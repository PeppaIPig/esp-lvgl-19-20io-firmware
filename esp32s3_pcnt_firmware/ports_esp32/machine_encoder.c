/*
 * This file is part of the MicroPython project, http://micropython.org/
 *
 * ESP32-S3 / ESP32 Hardware Quadrature Encoder & Counter based on PCNT
 */

#include "py/mpprint.h"
#include "py/runtime.h"
#include "mphalport.h"
#include "modmachine.h"

#if MICROPY_PY_MACHINE_PCNT || MICROPY_PY_MACHINE_ENCODER

#include "rom/gpio.h"
#include "driver/gpio.h"
#include "driver/pcnt.h"
#include "soc/pcnt_struct.h"
#include "hal/pcnt_ll.h"
#include "esp_err.h"

#include "machine_encoder.h"
#include "machine_pin.h"

extern const mp_obj_type_t machine_pin_type;

#define GET_INT mp_obj_get_int_truncated

static pcnt_isr_handle_t pcnt_isr_handle = NULL;
static mp_pcnt_obj_t *pcnts[PCNT_UNIT_MAX] = { NULL };

#define check_esp_err(x) do { esp_err_t _err = (x); if (_err != ESP_OK) { mp_raise_msg_varg(&mp_type_RuntimeError, MP_ERROR_TEXT("PCNT error 0x%x"), _err); } } while (0)

static void IRAM_ATTR pcnt_intr_handler(void *arg) {
    uint32_t intr_status = PCNT.int_st.val;
    for (int id = 0; id < PCNT_UNIT_MAX; ++id) {
        if (intr_status & BIT(id)) {
            mp_pcnt_obj_t *self = pcnts[id];
            if (self != NULL) {
                pcnt_get_event_status(id, &self->event_status);
                if (self->event_status & PCNT_EVT_H_LIM) {
                    self->counter += INT16_ROLL;
                    self->counter_accum += INT16_ROLL;
                    if (self->handler_roll_over != MP_OBJ_NULL) {
                        mp_sched_schedule(self->handler_roll_over, MP_OBJ_FROM_PTR(self));
                        mp_hal_wake_main_task_from_isr();
                    }
                } else if (self->event_status & PCNT_EVT_L_LIM) {
                    self->counter -= INT16_ROLL;
                    self->counter_accum -= INT16_ROLL;
                    if (self->handler_roll_under != MP_OBJ_NULL) {
                        mp_sched_schedule(self->handler_roll_under, MP_OBJ_FROM_PTR(self));
                        mp_hal_wake_main_task_from_isr();
                    }
                }
                if (self->event_status & PCNT_EVT_THRES_1) {
                    if (self->counter_accum == self->counter_match) {
                        mp_sched_schedule(self->handler_match, MP_OBJ_FROM_PTR(self));
                        mp_hal_wake_main_task_from_isr();
                    }
                } else if (self->event_status & PCNT_EVT_THRES_0) {
                    if (self->counter_accum == self->counter_match) {
                        mp_sched_schedule(self->handler_match, MP_OBJ_FROM_PTR(self));
                        mp_hal_wake_main_task_from_isr();
                    }
                }
                if (self->event_status & PCNT_EVT_ZERO) {
                    if (self->counter == 0) {
                        mp_sched_schedule(self->handler_zero, MP_OBJ_FROM_PTR(self));
                        mp_hal_wake_main_task_from_isr();
                    }
                }
            }
        }
    }
    PCNT.int_clr.val = intr_status;
}

static void register_isr_handler(void) {
    if (pcnt_isr_handle == NULL) {
        check_esp_err(pcnt_isr_register(pcnt_intr_handler, (void *)0, (int)0, &pcnt_isr_handle));
        if (pcnt_isr_handle == NULL) {
            mp_raise_msg(&mp_type_Exception, MP_ERROR_TEXT("PCNT wrap interrupt registration failed"));
        }
        PCNT.int_clr.val = PCNT.int_st.val;
    }
}

static gpio_num_t pin_or_int(const mp_obj_t arg) {
    if (mp_obj_is_small_int(arg)) {
        return (gpio_num_t)MP_OBJ_SMALL_INT_VALUE(arg);
    } else {
        return machine_pin_get_id(arg);
    }
}

