#include "xil_io.h"
#include "xparameters.h"
#include "xil_printf.h"
#include <stdint.h>

#define GPIO_TRIGGER_BASE   0x40000000
#define BRAM_BASE           0xC0000000
#define UART_BASE           0x40600000

#define UART_RX_FIFO   (UART_BASE + 0x00)
#define UART_TX_FIFO   (UART_BASE + 0x04)
#define UART_STAT_REG  (UART_BASE + 0x08)

#define UART_STAT_RX_VALID  0x01
#define UART_STAT_TX_FULL   0x08

#define GPIO_STATUS_OFFSET     0x8
#define WRITEBACK_MARGIN_LOOPS 200
#define POLL_TIMEOUT_LOOPS     5000000
#define POLL_PRINT_INTERVAL    500000   // print a status sample every N poll iterations

static void uart_putc(uint8_t c) {
    while (Xil_In32(UART_STAT_REG) & UART_STAT_TX_FULL) {
    }
    Xil_Out32(UART_TX_FIFO, (uint32_t)c);
}

static uint8_t uart_getc(void) {
    while (!(Xil_In32(UART_STAT_REG) & UART_STAT_RX_VALID)) {
    }
    return (uint8_t)(Xil_In32(UART_RX_FIFO) & 0xFF);
}

static void uart_read_bytes_verbose(uint8_t *buf, int n, const char *label) {
    for (int i = 0; i < n; i++) {
        buf[i] = uart_getc();
        xil_printf("  [%s] byte %2d = 0x%02x\r\n", label, i, buf[i]);
    }
}

static void uart_write_bytes_verbose(const uint8_t *buf, int n) {
    for (int i = 0; i < n; i++) {
        uart_putc(buf[i]);
        xil_printf("  [ciphertext TX] byte %2d = 0x%02x sent\r\n", i, buf[i]);
    }
}

static uint32_t bytes_to_word_le(const uint8_t *b) {
    return ((uint32_t)b[0])       |
    ((uint32_t)b[1] << 8)  |
    ((uint32_t)b[2] << 16) |
    ((uint32_t)b[3] << 24);
}

static void word_to_bytes_le(uint32_t w, uint8_t *b) {
    b[0] = (uint8_t)(w & 0xFF);
    b[1] = (uint8_t)((w >> 8) & 0xFF);
    b[2] = (uint8_t)((w >> 16) & 0xFF);
    b[3] = (uint8_t)((w >> 24) & 0xFF);
}

static void delay_loops(volatile uint32_t count) {
    while (count--) {
        __asm__ __volatile__("nop");
    }
}

static void reverse16(uint8_t *buf) {
    for (int i = 0; i < 8; i++) {
        uint8_t tmp = buf[i];
        buf[i] = buf[15 - i];
        buf[15 - i] = tmp;
    }
}

