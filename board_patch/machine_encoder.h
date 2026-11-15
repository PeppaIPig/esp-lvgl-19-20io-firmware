/*
 * MicroPython machine.Encoder and machine.Counter hardware driver for ESP32 / ESP32-S3
 * Based on ESP-IDF PCNT (Pulse Counter) Hardware Peripheral
 */

#ifndef MICROPY_INCLUDED_MACHINE_ENCODER_H
#define MICROPY_INCLUDED_MACHINE_ENCODER_H

#include "py/obj.h"
#include <stdint.h>

#define USE_INT64 1
#ifdef USE_INT64
typedef int64_t counter_t;
#else
typedef int32_t counter_t;
#endif

#define INT16_ROLL ((counter_t)32767)
#define FILTER_MAX 1023

enum edge_bit_mask {
    RISING = 0x1,
    FALLING = 0x2
};

#define COUNTER_UP   (-2)
#define COUNTER_DOWN (-4)

typedef struct _mp_pcnt_obj_t {
    mp_obj_base_t base;
    int unit;

    int aPinNumber;
    int bPinNumber;

    volatile counter_t counter;
    volatile counter_t counter_accum;

    counter_t match;
    counter_t counter_match;
    mp_obj_t handler_match;
    mp_obj_t handler_zero;
    mp_obj_t handler_roll_over;
    mp_obj_t handler_roll_under;
    uint32_t event_status;

    int filter;
    enum edge_bit_mask edge;
    int8_t phases;
} mp_pcnt_obj_t;

extern const mp_obj_type_t machine_Encoder_type;
extern const mp_obj_type_t machine_Counter_type;

void machine_encoder_deinit_all(void);

#endif // MICROPY_INCLUDED_MACHINE_ENCODER_H