// 1 / 80MHz = 12.5ns
#define ns_to_filter(ns) ((ns * (APB_CLK_FREQ / 1000000) + 500) / 1000)
#define filter_to_ns(filter) (filter * 1000 / (APB_CLK_FREQ / 1000000))

static uint16_t get_filter_value_ns(pcnt_unit_t unit) {
    uint16_t value;
    check_esp_err(pcnt_get_filter_value(unit, &value));
    return filter_to_ns(value);
}

static void set_filter_value(pcnt_unit_t unit, int16_t value) {
    if (value < 0) {
        value = 0;
    } else if (value > FILTER_MAX) {
        value = FILTER_MAX;
    }
    check_esp_err(pcnt_set_filter_value(unit, value));
    if (value > 0) {
        check_esp_err(pcnt_filter_enable(unit));
    } else {
        check_esp_err(pcnt_filter_disable(unit));
    }
}

static void set_filter_and_start(mp_pcnt_obj_t *self) {
    check_esp_err(pcnt_event_enable(self->unit, PCNT_EVT_H_LIM));
    check_esp_err(pcnt_event_enable(self->unit, PCNT_EVT_L_LIM));
    set_filter_value(self->unit, self->filter);
    check_esp_err(pcnt_counter_pause(self->unit));
    check_esp_err(pcnt_counter_clear(self->unit));
    self->counter_accum = 0;
    self->counter = 0;
    check_esp_err(pcnt_intr_enable(self->unit));
    check_esp_err(pcnt_counter_resume(self->unit));
}

static void pcnt_deinit(mp_pcnt_obj_t *self) {
    if (self == NULL) {
        return;
    }
    pcnt_counter_pause(self->unit);
    pcnt_intr_disable(self->unit);
    pcnts[self->unit] = NULL;
}

void machine_encoder_deinit_all(void) {
    for (int id = 0; id < PCNT_UNIT_MAX; ++id) {
        pcnt_deinit(pcnts[id]);
    }
    if (pcnt_isr_handle != NULL) {
        pcnt_isr_unregister(pcnt_isr_handle);
        pcnt_isr_handle = NULL;
    }
}

static mp_obj_t machine_PCNT_deinit(mp_obj_t self_obj) {
    mp_pcnt_obj_t *self = MP_OBJ_TO_PTR(self_obj);
    pcnt_deinit(self);
    return mp_const_none;
}
static MP_DEFINE_CONST_FUN_OBJ_1(machine_PCNT_deinit_obj, machine_PCNT_deinit);

static mp_obj_t machine_PCNT_filter(size_t n_args, const mp_obj_t *args) {
    mp_pcnt_obj_t *self = MP_OBJ_TO_PTR(args[0]);
    uint16_t value = get_filter_value_ns(self->unit);
    if (n_args > 1) {
        set_filter_value(self->unit, ns_to_filter(mp_obj_get_int(args[1])));
    }
    return MP_OBJ_NEW_SMALL_INT(value);
}
static MP_DEFINE_CONST_FUN_OBJ_VAR_BETWEEN(machine_PCNT_filter_obj, 1, 2, machine_PCNT_filter);

static mp_obj_t machine_PCNT_count(size_t n_args, const mp_obj_t *args) {
    mp_pcnt_obj_t *self = MP_OBJ_TO_PTR(args[0]);

    check_esp_err(pcnt_intr_disable(self->unit));

    int16_t count;
    check_esp_err(pcnt_get_counter_value(self->unit, &count));
    counter_t counter = self->counter;

    if (n_args > 1) {
        counter_t new_counter = GET_INT(args[1]);
        check_esp_err(pcnt_counter_clear(self->unit));
        self->counter_accum = new_counter;
        self->counter = new_counter;
        count = 0;
        counter = new_counter;
    }

    check_esp_err(pcnt_intr_enable(self->unit));

    return mp_obj_new_int_from_ll(counter + count);
}
static MP_DEFINE_CONST_FUN_OBJ_VAR_BETWEEN(machine_PCNT_count_obj, 1, 2, machine_PCNT_count);

