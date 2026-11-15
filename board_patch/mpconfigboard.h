#define MODULE_NAME "GENERIC_S3"
#define MICROPY_HW_BOARD_NAME "ESP32S3 (LVGL8.3-PCNT-GPIO19/20-Freed)"
#define MICROPY_HW_MCU_NAME "ESP32S3"

#define MICROPY_PY_MACHINE_DAC (0)

// [核心释放] 禁用原生 USB-SERIAL-JTAG 与 USB-OTG 控制器，释放 GPIO19(D-) 和 GPIO20(D+) 为普通GPIO
#define MICROPY_HW_ENABLE_USB_SERIAL_JTAG (0)
#define MICROPY_HW_ENABLE_USBDEV          (0)

// [串口重定向] 强制将 MicroPython REPL 绑定至硬件物理串口 UART0 (由板载第二个独立USB口芯片连接)
#define MICROPY_HW_ENABLE_UART_REPL       (1)
#define MICROPY_HW_UART_REPL              (UART_NUM_0)
#define MICROPY_HW_UART_REPL_BAUD         (115200)

// 标定 ESP32-S3 默认 UART0 物理引脚 (TXD0=GPIO43, RXD0=GPIO44)
#define MICROPY_HW_UART0_TX               (43)
#define MICROPY_HW_UART0_RX               (44)

// [全量扩展IO] 开启 GPIO47 (I2C SCL) 与 GPIO48 (WS2812 RGB)
#define MICROPY_HW_ESP32S3_EXTENDED_IO    (1)

// [硬件 PCNT 编码器]
#define MICROPY_PY_MACHINE_ENCODER        (1)
#define MICROPY_PY_MACHINE_COUNTER        (1)
#define MICROPY_PY_MACHINE_PCNT           (1)