int main(void) {
    uint8_t plaintext[16];
    uint8_t key[16];
    uint8_t ciphertext[16];
    uint32_t iteration = 0;

    xil_printf("\r\n\r\n");
    xil_printf("========================================\r\n");
    xil_printf("AES UART firmware - VERBOSE DEBUG BUILD\r\n");
    xil_printf("========================================\r\n");
    xil_printf("GPIO_TRIGGER_BASE = 0x%08x\r\n", GPIO_TRIGGER_BASE);
    xil_printf("BRAM_BASE         = 0x%08x\r\n", BRAM_BASE);
    xil_printf("UART_BASE         = 0x%08x\r\n", UART_BASE);
    xil_printf("GPIO status offset= 0x%08x (full addr 0x%08x)\r\n",
               GPIO_STATUS_OFFSET, GPIO_TRIGGER_BASE + GPIO_STATUS_OFFSET);
    xil_printf("\r\n");

    xil_printf("[startup] Reading GPIO channel 1 (trigger out) data reg at 0x%08x: 0x%08x\r\n",
               GPIO_TRIGGER_BASE, Xil_In32(GPIO_TRIGGER_BASE));
    xil_printf("[startup] Reading GPIO channel 2 (status in) data reg at 0x%08x: 0x%08x\r\n",
               GPIO_TRIGGER_BASE + GPIO_STATUS_OFFSET, Xil_In32(GPIO_TRIGGER_BASE + GPIO_STATUS_OFFSET));
    xil_printf("[startup] Reading GPIO channel 1 tri-state reg at 0x%08x: 0x%08x\r\n",
               GPIO_TRIGGER_BASE + 0x4, Xil_In32(GPIO_TRIGGER_BASE + 0x4));
    xil_printf("[startup] Reading GPIO channel 2 tri-state reg at 0x%08x: 0x%08x\r\n",
               GPIO_TRIGGER_BASE + 0xC, Xil_In32(GPIO_TRIGGER_BASE + 0xC));
    xil_printf("\r\n");

    for (;;) {
        iteration++;
        xil_printf("---------- Iteration %u ----------\r\n", iteration);
        xil_printf("[recv] Waiting for 16 plaintext bytes...\r\n");
        uart_read_bytes_verbose(plaintext, 16, "plaintext");
        xil_printf("[recv] Waiting for 16 key bytes...\r\n");
        uart_read_bytes_verbose(key, 16, "key");

        xil_printf("[fixup] Reversing plaintext/key byte order for AES state layout:\r\n");
        reverse16(plaintext);
        reverse16(key);
        for (int i = 0; i < 16; i++) {
            xil_printf("  [plaintext reversed] byte %2d = 0x%02x\r\n", i, plaintext[i]);
        }
        for (int i = 0; i < 16; i++) {
            xil_printf("  [key reversed]       byte %2d = 0x%02x\r\n", i, key[i]);
        }

        xil_printf("[bram] Writing plaintext words:\r\n");
        for (int w = 0; w < 4; w++) {
            uint32_t word = bytes_to_word_le(&plaintext[w * 4]);
            uint32_t addr = BRAM_BASE + (w * 4);
            Xil_Out32(addr, word);
            xil_printf("  addr 0x%08x <= 0x%08x\r\n", addr, word);
        }
        xil_printf("[bram] Writing key words:\r\n");
        for (int w = 0; w < 4; w++) {
            uint32_t word = bytes_to_word_le(&key[w * 4]);
            uint32_t addr = BRAM_BASE + 16 + (w * 4);
            Xil_Out32(addr, word);
            xil_printf("  addr 0x%08x <= 0x%08x\r\n", addr, word);
        }

        xil_printf("[bram] Reading back plaintext/key region to verify write:\r\n");
        for (int w = 0; w < 8; w++) {
            uint32_t addr = BRAM_BASE + (w * 4);
            xil_printf("  addr 0x%08x => 0x%08x\r\n", addr, Xil_In32(addr));
        }

        uint32_t pre_status = Xil_In32(GPIO_TRIGGER_BASE + GPIO_STATUS_OFFSET);
        xil_printf("[gpio] Status reg BEFORE trigger pulse: 0x%08x\r\n", pre_status);

        xil_printf("[gpio] Pulsing trigger: writing 0x1 to 0x%08x\r\n", GPIO_TRIGGER_BASE);
        Xil_Out32(GPIO_TRIGGER_BASE, 0x1);
        xil_printf("[gpio] Readback immediately after write-1: 0x%08x\r\n", Xil_In32(GPIO_TRIGGER_BASE));
        xil_printf("[gpio] Writing 0x0 to 0x%08x\r\n", GPIO_TRIGGER_BASE);
        Xil_Out32(GPIO_TRIGGER_BASE, 0x0);
        xil_printf("[gpio] Readback immediately after write-0: 0x%08x\r\n", Xil_In32(GPIO_TRIGGER_BASE));

        xil_printf("[poll] Entering poll loop, timeout=%u iterations, sampling every %u\r\n",
                   (unsigned)POLL_TIMEOUT_LOOPS, (unsigned)POLL_PRINT_INTERVAL);
        {
            uint32_t timeout = POLL_TIMEOUT_LOOPS;
            uint32_t status_val = 0;
            uint32_t last_printed_at = POLL_TIMEOUT_LOOPS;
            int completed = 0;
            while (1) {
                status_val = Xil_In32(GPIO_TRIGGER_BASE + GPIO_STATUS_OFFSET);
                if (status_val & 0x1) {
                    completed = 1;
                    break;
                }
                if (last_printed_at - timeout >= POLL_PRINT_INTERVAL) {
                    xil_printf("  [poll] timeout_left=%u status=0x%08x\r\n", timeout, status_val);
                    last_printed_at = timeout;
                }
                if (--timeout == 0) {
                    break;
                }
            }
            if (completed) {
                xil_printf("[poll] op_complete DETECTED. status=0x%08x, timeout_left=%u\r\n",
                           status_val, timeout);
            } else {
                xil_printf("[poll] *** TIMEOUT *** never saw bit0 set. Final status=0x%08x\r\n", status_val);
            }
            delay_loops(WRITEBACK_MARGIN_LOOPS);
        }

        xil_printf("[bram] Reading ciphertext region:\r\n");
        for (int w = 0; w < 4; w++) {
            uint32_t addr = BRAM_BASE + 32 + (w * 4);
            uint32_t word = Xil_In32(addr);
            xil_printf("  addr 0x%08x => 0x%08x\r\n", addr, word);
            word_to_bytes_le(word, &ciphertext[w * 4]);
        }

        xil_printf("[fixup] Reversing ciphertext byte order before TX:\r\n");
        reverse16(ciphertext);
        for (int i = 0; i < 16; i++) {
            xil_printf("  [ciphertext reversed] byte %2d = 0x%02x\r\n", i, ciphertext[i]);
        }

        xil_printf("[send] Transmitting ciphertext:\r\n");
        uart_write_bytes_verbose(ciphertext, 16);
        xil_printf("---------- Iteration %u complete ----------\r\n\r\n", iteration);
    }

    return 0;
}