static mp_obj_t machine_PCNT_pause(mp_obj_t self_obj) {
    mp_pcnt_obj_t *self = MP_OBJ_TO_PTR(self_obj);
    check_esp_err(pcnt_counter_pause(self->unit));
    return mp_const_none;
}
static MP_DEFINE_CONST_FUN_OBJ_1(machine_PCNT_pause_obj, machine_PCNT_pause);

static mp_obj_t machine_PCNT_resume(mp_obj_t self_obj) {
    mp_pcnt_obj_t *self = MP_OBJ_TO_PTR(self_obj);
    check_esp_err(pcnt_counter_resume(self->unit));
    return mp_const_none;
}
static MP_DEFINE_CONST_FUN_OBJ_1(machine_PCNT_resume_obj, machine_PCNT_resume);

static mp_obj_t machine_PCNT_id(mp_obj_t self_obj) {
    mp_pcnt_obj_t *self = MP_OBJ_TO_PTR(self_obj);
    return MP_OBJ_NEW_SMALL_INT(self->unit);
}
static MP_DEFINE_CONST_FUN_OBJ_1(machine_PCNT_id_obj, machine_PCNT_id);

static mp_obj_t machine_PCNT_status(mp_obj_t self_obj) {
    mp_pcnt_obj_t *self = MP_OBJ_TO_PTR(self_obj);
    return MP_OBJ_NEW_SMALL_INT(self->event_status);
}
static MP_DEFINE_CONST_FUN_OBJ_1(machine_PCNT_status_obj, machine_PCNT_status);

#define COMMON_METHODS \
    { MP_ROM_QSTR(MP_QSTR_deinit), MP_ROM_PTR(&machine_PCNT_deinit_obj) }, \
    { MP_ROM_QSTR(MP_QSTR___del__), MP_ROM_PTR(&machine_PCNT_deinit_obj) }, \
    { MP_ROM_QSTR(MP_QSTR_value), MP_ROM_PTR(&machine_PCNT_count_obj) }, \
    { MP_ROM_QSTR(MP_QSTR_filter_ns), MP_ROM_PTR(&machine_PCNT_filter_obj) }, \
    { MP_ROM_QSTR(MP_QSTR_pause), MP_ROM_PTR(&machine_PCNT_pause_obj) }, \
    { MP_ROM_QSTR(MP_QSTR_resume), MP_ROM_PTR(&machine_PCNT_resume_obj) }, \
    { MP_ROM_QSTR(MP_QSTR_id), MP_ROM_PTR(&machine_PCNT_id_obj) }, \
    { MP_ROM_QSTR(MP_QSTR_status), MP_ROM_PTR(&machine_PCNT_status_obj) }

#define COMMON_CONSTANTS \
    { MP_ROM_QSTR(MP_QSTR_IRQ_ZERO), MP_ROM_INT(PCNT_EVT_ZERO) }, \
    { MP_ROM_QSTR(MP_QSTR_IRQ_ROLL_OVER), MP_ROM_INT(PCNT_EVT_H_LIM) }, \
    { MP_ROM_QSTR(MP_QSTR_IRQ_ROLL_UNDER), MP_ROM_INT(PCNT_EVT_L_LIM) }, \
    { MP_ROM_QSTR(MP_QSTR_IRQ_MATCH), MP_ROM_INT(PCNT_EVT_THRES_1) }

// =================================================================
// class Counter
// =================================================================
static void mp_machine_Counter_init_helper(mp_pcnt_obj_t *self, size_t n_args, const mp_obj_t *pos_args, mp_map_t *kw_args) {
    enum { ARG_src, ARG_direction, ARG_edge, ARG_filter_ns };
    const mp_arg_t allowed_args[] = {
        { MP_QSTR_src, MP_ARG_OBJ, {.u_obj = MP_OBJ_NULL} },
        { MP_QSTR_direction, MP_ARG_OBJ, {.u_obj = MP_OBJ_NULL} },
        { MP_QSTR_edge, MP_ARG_KW_ONLY | MP_ARG_INT, {.u_int = self->edge} },
        { MP_QSTR_filter_ns, MP_ARG_KW_ONLY | MP_ARG_INT, {.u_int = -1} },
    };

    mp_arg_val_t args[MP_ARRAY_SIZE(allowed_args)];
    mp_arg_parse_all(n_args, pos_args, kw_args, MP_ARRAY_SIZE(allowed_args), allowed_args, args);

    self->bPinNumber = COUNTER_UP;
    self->edge = args[ARG_edge].u_int;

    if (args[ARG_src].u_obj != MP_OBJ_NULL) {
        self->aPinNumber = pin_or_int(args[ARG_src].u_obj);
    }
    if (self->aPinNumber == PCNT_PIN_NOT_USED) {
        mp_raise_ValueError(MP_ERROR_TEXT("src"));
    }

    mp_obj_t direction = args[ARG_direction].u_obj;
    if (direction != MP_OBJ_NULL) {
        if (mp_obj_is_type(direction, &machine_pin_type) || mp_obj_is_small_int(direction)) {
            self->bPinNumber = pin_or_int(direction);
        } else {
            self->bPinNumber = mp_obj_get_int(direction);
        }
    }

    pcnt_config_t r_enc_config;
    r_enc_config.unit = self->unit;
    r_enc_config.counter_h_lim = INT16_ROLL;
    r_enc_config.counter_l_lim = -INT16_ROLL;

    r_enc_config.channel = PCNT_CHANNEL_0;
    r_enc_config.pos_mode = (self->edge & RISING) ? PCNT_COUNT_INC : PCNT_COUNT_DIS;
    r_enc_config.neg_mode = (self->edge & FALLING) ? PCNT_COUNT_INC : PCNT_COUNT_DIS;
    r_enc_config.pulse_gpio_num = self->aPinNumber;
    r_enc_config.ctrl_gpio_num = (self->bPinNumber >= 0) ? self->bPinNumber : PCNT_PIN_NOT_USED;

    if (self->bPinNumber == COUNTER_UP || self->bPinNumber < 0) {
        r_enc_config.lctrl_mode = PCNT_MODE_KEEP;
        r_enc_config.hctrl_mode = PCNT_MODE_REVERSE;
    } else {
        r_enc_config.lctrl_mode = PCNT_MODE_REVERSE;
        r_enc_config.hctrl_mode = PCNT_MODE_KEEP;
    }
    check_esp_err(pcnt_unit_config(&r_enc_config));

    r_enc_config.channel = PCNT_CHANNEL_1;
    r_enc_config.lctrl_mode = PCNT_MODE_DISABLE;
    r_enc_config.hctrl_mode = PCNT_MODE_DISABLE;
    r_enc_config.pos_mode = PCNT_COUNT_DIS;
    r_enc_config.neg_mode = PCNT_COUNT_DIS;
    check_esp_err(pcnt_unit_config(&r_enc_config));

    if (args[ARG_filter_ns].u_int != -1) {
        self->filter = ns_to_filter(args[ARG_filter_ns].u_int);
    }
    set_filter_and_start(self);
}

static mp_obj_t machine_Counter_make_new(const mp_obj_type_t *type, size_t n_args, size_t n_kw, const mp_obj_t *args) {
    mp_arg_check_num(n_args, n_kw, 1, 4, true);

    int unit = mp_obj_get_int(args[0]);
    if (unit < 0 || unit >= PCNT_UNIT_MAX) {
        mp_raise_msg_varg(&mp_type_ValueError, MP_ERROR_TEXT("id must be from 0 to %d"), PCNT_UNIT_MAX - 1);
    }
    if (pcnts[unit] != NULL) {
        mp_raise_msg(&mp_type_RuntimeError, MP_ERROR_TEXT("PCNT unit already used"));
    }

    mp_pcnt_obj_t *self = mp_obj_malloc(mp_pcnt_obj_t, type);
    self->unit = unit;
    self->aPinNumber = PCNT_PIN_NOT_USED;
    self->bPinNumber = PCNT_PIN_NOT_USED;
    self->edge = RISING;
    self->filter = 0;
    self->phases = 0;

    pcnts[self->unit] = self;
    register_isr_handler();

    if (n_args > 1) {
        self->aPinNumber = pin_or_int(args[1]);
    }

    mp_map_t kw_args;
    mp_map_init_fixed_table(&kw_args, n_kw, args + n_args);
    mp_machine_Counter_init_helper(self, n_args - 1, args + 1, &kw_args);

    return MP_OBJ_FROM_PTR(self);
}

static const mp_rom_map_elem_t machine_Counter_locals_dict_table[] = {
    COMMON_METHODS,
    COMMON_CONSTANTS,
    { MP_ROM_QSTR(MP_QSTR_RISING), MP_ROM_INT(RISING) },
    { MP_ROM_QSTR(MP_QSTR_FALLING), MP_ROM_INT(FALLING) },
    { MP_ROM_QSTR(MP_QSTR_UP), MP_ROM_INT(COUNTER_UP) },
    { MP_ROM_QSTR(MP_QSTR_DOWN), MP_ROM_INT(COUNTER_DOWN) },
};
static MP_DEFINE_CONST_DICT(machine_Counter_locals_dict, machine_Counter_locals_dict_table);

MP_DEFINE_CONST_OBJ_TYPE(
    machine_Counter_type,
    MP_QSTR_Counter,
    MP_TYPE_FLAG_NONE,
    make_new, machine_Counter_make_new,
    locals_dict, &machine_Counter_locals_dict
);

// =================================================================
// class Encoder
// =================================================================
static void mp_machine_Encoder_init_helper(mp_pcnt_obj_t *self, size_t n_args, const mp_obj_t *pos_args, mp_map_t *kw_args) {
    enum { ARG_phase_a, ARG_phase_b, ARG_phases, ARG_x124, ARG_filter_ns };
    static const mp_arg_t allowed_args[] = {
        { MP_QSTR_phase_a, MP_ARG_OBJ, {.u_obj = MP_OBJ_NULL} },
        { MP_QSTR_phase_b, MP_ARG_OBJ, {.u_obj = MP_OBJ_NULL} },
        { MP_QSTR_phases, MP_ARG_KW_ONLY | MP_ARG_INT, {.u_int = -1} },
        { MP_QSTR_x124, MP_ARG_KW_ONLY | MP_ARG_INT, {.u_int = -1} },
        { MP_QSTR_filter_ns, MP_ARG_KW_ONLY | MP_ARG_INT, {.u_int = -1} },
    };

    mp_arg_val_t args[MP_ARRAY_SIZE(allowed_args)];
    mp_arg_parse_all(n_args, pos_args, kw_args, MP_ARRAY_SIZE(allowed_args), allowed_args, args);

    if (args[ARG_phase_a].u_obj != MP_OBJ_NULL) {
        self->aPinNumber = pin_or_int(args[ARG_phase_a].u_obj);
    }
    if (self->aPinNumber == PCNT_PIN_NOT_USED) {
        mp_raise_ValueError(MP_ERROR_TEXT("phase_a required"));
    }

    if (args[ARG_phase_b].u_obj != MP_OBJ_NULL) {
        self->bPinNumber = pin_or_int(args[ARG_phase_b].u_obj);
    }
    if (self->bPinNumber == PCNT_PIN_NOT_USED) {
        mp_raise_ValueError(MP_ERROR_TEXT("phase_b required"));
    }

    int p = args[ARG_phases].u_int;
    if (p == -1 && args[ARG_x124].u_int != -1) {
        p = args[ARG_x124].u_int;
    }
    if (p != -1) {
        if (p == 1 || p == 2 || p == 4) {
            self->phases = p;
        } else {
            mp_raise_ValueError(MP_ERROR_TEXT("phases must be 1, 2, or 4"));
        }
    } else if (self->phases == 0) {
        self->phases = 4; // default full quadrature 4x
    }

    pcnt_config_t r_enc_config;
    r_enc_config.unit = self->unit;
    r_enc_config.channel = PCNT_CHANNEL_0;
    r_enc_config.pulse_gpio_num = self->aPinNumber;
    r_enc_config.ctrl_gpio_num = self->bPinNumber;

    r_enc_config.pos_mode = PCNT_COUNT_INC;
    r_enc_config.neg_mode = (self->phases != 1) ? PCNT_COUNT_DEC : PCNT_COUNT_DIS;
    r_enc_config.lctrl_mode = PCNT_MODE_KEEP;
    r_enc_config.hctrl_mode = PCNT_MODE_REVERSE;

    r_enc_config.counter_h_lim = INT16_ROLL;
    r_enc_config.counter_l_lim = -INT16_ROLL;
    check_esp_err(pcnt_unit_config(&r_enc_config));

    if (self->phases == 4) {
        // Full quadrature: configure Channel 1 with swapped pins
        r_enc_config.channel = PCNT_CHANNEL_1;
        r_enc_config.pulse_gpio_num = self->bPinNumber;
        r_enc_config.ctrl_gpio_num = self->aPinNumber;
        r_enc_config.pos_mode = PCNT_COUNT_INC;
        r_enc_config.neg_mode = PCNT_COUNT_DEC;
        r_enc_config.lctrl_mode = PCNT_MODE_REVERSE;
        r_enc_config.hctrl_mode = PCNT_MODE_KEEP;
        check_esp_err(pcnt_unit_config(&r_enc_config));
    } else {
        r_enc_config.channel = PCNT_CHANNEL_1;
        r_enc_config.pos_mode = PCNT_COUNT_DIS;
        r_enc_config.neg_mode = PCNT_COUNT_DIS;
        r_enc_config.lctrl_mode = PCNT_MODE_DISABLE;
        r_enc_config.hctrl_mode = PCNT_MODE_DISABLE;
        check_esp_err(pcnt_unit_config(&r_enc_config));
    }

    if (args[ARG_filter_ns].u_int != -1) {
        self->filter = ns_to_filter(args[ARG_filter_ns].u_int);
    }
    set_filter_and_start(self);
}

static mp_obj_t machine_Encoder_make_new(const mp_obj_type_t *type, size_t n_args, size_t n_kw, const mp_obj_t *args) {
    mp_arg_check_num(n_args, n_kw, 1, 5, true);

    int unit = mp_obj_get_int(args[0]);
    if (unit < 0 || unit >= PCNT_UNIT_MAX) {
        mp_raise_msg_varg(&mp_type_ValueError, MP_ERROR_TEXT("id must be from 0 to %d"), PCNT_UNIT_MAX - 1);
    }
    if (pcnts[unit] != NULL) {
        mp_raise_msg(&mp_type_RuntimeError, MP_ERROR_TEXT("PCNT unit already used"));
    }

    mp_pcnt_obj_t *self = mp_obj_malloc(mp_pcnt_obj_t, type);
    self->unit = unit;
    self->aPinNumber = PCNT_PIN_NOT_USED;
    self->bPinNumber = PCNT_PIN_NOT_USED;
    self->filter = 0;
    self->phases = 4; // Default 4x quadrature

    pcnts[self->unit] = self;
    register_isr_handler();

    if (n_args >= 2) {
        self->aPinNumber = pin_or_int(args[1]);
    }
    if (n_args >= 3) {
        self->bPinNumber = pin_or_int(args[2]);
    }

    mp_map_t kw_args;
    mp_map_init_fixed_table(&kw_args, n_kw, args + n_args);
    mp_machine_Encoder_init_helper(self, n_args - 1, args + 1, &kw_args);

    return MP_OBJ_FROM_PTR(self);
}

static const mp_rom_map_elem_t machine_Encoder_locals_dict_table[] = {
    COMMON_METHODS,
    COMMON_CONSTANTS
};
static MP_DEFINE_CONST_DICT(machine_Encoder_locals_dict, machine_Encoder_locals_dict_table);

MP_DEFINE_CONST_OBJ_TYPE(
    machine_Encoder_type,
    MP_QSTR_Encoder,
    MP_TYPE_FLAG_NONE,
    make_new, machine_Encoder_make_new,
    locals_dict, &machine_Encoder_locals_dict
);

#endif // MICROPY_PY_MACHINE_PCNT || MICROPY_PY_MACHINE_ENCODER
