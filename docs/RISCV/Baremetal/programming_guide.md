# RISC-V Baremetal 编程完全指南

本教程将从零开始，带你深入理解 RISC-V 架构下 Baremetal（裸机）程序的开发。

---

## 目录

1. [Baremetal 概述](#1-baremetal-概述)
2. [启动代码 (crt.S) 详解](#2-启动代码-crts-详解)
3. [Linker Script 详解](#3-linker-script-详解)
4. [Syscalls 与 HTIF 协议](#4-syscalls-与-htif-协议)
5. [C 标准库函数实现](#5-c-标准库函数实现)
6. [异常与中断处理](#6-异常与中断处理)
7. [编译与链接配置](#7-编译与链接配置)
8. [调试技巧](#8-调试技巧)
9. [完整示例项目](#9-完整示例项目)

---

## 1. Baremetal 概述

### 1.1 什么是 Baremetal

**Baremetal**（裸机）指的是程序直接运行在硬件上，没有操作系统支持。程序需要自己处理：

- 硬件初始化
- 内存管理
- I/O 操作
- 异常处理

```
┌─────────────────────────────────────────────────────────────┐
│                    Hosted 环境                               │
├─────────────────────────────────────────────────────────────┤
│  Application                                                │
│      ↓                                                      │
│  C Library (glibc/newlib)                                   │
│      ↓                                                      │
│  Operating System (Linux/RTOS)                              │
│      ↓                                                      │
│  Hardware                                                   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Baremetal 环境                            │
├─────────────────────────────────────────────────────────────┤
│  Application                                                │
│      ↓                                                      │
│  Mini Runtime (自己实现)                                     │
│      ↓                                                      │
│  Hardware (直接控制)                                         │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 为什么需要 Baremetal

| 场景 | 说明 |
|------|------|
| **嵌入式系统** | 资源受限，无法运行完整 OS |
| **性能分析** | 消除 OS 干扰，精确测量指令数 |
| **硬件驱动开发** | 直接操作硬件寄存器 |
| **安全关键系统** | 需要完全控制执行环境 |
| **Bootloader** | OS 启动前的初始化代码 |

### 1.3 RISC-V 特权级别

RISC-V 定义了三种特权级别：

```
┌─────────────────────────────────────────┐
│  Level 3: Machine Mode (M-mode)         │  ← 最高权限，硬件复位后的默认模式
│  - 完全硬件访问权限                        │
│  - 可访问所有 CSR 寄存器                   │
│  - Baremetal 程序通常运行在此模式          │
├─────────────────────────────────────────┤
│  Level 1: Supervisor Mode (S-mode)      │  ← OS 内核运行模式
│  - 可管理虚拟内存                          │
│  - 可处理系统调用                          │
├─────────────────────────────────────────┤
│  Level 0: User Mode (U-mode)            │  ← 最低权限
│  - 用户程序运行模式                        │
│  - 受保护的执行环境                        │
└─────────────────────────────────────────┘
```

### 1.4 程序执行生命周期

```
CPU 复位
    │
    ▼
┌─────────────────┐
│ 1. _start       │  ← crt.S 中的入口点
│    (汇编)       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 2. 硬件初始化    │  ← 设置 CSR、启用 FPU/Vector
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 3. 栈/GP 初始化  │  ← 为 C 代码准备运行环境
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 4. BSS 清零      │  ← 清空未初始化全局变量区
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 5. _init / main │  ← 进入 C 代码
│    (C 代码)     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 6. exit()       │  ← 程序退出
└─────────────────┘
```

---

## 2. 启动代码 (crt.S) 详解

启动代码是 CPU 复位后执行的第一段代码，负责建立 C 语言运行环境。

### 2.1 基本结构

```asm
# ============================================================
# crt.S - C Runtime Startup for RISC-V Baremetal
# ============================================================

# CSR 位定义
#define MSTATUS_FS    0x00006000   # 浮点状态位
#define MSTATUS_VS    0x00000600   # 向量状态位
#define MSTATUS_MPP   0x00001800   # Machine Previous Privilege

# 根据 XLEN 选择正确的加载/存储指令
#if __riscv_xlen == 64
# define LREG ld                    # 64-bit 加载
# define SREG sd                    # 64-bit 存储
# define REGBYTES 8                 # 寄存器字节数
#else
# define LREG lw                    # 32-bit 加载
# define SREG sw                    # 32-bit 存储
# define REGBYTES 4
#endif

# ============================================================
# .text.init 段 - 必须放在程序最开始
# ============================================================
  .section ".text.init"
  .globl _start

_start:
  # --------------------------------------------------------
  # 第1步: 清零所有通用寄存器
  # 目的: 确保寄存器处于已知状态，避免使用未初始化的值
  # --------------------------------------------------------
  li  x1, 0
  li  x2, 0
  li  x3, 0
  # ... x4 到 x30 ...
  li  x31, 0

  # --------------------------------------------------------
  # 第2步: 启用 FPU 和 Vector 扩展
  # MSTATUS.FS = 01 (Initial): 允许使用浮点指令
  # MSTATUS.VS = 01 (Initial): 允许使用向量指令
  # --------------------------------------------------------
  li t0, MSTATUS_FS | MSTATUS_VS
  csrs mstatus, t0

  # --------------------------------------------------------
  # 第3步: 验证 XLEN (可选)
  # 确保运行时架构与编译时一致
  # --------------------------------------------------------
  li t0, 1
  slli t0, t0, 31           # t0 = 1 << 31
#if __riscv_xlen == 64
  bgez t0, .arch_mismatch   # 64-bit: 结果应该为负数
#else
  bltz t0, .arch_mismatch   # 32-bit: 结果应该为正数
#endif
  j .arch_ok

.arch_mismatch:
  # 架构不匹配，停止执行
  li a0, 1
  j tohost_exit

.arch_ok:
  # --------------------------------------------------------
  # 第4步: 初始化浮点寄存器 (如果有 FPU)
  # --------------------------------------------------------
#ifdef __riscv_flen
  fssr    x0                # 清除浮点状态寄存器
  fmv.s.x f0, x0            # 清零所有浮点寄存器
  fmv.s.x f1, x0
  # ... f2 到 f30 ...
  fmv.s.x f31, x0
#endif

  # --------------------------------------------------------
  # 第5步: 设置 Trap 向量
  # mtvec 指向异常处理入口
  # --------------------------------------------------------
  la t0, trap_entry
  csrw mtvec, t0

  # --------------------------------------------------------
  # 第6步: 初始化 Global Pointer (gp)
  # gp 用于优化小数据段访问 (GP relaxation)
  # --------------------------------------------------------
.option push
.option norelax             # 禁止链接器优化这条指令
  la gp, __global_pointer$  # 从 linker script 获取地址
.option pop

  # --------------------------------------------------------
  # 第7步: 初始化 Thread Pointer (tp)
  # tp 用于 Thread-Local Storage
  # --------------------------------------------------------
  la tp, _end               # TLS 区域起始地址
  addi tp, tp, 63
  andi tp, tp, -64          # 64 字节对齐

  # --------------------------------------------------------
  # 第8步: 初始化栈指针 (sp)
  # 栈从高地址向低地址增长
  # --------------------------------------------------------
  la sp, _stack_top         # 从 linker script 获取栈顶地址

  # --------------------------------------------------------
  # 第9步: 清零 BSS 段
  # BSS 存放未初始化的全局变量，必须清零
  # --------------------------------------------------------
  la t0, _bss_start
  la t1, _bss_end
.bss_clear:
  bgeu t0, t1, .bss_done
  SREG zero, 0(t0)
  addi t0, t0, REGBYTES
  j .bss_clear
.bss_done:

  # --------------------------------------------------------
  # 第10步: 跳转到 C 代码
  # --------------------------------------------------------
  call main                 # 调用 main()
  
  # main() 返回后退出
  mv a0, a0                 # 返回值已在 a0
  call exit

  # 死循环 (正常不应该到达这里)
.hang:
  j .hang
```

### 2.2 关键 CSR 寄存器

| CSR | 名称 | 说明 |
|-----|------|------|
| `mstatus` | Machine Status | 控制特权级别、中断使能、FPU/Vector 状态 |
| `mtvec` | Machine Trap Vector | 异常处理入口地址 |
| `mepc` | Machine Exception PC | 发生异常时的 PC 值 |
| `mcause` | Machine Cause | 异常/中断原因 |
| `mhartid` | Hart ID | 当前硬件线程 ID |

### 2.3 CSR 操作指令

```asm
# 读取 CSR
csrr rd, csr        # rd = csr

# 写入 CSR  
csrw csr, rs        # csr = rs

# 读取并设置位
csrrs rd, csr, rs   # rd = csr; csr |= rs

# 读取并清除位
csrrc rd, csr, rs   # rd = csr; csr &= ~rs

# 设置位 (不读取)
csrs csr, rs        # csr |= rs

# 清除位 (不读取)
csrc csr, rs        # csr &= ~rs
```

### 2.4 为什么需要 .option norelax

```asm
.option push
.option norelax
  la gp, __global_pointer$
.option pop
```

**原因**: 链接器的 GP relaxation 优化会将全局变量访问转换为基于 `gp` 的偏移访问。但这要求 `gp` 已经被正确设置。如果链接器优化了设置 `gp` 的指令本身，就会形成循环依赖。`.option norelax` 告诉汇编器不要标记这条指令为可优化。

---

## 3. Linker Script 详解

Linker Script（链接脚本）控制程序的内存布局，决定代码和数据放在哪里。

### 3.1 基本语法

```ld
/* baremetal.lds - RISC-V Baremetal Linker Script */

/* 输出格式和入口点 */
OUTPUT_ARCH("riscv")
ENTRY(_start)

/* ============================================================
 * MEMORY 命令: 定义物理内存区域
 * ============================================================ */
MEMORY
{
    /* 名称 (属性) : ORIGIN = 起始地址, LENGTH = 大小 */
    
    /* ROM: 存放代码和只读数据 */
    ROM   (rx)  : ORIGIN = 0x80000000, LENGTH = 2M
    
    /* RAM: 存放数据和 BSS */
    RAM   (rwx) : ORIGIN = 0x80200000, LENGTH = 2M
    
    /* STACK: 栈区域 */
    STACK (rw)  : ORIGIN = 0x80400000, LENGTH = 64K
}
```

**内存属性说明**:
- `r` = 可读 (Readable)
- `w` = 可写 (Writable)
- `x` = 可执行 (Executable)
- `a` = 可分配 (Allocatable)

### 3.2 SECTIONS 命令

```ld
SECTIONS
{
    /* ========================================================
     * .text.init - 启动代码 (必须在最前面)
     * ======================================================== */
    .text.init : {
        *(.text.init)       /* 所有输入文件的 .text.init 段 */
    } > ROM
    
    /* ========================================================
     * .text - 程序代码
     * ======================================================== */
    .text : {
        *(.text .text.*)    /* 所有 .text 和 .text.xxx 段 */
        . = ALIGN(4);       /* 4 字节对齐 */
    } > ROM
    
    /* ========================================================
     * .rodata - 只读数据 (常量、字符串字面量)
     * ======================================================== */
    .rodata : {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)  /* 小只读数据 */
        . = ALIGN(8);
    } > ROM
    
    /* ========================================================
     * .data - 已初始化全局变量
     * 注意: LMA 在 ROM，VMA 在 RAM (需要复制)
     * ======================================================== */
    .data : {
        _data_start = .;
        *(.data .data.*)
        *(.sdata .sdata.*)      /* 小数据段 */
        . = ALIGN(8);
        _data_end = .;
    } > RAM AT > ROM
    
    _data_load = LOADADDR(.data);  /* ROM 中的加载地址 */
    
    /* ========================================================
     * .bss - 未初始化全局变量 (启动时清零)
     * ======================================================== */
    .bss (NOLOAD) : {
        _bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)        /* 小 BSS */
        *(COMMON)
        . = ALIGN(8);
        _bss_end = .;
    } > RAM
    
    /* ========================================================
     * .tohost - HTIF 通信区域 (Spike/QEMU)
     * 必须 64 字节对齐
     * ======================================================== */
    .tohost (NOLOAD) : ALIGN(64) {
        tohost = .;
        . += 8;
        . = ALIGN(64);
        fromhost = .;
        . += 8;
    } > RAM
    
    /* ========================================================
     * 栈
     * ======================================================== */
    .stack (NOLOAD) : {
        . = ALIGN(16);          /* 栈必须 16 字节对齐 (ABI 要求) */
        _stack_bottom = .;
        . += LENGTH(STACK);
        _stack_top = .;
    } > STACK
    
    /* ========================================================
     * 导出符号供 C 代码使用
     * ======================================================== */
    __global_pointer$ = ADDR(.sdata) + 0x800;
    _end = .;
    
    /* ========================================================
     * 丢弃不需要的段
     * ======================================================== */
    /DISCARD/ : {
        *(.comment)
        *(.note.*)
        *(.eh_frame*)
    }
}
```

### 3.3 关键概念

#### 3.3.1 VMA vs LMA

```
VMA (Virtual Memory Address): 程序运行时的地址
LMA (Load Memory Address): 程序加载时的地址

┌─────────────────────────────────────────────────────────────┐
│                    典型 Baremetal 场景                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ROM (LMA)                    RAM (VMA)                     │
│  ┌──────────┐                 ┌──────────┐                  │
│  │ .text    │                 │          │                  │
│  ├──────────┤                 │          │                  │
│  │ .rodata  │                 │          │                  │
│  ├──────────┤    启动时复制    ├──────────┤                  │
│  │ .data    │ ──────────────> │ .data    │                  │
│  │ (初始值) │                 │ (运行时) │                  │
│  └──────────┘                 ├──────────┤                  │
│                               │ .bss     │ ← 启动时清零      │
│                               └──────────┘                  │
└─────────────────────────────────────────────────────────────┘
```

**语法**: `> VMA_REGION AT > LMA_REGION`

```ld
.data : {
    *(.data)
} > RAM AT > ROM    /* VMA 在 RAM，LMA 在 ROM */

_data_load = LOADADDR(.data);  /* 获取 LMA 地址 */
```

#### 3.3.2 对齐的重要性

```ld
. = ALIGN(n);   /* 将当前地址对齐到 n 字节边界 */
```

| 对齐要求 | 原因 |
|----------|------|
| `ALIGN(4)` | RISC-V 指令 4 字节对齐 |
| `ALIGN(8)` | 64-bit 数据自然对齐 |
| `ALIGN(16)` | 栈 ABI 要求 |
| `ALIGN(64)` | HTIF tohost/fromhost 要求，缓存行对齐 |

#### 3.3.3 符号导出

```ld
/* 定义符号，供 C/汇编代码使用 */
_bss_start = .;         /* 当前地址 */
_bss_end = .;
__global_pointer$ = ADDR(.sdata) + 0x800;
```

**在 C 中使用**:
```c
extern char _bss_start[];
extern char _bss_end[];

void clear_bss(void) {
    for (char *p = _bss_start; p < _bss_end; p++)
        *p = 0;
}
```

### 3.4 常见内存布局

#### 3.4.1 Spike 默认布局

```ld
MEMORY {
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128M
}
```

#### 3.4.2 分离 ROM/RAM

```ld
MEMORY {
    ROM   (rx)  : ORIGIN = 0x00000000, LENGTH = 256K
    RAM   (rwx) : ORIGIN = 0x80000000, LENGTH = 64K
    STACK (rw)  : ORIGIN = 0x80010000, LENGTH = 8K
}
```

#### 3.4.3 带 TCM 的嵌入式布局

```ld
MEMORY {
    ITCM  (rx)  : ORIGIN = 0x00000000, LENGTH = 64K   /* 指令 TCM */
    DTCM  (rw)  : ORIGIN = 0x00100000, LENGTH = 64K   /* 数据 TCM */
    FLASH (rx)  : ORIGIN = 0x20000000, LENGTH = 1M    /* 外部 Flash */
    SRAM  (rwx) : ORIGIN = 0x80000000, LENGTH = 256K  /* 外部 SRAM */
}
```

---

## 4. Syscalls 与 HTIF 协议

### 4.1 HTIF 协议概述

**HTIF (Host-Target Interface)** 是 RISC-V 模拟器（Spike、QEMU）与目标程序通信的机制。

```
┌─────────────────┐                ┌─────────────────┐
│   Target        │                │   Host          │
│   (程序)        │                │   (模拟器)       │
│                 │                │                 │
│   tohost ───────┼───────────────>│   读取请求       │
│                 │                │   执行操作       │
│   fromhost <────┼───────────────│   写入响应       │
└─────────────────┘                └─────────────────┘
```

### 4.2 tohost/fromhost 变量

```c
/* 必须放在特定内存区域，64 字节对齐 */
volatile uint64_t tohost   __attribute__((section(".tohost"), aligned(64)));
volatile uint64_t fromhost __attribute__((section(".tohost"), aligned(64)));
```

或者在汇编中定义：
```asm
.section ".tohost", "aw", @progbits
.align 6                    /* 64 字节对齐 */
.globl tohost
tohost:   .dword 0
.align 6
.globl fromhost  
fromhost: .dword 0
```

### 4.3 syscall 实现

```c
#include <stdint.h>

#define SYS_write  64
#define SYS_exit   93

extern volatile uint64_t tohost;
extern volatile uint64_t fromhost;

/* 系统调用实现 */
static uintptr_t syscall(uintptr_t which, uint64_t arg0, 
                         uint64_t arg1, uint64_t arg2)
{
    /* Magic memory: 存放系统调用参数 */
    volatile uint64_t magic_mem[8] __attribute__((aligned(64)));
    
    magic_mem[0] = which;   /* 系统调用号 */
    magic_mem[1] = arg0;    /* 参数 1 */
    magic_mem[2] = arg1;    /* 参数 2 */
    magic_mem[3] = arg2;    /* 参数 3 */
    
    /* 内存屏障: 确保写入完成后再通知 host */
    __sync_synchronize();
    
    /* 通知 host: 将 magic_mem 地址写入 tohost */
    tohost = (uintptr_t)magic_mem;
    
    /* 等待 host 响应 */
    while (fromhost == 0)
        ;
    
    /* 清除响应标志 */
    fromhost = 0;
    
    /* 内存屏障: 确保读取返回值前同步完成 */
    __sync_synchronize();
    
    /* 返回值在 magic_mem[0] */
    return magic_mem[0];
}
```

### 4.4 程序退出

```c
/* 退出程序 */
void __attribute__((noreturn)) tohost_exit(uintptr_t code)
{
    /* 退出码格式: (code << 1) | 1 */
    tohost = (code << 1) | 1;
    
    /* 死循环 (理论上不应该到达) */
    while (1)
        ;
}

void exit(int code)
{
    tohost_exit(code);
}
```

### 4.5 控制台输出

```c
/* 输出字符串到控制台 */
void printstr(const char *s)
{
    syscall(SYS_write, 
            1,              /* fd: stdout */
            (uintptr_t)s,   /* 字符串地址 */
            strlen(s));     /* 长度 */
}

/* 带缓冲的字符输出 */
int putchar(int ch)
{
    static char buf[64] __attribute__((aligned(64)));
    static int buflen = 0;
    
    buf[buflen++] = ch;
    
    /* 换行或缓冲区满时刷新 */
    if (ch == '\n' || buflen == sizeof(buf)) {
        syscall(SYS_write, 1, (uintptr_t)buf, buflen);
        buflen = 0;
    }
    
    return ch;
}
```

### 4.6 内存屏障的作用

```c
__sync_synchronize();
```

**为什么需要内存屏障？**

1. **编译器优化**: 编译器可能重排指令顺序
2. **CPU 乱序执行**: 现代 CPU 可能乱序执行内存操作
3. **多核一致性**: 确保其他核心看到正确的内存状态

**在 HTIF 中的作用**:
- 写入 `magic_mem` 后必须同步，确保 host 读到完整数据
- 读取返回值前必须同步，确保 host 的写入已完成

---

## 5. C 标准库函数实现

Baremetal 环境没有标准库，需要自己实现常用函数。

### 5.1 字符串函数

```c
/* 计算字符串长度 */
size_t strlen(const char *s)
{
    const char *p = s;
    while (*p)
        p++;
    return p - s;
}

/* 带最大长度的字符串长度 */
size_t strnlen(const char *s, size_t maxlen)
{
    const char *p = s;
    while (maxlen-- && *p)
        p++;
    return p - s;
}

/* 字符串比较 */
int strcmp(const char *s1, const char *s2)
{
    while (*s1 && *s1 == *s2) {
        s1++;
        s2++;
    }
    return *(unsigned char *)s1 - *(unsigned char *)s2;
}

/* 字符串复制 */
char *strcpy(char *dest, const char *src)
{
    char *d = dest;
    while ((*d++ = *src++))
        ;
    return dest;
}
```

### 5.2 内存函数

```c
/* 内存复制 (优化版) */
void *memcpy(void *dest, const void *src, size_t n)
{
    unsigned char *d = dest;
    const unsigned char *s = src;
    
    /* 如果对齐，使用字长复制 */
    if (((uintptr_t)d | (uintptr_t)s | n) % sizeof(long) == 0) {
        long *ld = (long *)d;
        const long *ls = (const long *)s;
        n /= sizeof(long);
        while (n--)
            *ld++ = *ls++;
    } else {
        /* 否则逐字节复制 */
        while (n--)
            *d++ = *s++;
    }
    
    return dest;
}

/* 内存设置 */
void *memset(void *dest, int c, size_t n)
{
    unsigned char *d = dest;
    unsigned char byte = c;
    
    /* 如果对齐且设置为 0，使用字长操作 */
    if (((uintptr_t)d | n) % sizeof(long) == 0 && c == 0) {
        long *ld = (long *)d;
        n /= sizeof(long);
        while (n--)
            *ld++ = 0;
    } else {
        while (n--)
            *d++ = byte;
    }
    
    return dest;
}

/* 内存比较 */
int memcmp(const void *s1, const void *s2, size_t n)
{
    const unsigned char *p1 = s1;
    const unsigned char *p2 = s2;
    
    while (n--) {
        if (*p1 != *p2)
            return *p1 - *p2;
        p1++;
        p2++;
    }
    return 0;
}
```

### 5.3 printf 实现

```c
#include <stdarg.h>

/* 输出单个数字 */
static void print_num(unsigned long long num, int base, 
                      int width, char pad)
{
    char buf[32];
    int i = 0;
    
    /* 转换数字到字符串 (逆序) */
    do {
        int digit = num % base;
        buf[i++] = digit < 10 ? '0' + digit : 'a' + digit - 10;
        num /= base;
    } while (num > 0);
    
    /* 填充前导字符 */
    while (i < width)
        buf[i++] = pad;
    
    /* 逆序输出 */
    while (i > 0)
        putchar(buf[--i]);
}

/* 简化版 printf */
int printf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    
    while (*fmt) {
        if (*fmt != '%') {
            putchar(*fmt++);
            continue;
        }
        
        fmt++;  /* 跳过 '%' */
        
        /* 解析宽度 */
        char pad = ' ';
        int width = 0;
        
        if (*fmt == '0') {
            pad = '0';
            fmt++;
        }
        
        while (*fmt >= '0' && *fmt <= '9') {
            width = width * 10 + (*fmt - '0');
            fmt++;
        }
        
        /* 解析长度修饰符 */
        int is_long = 0;
        if (*fmt == 'l') {
            is_long = 1;
            fmt++;
            if (*fmt == 'l') {
                is_long = 2;
                fmt++;
            }
        }
        
        /* 解析格式说明符 */
        switch (*fmt) {
        case 'd': case 'i': {
            long long num;
            if (is_long >= 2)
                num = va_arg(ap, long long);
            else if (is_long)
                num = va_arg(ap, long);
            else
                num = va_arg(ap, int);
            
            if (num < 0) {
                putchar('-');
                num = -num;
            }
            print_num(num, 10, width, pad);
            break;
        }
        
        case 'u': {
            unsigned long long num;
            if (is_long >= 2)
                num = va_arg(ap, unsigned long long);
            else if (is_long)
                num = va_arg(ap, unsigned long);
            else
                num = va_arg(ap, unsigned int);
            print_num(num, 10, width, pad);
            break;
        }
        
        case 'x': case 'X': {
            unsigned long long num;
            if (is_long >= 2)
                num = va_arg(ap, unsigned long long);
            else if (is_long)
                num = va_arg(ap, unsigned long);
            else
                num = va_arg(ap, unsigned int);
            print_num(num, 16, width, pad);
            break;
        }
        
        case 'p':
            putchar('0');
            putchar('x');
            print_num((unsigned long)va_arg(ap, void *), 16, 
                      sizeof(void *) * 2, '0');
            break;
        
        case 's': {
            const char *s = va_arg(ap, const char *);
            if (!s) s = "(null)";
            while (*s)
                putchar(*s++);
            break;
        }
        
        case 'c':
            putchar(va_arg(ap, int));
            break;
        
        case '%':
            putchar('%');
            break;
        
        default:
            putchar('%');
            putchar(*fmt);
            break;
        }
        
        fmt++;
    }
    
    va_end(ap);
    return 0;
}

/* puts */
int puts(const char *s)
{
    while (*s)
        putchar(*s++);
    putchar('\n');
    return 0;
}
```

### 5.4 数值转换

```c
/* 字符串转整数 */
int atoi(const char *s)
{
    int result = 0;
    int sign = 1;
    
    /* 跳过空白 */
    while (*s == ' ' || *s == '\t')
        s++;
    
    /* 处理符号 */
    if (*s == '-') {
        sign = -1;
        s++;
    } else if (*s == '+') {
        s++;
    }
    
    /* 转换数字 */
    while (*s >= '0' && *s <= '9') {
        result = result * 10 + (*s - '0');
        s++;
    }
    
    return sign * result;
}

long atol(const char *s)
{
    long result = 0;
    int sign = 1;
    
    while (*s == ' ' || *s == '\t')
        s++;
    
    if (*s == '-') {
        sign = -1;
        s++;
    } else if (*s == '+') {
        s++;
    }
    
    while (*s >= '0' && *s <= '9') {
        result = result * 10 + (*s - '0');
        s++;
    }
    
    return sign * result;
}
```

---

## 6. 异常与中断处理

### 6.1 RISC-V Trap 概述

RISC-V 将所有的异常和中断统称为 **Trap**。

```
Trap
├── Exception (同步): 由指令执行触发
│   ├── 非法指令
│   ├── 地址不对齐
│   ├── 访问错误
│   └── 环境调用 (ecall)
│
└── Interrupt (异步): 由外部事件触发
    ├── 软件中断
    ├── 定时器中断
    └── 外部中断
```

### 6.2 关键 CSR 寄存器

| CSR | 说明 |
|-----|------|
| `mtvec` | Trap 向量基地址 |
| `mcause` | Trap 原因 (最高位为 1 表示中断) |
| `mepc` | 发生 Trap 时的 PC |
| `mtval` | 附加信息 (错误地址、非法指令等) |
| `mstatus` | 状态寄存器 (MIE 位控制中断使能) |
| `mie` | 中断使能寄存器 |
| `mip` | 中断挂起寄存器 |

### 6.3 mcause 值

#### Exception (mcause[XLEN-1] = 0)

| Code | 名称 | 说明 |
|------|------|------|
| 0 | Instruction address misaligned | 指令地址不对齐 |
| 1 | Instruction access fault | 指令访问错误 |
| 2 | Illegal instruction | 非法指令 |
| 3 | Breakpoint | 断点 |
| 4 | Load address misaligned | 加载地址不对齐 |
| 5 | Load access fault | 加载访问错误 |
| 6 | Store address misaligned | 存储地址不对齐 |
| 7 | Store access fault | 存储访问错误 |
| 8 | Environment call from U-mode | 用户态系统调用 |
| 11 | Environment call from M-mode | 机器态系统调用 |

#### Interrupt (mcause[XLEN-1] = 1)

| Code | 名称 |
|------|------|
| 3 | Machine software interrupt |
| 7 | Machine timer interrupt |
| 11 | Machine external interrupt |

### 6.4 Trap 处理汇编

```asm
# ============================================================
# trap_entry - 异常/中断入口
# ============================================================
  .align 2                  # 4 字节对齐 (mtvec 要求)
  .globl trap_entry
trap_entry:
  # --------------------------------------------------------
  # 保存所有寄存器到栈
  # 分配栈帧: 32 个通用寄存器 * 8 字节 = 256 字节
  # 加上对齐 = 272 字节
  # --------------------------------------------------------
  addi sp, sp, -272
  
  # 保存通用寄存器 (x1-x31, x0 不需要保存)
  sd x1,   1*8(sp)
  sd x2,   2*8(sp)
  sd x3,   3*8(sp)
  sd x4,   4*8(sp)
  sd x5,   5*8(sp)
  sd x6,   6*8(sp)
  sd x7,   7*8(sp)
  sd x8,   8*8(sp)
  sd x9,   9*8(sp)
  sd x10, 10*8(sp)
  sd x11, 11*8(sp)
  sd x12, 12*8(sp)
  sd x13, 13*8(sp)
  sd x14, 14*8(sp)
  sd x15, 15*8(sp)
  sd x16, 16*8(sp)
  sd x17, 17*8(sp)
  sd x18, 18*8(sp)
  sd x19, 19*8(sp)
  sd x20, 20*8(sp)
  sd x21, 21*8(sp)
  sd x22, 22*8(sp)
  sd x23, 23*8(sp)
  sd x24, 24*8(sp)
  sd x25, 25*8(sp)
  sd x26, 26*8(sp)
  sd x27, 27*8(sp)
  sd x28, 28*8(sp)
  sd x29, 29*8(sp)
  sd x30, 30*8(sp)
  sd x31, 31*8(sp)
  
  # --------------------------------------------------------
  # 调用 C 处理函数
  # 参数: a0 = mcause, a1 = mepc, a2 = sp (寄存器数组)
  # --------------------------------------------------------
  csrr a0, mcause
  csrr a1, mepc
  mv   a2, sp
  
  call handle_trap          # 返回值是新的 PC
  
  csrw mepc, a0             # 更新返回地址
  
  # --------------------------------------------------------
  # 恢复所有寄存器
  # --------------------------------------------------------
  ld x1,   1*8(sp)
  ld x2,   2*8(sp)
  ld x3,   3*8(sp)
  ld x4,   4*8(sp)
  ld x5,   5*8(sp)
  ld x6,   6*8(sp)
  ld x7,   7*8(sp)
  ld x8,   8*8(sp)
  ld x9,   9*8(sp)
  ld x10, 10*8(sp)
  ld x11, 11*8(sp)
  ld x12, 12*8(sp)
  ld x13, 13*8(sp)
  ld x14, 14*8(sp)
  ld x15, 15*8(sp)
  ld x16, 16*8(sp)
  ld x17, 17*8(sp)
  ld x18, 18*8(sp)
  ld x19, 19*8(sp)
  ld x20, 20*8(sp)
  ld x21, 21*8(sp)
  ld x22, 22*8(sp)
  ld x23, 23*8(sp)
  ld x24, 24*8(sp)
  ld x25, 25*8(sp)
  ld x26, 26*8(sp)
  ld x27, 27*8(sp)
  ld x28, 28*8(sp)
  ld x29, 29*8(sp)
  ld x30, 30*8(sp)
  ld x31, 31*8(sp)
  
  addi sp, sp, 272
  
  # --------------------------------------------------------
  # 返回
  # --------------------------------------------------------
  mret
```

### 6.5 Trap 处理 C 函数

```c
#include <stdint.h>

/* 获取指令长度 (2 或 4 字节) */
static inline size_t insn_len(uintptr_t pc)
{
    /* RISC-V: 低 2 位为 11 表示 32-bit 指令 */
    return (*(uint16_t *)pc & 0x3) == 0x3 ? 4 : 2;
}

/* Trap 处理函数 */
uintptr_t handle_trap(uintptr_t mcause, uintptr_t mepc, 
                      uintptr_t *regs)
{
    /* 检查是否是中断 (最高位为 1) */
    if ((long)mcause < 0) {
        /* 中断处理 */
        uintptr_t cause = mcause & 0x7FFFFFFFFFFFFFFF;
        
        switch (cause) {
        case 7:     /* Machine timer interrupt */
            /* 处理定时器中断 */
            /* ... */
            break;
            
        case 11:    /* Machine external interrupt */
            /* 处理外部中断 */
            /* ... */
            break;
            
        default:
            printf("Unknown interrupt: %ld\n", cause);
            break;
        }
        
        return mepc;    /* 中断返回原地址 */
    }
    
    /* 异常处理 */
    uintptr_t mtval;
    asm volatile ("csrr %0, mtval" : "=r"(mtval));
    
    switch (mcause) {
    case 0:     /* Instruction address misaligned */
        printf("Instruction address misaligned at 0x%lx\n", mepc);
        break;
        
    case 1:     /* Instruction access fault */
        printf("Instruction access fault at 0x%lx\n", mepc);
        break;
        
    case 2:     /* Illegal instruction */
        printf("Illegal instruction at 0x%lx: 0x%lx\n", 
               mepc, mtval);
        break;
        
    case 4:     /* Load address misaligned */
        printf("Load address misaligned at 0x%lx, addr=0x%lx\n", 
               mepc, mtval);
        break;
        
    case 5:     /* Load access fault */
        printf("Load access fault at 0x%lx, addr=0x%lx\n", 
               mepc, mtval);
        break;
        
    case 6:     /* Store address misaligned */
        printf("Store address misaligned at 0x%lx, addr=0x%lx\n", 
               mepc, mtval);
        break;
        
    case 7:     /* Store access fault */
        printf("Store access fault at 0x%lx, addr=0x%lx\n", 
               mepc, mtval);
        break;
        
    case 8:     /* Environment call from U-mode */
    case 11:    /* Environment call from M-mode */
        /* 处理系统调用 (ecall) */
        /* a7 = 系统调用号, a0-a5 = 参数, a0 = 返回值 */
        /* regs[17] = a7, regs[10] = a0 */
        /* ... */
        return mepc + 4;    /* ecall 是 4 字节指令 */
        
    default:
        printf("Unknown exception %ld at 0x%lx\n", mcause, mepc);
        break;
    }
    
    /* 默认: 终止程序 */
    exit(1);
    return mepc;    /* 不会到达 */
}
```

### 6.6 启用中断

```c
/* CSR 操作宏 */
#define read_csr(reg) ({ \
    unsigned long __tmp; \
    asm volatile ("csrr %0, " #reg : "=r"(__tmp)); \
    __tmp; \
})

#define write_csr(reg, val) ({ \
    asm volatile ("csrw " #reg ", %0" :: "rK"(val)); \
})

#define set_csr(reg, bit) ({ \
    asm volatile ("csrs " #reg ", %0" :: "rK"(bit)); \
})

#define clear_csr(reg, bit) ({ \
    asm volatile ("csrc " #reg ", %0" :: "rK"(bit)); \
})

/* mstatus 位定义 */
#define MSTATUS_MIE     (1UL << 3)      /* Machine Interrupt Enable */
#define MSTATUS_MPIE    (1UL << 7)      /* Machine Previous IE */

/* mie 位定义 */
#define MIE_MTIE        (1UL << 7)      /* Machine Timer IE */
#define MIE_MEIE        (1UL << 11)     /* Machine External IE */

/* 启用全局中断 */
void enable_interrupts(void)
{
    set_csr(mstatus, MSTATUS_MIE);
}

/* 禁用全局中断 */
void disable_interrupts(void)
{
    clear_csr(mstatus, MSTATUS_MIE);
}

/* 启用定时器中断 */
void enable_timer_interrupt(void)
{
    set_csr(mie, MIE_MTIE);
}
```

---

## 7. 编译与链接配置

### 7.1 编译选项详解

```makefile
# 目标架构
ARCH = -march=rv64gc        # RV64 + G 扩展 (IMAFD) + C 扩展
# 或者
ARCH = -march=rv64gcv       # 加上 Vector 扩展

# ABI
ABI = -mabi=lp64d           # LP64 + double-float ABI

# 优化
OPT = -O2                   # 优化级别

# Baremetal 必需选项
BAREMETAL_FLAGS = \
    -ffreestanding          # 独立环境，不假设标准库存在 \
    -nostartfiles           # 不链接默认启动文件 (crt0.o, crti.o) \
    -nostdlib               # 不链接标准库 \
    -fno-common             # 禁止 common 块 (BSS 合并) \
    -mcmodel=medany         # 代码模型: 支持任意地址

# 代码模型说明:
# medlow:  代码和数据在低 2GB (默认)
# medany:  代码和数据可在任意位置，但相对偏移 < 2GB

# 可选优化选项
EXTRA_FLAGS = \
    -ffunction-sections     # 每个函数放入单独的 section \
    -fdata-sections         # 每个数据放入单独的 section
```

### 7.2 链接选项详解

```makefile
# 链接选项
LDFLAGS = \
    -T baremetal.lds        # 使用自定义链接脚本 \
    -nostdlib               # 不链接标准库 \
    -static                 # 静态链接 \
    -Wl,--gc-sections       # 删除未使用的 sections \
    -lgcc                   # 链接 libgcc (软浮点、除法等)

# -lgcc 提供的函数:
# - 整数除法/取模: __divdi3, __moddi3, __udivdi3, __umoddi3
# - 软浮点: __addsf3, __mulsf3, __divsf3, etc.
# - 内存操作: __clear_cache
```

### 7.3 完整 Makefile

```makefile
# ============================================================
# Makefile for RISC-V Baremetal Project
# ============================================================

# 工具链
CROSS_COMPILE ?= riscv64-unknown-elf-
CC      = $(CROSS_COMPILE)gcc
AS      = $(CROSS_COMPILE)gcc
LD      = $(CROSS_COMPILE)gcc
OBJCOPY = $(CROSS_COMPILE)objcopy
OBJDUMP = $(CROSS_COMPILE)objdump
SIZE    = $(CROSS_COMPILE)size

# 目标
TARGET = hello

# 目录
SRCDIR = src
OBJDIR = build/obj
BINDIR = build/bin

# 源文件
SRCS_C   = $(wildcard $(SRCDIR)/*.c)
SRCS_S   = $(wildcard $(SRCDIR)/*.S)
OBJS     = $(SRCS_C:$(SRCDIR)/%.c=$(OBJDIR)/%.o) \
           $(SRCS_S:$(SRCDIR)/%.S=$(OBJDIR)/%.o)

# 编译选项
ARCH    = -march=rv64gc -mabi=lp64d
CFLAGS  = $(ARCH) -O2 -g \
          -ffreestanding -nostartfiles -nostdlib \
          -fno-common -mcmodel=medany \
          -ffunction-sections -fdata-sections \
          -Wall -Wextra

ASFLAGS = $(ARCH) -g

LDFLAGS = -T linker/baremetal.lds \
          -nostdlib -static \
          -Wl,--gc-sections \
          -lgcc

# ============================================================
# 构建规则
# ============================================================

.PHONY: all clean run

all: $(BINDIR)/$(TARGET).elf $(BINDIR)/$(TARGET).bin

# 链接
$(BINDIR)/$(TARGET).elf: $(OBJS) linker/baremetal.lds
	@mkdir -p $(BINDIR)
	$(LD) $(CFLAGS) $(OBJS) -o $@ $(LDFLAGS)
	$(SIZE) $@
	$(OBJDUMP) -d $@ > $(BINDIR)/$(TARGET).dis

# 生成二进制 (用于烧录)
$(BINDIR)/$(TARGET).bin: $(BINDIR)/$(TARGET).elf
	$(OBJCOPY) -O binary $< $@

# 编译 C
$(OBJDIR)/%.o: $(SRCDIR)/%.c
	@mkdir -p $(OBJDIR)
	$(CC) $(CFLAGS) -c $< -o $@

# 编译汇编
$(OBJDIR)/%.o: $(SRCDIR)/%.S
	@mkdir -p $(OBJDIR)
	$(AS) $(ASFLAGS) -c $< -o $@

# 清理
clean:
	rm -rf build

# ============================================================
# 运行目标
# ============================================================

SPIKE ?= spike
QEMU  ?= qemu-riscv64

# Spike 运行
run-spike: $(BINDIR)/$(TARGET).elf
	$(SPIKE) --isa=rv64gc $<

# QEMU 运行
run-qemu: $(BINDIR)/$(TARGET).elf
	$(QEMU) $<

# Spike 调试
debug-spike: $(BINDIR)/$(TARGET).elf
	$(SPIKE) --isa=rv64gc -d $<

# QEMU GDB 调试
debug-qemu: $(BINDIR)/$(TARGET).elf
	$(QEMU) -g 1234 $< &
	@echo "Use: riscv64-unknown-elf-gdb -ex 'target remote :1234' $<"
```

### 7.4 构建流程

```
源文件                    编译                链接              输出
┌─────────┐            ┌─────────┐        ┌─────────┐      ┌─────────┐
│ crt.S   │ ─── as ──> │ crt.o   │        │         │      │         │
├─────────┤            ├─────────┤        │         │      │ .elf    │
│ main.c  │ ─── gcc ─> │ main.o  │ ─ ld ─>│ linker  │ ──>  │ (调试)  │
├─────────┤            ├─────────┤        │ script  │      ├─────────┤
│syscalls.c│─── gcc ─> │syscalls.o│       │         │      │ .bin    │
└─────────┘            └─────────┘        └─────────┘      │ (烧录)  │
                                                           └─────────┘
```

---

## 8. 调试技巧

### 8.1 Spike 调试

```bash
# 基本运行
spike --isa=rv64gc hello.elf

# 交互式调试
spike --isa=rv64gc -d hello.elf

# 调试命令:
# run              - 运行到断点或结束
# reg 0            - 显示寄存器
# reg 0 a0         - 显示特定寄存器
# mem 0 0x80000000 - 显示内存
# until pc 0x80000100 - 运行到指定地址
# while 1          - 单步执行
# quit             - 退出

# 指令追踪
spike --isa=rv64gc --log-commits hello.elf 2> trace.log
```

### 8.2 QEMU 调试

```bash
# 基本运行
qemu-riscv64 hello.elf

# 启动 GDB 服务器
qemu-riscv64 -g 1234 hello.elf

# 另一个终端连接 GDB
riscv64-unknown-elf-gdb hello.elf
(gdb) target remote :1234
(gdb) break main
(gdb) continue
(gdb) info registers
(gdb) x/10i $pc

# 指令日志
qemu-riscv64 -d in_asm hello.elf 2> asm.log
qemu-riscv64 -d cpu hello.elf 2> cpu.log
```

### 8.3 常见问题排查

#### 问题 1: 程序启动后立即卡死

**可能原因**:
1. 入口地址错误
2. 栈未正确初始化
3. 异常处理未设置

**排查方法**:
```bash
# 检查入口地址
riscv64-unknown-elf-objdump -f hello.elf | grep "start address"

# 检查 _start 是否在正确位置
riscv64-unknown-elf-objdump -d hello.elf | head -50

# 使用 Spike 单步调试
spike --isa=rv64gc -d hello.elf
: reg 0 pc
: while 1
```

#### 问题 2: printf 无输出

**可能原因**:
1. tohost/fromhost 未正确对齐
2. HTIF 区域地址错误
3. 缓冲区未刷新

**排查方法**:
```bash
# 检查 tohost 地址和对齐
riscv64-unknown-elf-objdump -t hello.elf | grep tohost

# 确保地址是 64 字节对齐
# 地址应该是 0x...00 或 0x...40 或 0x...80 或 0x...C0
```

#### 问题 3: 非法指令异常

**可能原因**:
1. 使用了未启用的扩展 (FPU/Vector)
2. 编译选项与硬件不匹配
3. 跳转到了非代码区域

**排查方法**:
```bash
# 检查编译选项
riscv64-unknown-elf-objdump -d hello.elf | grep -E "flw|fsw|fadd"
# 如果有浮点指令，确保启用了 FPU

# 检查异常地址
# 在 handle_trap 中打印 mepc 和 mtval
```

#### 问题 4: 链接错误 "relocation truncated"

**可能原因**:
代码/数据距离超过代码模型限制

**解决方法**:
```makefile
# 使用 medany 代码模型
CFLAGS += -mcmodel=medany
```

### 8.4 有用的 objdump 命令

```bash
# 反汇编
riscv64-unknown-elf-objdump -d hello.elf > hello.dis

# 显示所有段
riscv64-unknown-elf-objdump -h hello.elf

# 显示符号表
riscv64-unknown-elf-objdump -t hello.elf

# 显示段内容
riscv64-unknown-elf-objdump -s -j .rodata hello.elf

# 文件大小分析
riscv64-unknown-elf-size hello.elf
```

---

## 9. 完整示例项目

### 9.1 项目结构

```
minimal_baremetal/
├── src/
│   ├── crt.S           # 启动代码
│   ├── syscalls.c      # 系统调用和库函数
│   └── main.c          # 主程序
├── linker/
│   └── baremetal.lds   # 链接脚本
├── Makefile            # 构建配置
└── README.md           # 说明文档
```

### 9.2 crt.S

```asm
# ============================================================
# crt.S - Minimal C Runtime Startup
# ============================================================

#define MSTATUS_FS    0x00006000
#define MSTATUS_MPP   0x00001800

#if __riscv_xlen == 64
# define LREG ld
# define SREG sd
# define REGBYTES 8
#else
# define LREG lw
# define SREG sw
# define REGBYTES 4
#endif

  .section ".text.init", "ax"
  .globl _start
  .type _start, @function

_start:
  # 清零寄存器
  li  x1, 0
  li  x2, 0
  li  x3, 0
  li  x4, 0
  li  x5, 0
  li  x6, 0
  li  x7, 0
  li  x8, 0
  li  x9, 0
  li  x10,0
  li  x11,0
  li  x12,0
  li  x13,0
  li  x14,0
  li  x15,0
  li  x16,0
  li  x17,0
  li  x18,0
  li  x19,0
  li  x20,0
  li  x21,0
  li  x22,0
  li  x23,0
  li  x24,0
  li  x25,0
  li  x26,0
  li  x27,0
  li  x28,0
  li  x29,0
  li  x30,0
  li  x31,0

  # 启用 FPU
  li t0, MSTATUS_FS
  csrs mstatus, t0

#ifdef __riscv_flen
  # 初始化 FPU 寄存器
  fscsr x0
  fmv.s.x f0, x0
  fmv.s.x f1, x0
  fmv.s.x f2, x0
  fmv.s.x f3, x0
  fmv.s.x f4, x0
  fmv.s.x f5, x0
  fmv.s.x f6, x0
  fmv.s.x f7, x0
  fmv.s.x f8, x0
  fmv.s.x f9, x0
  fmv.s.x f10,x0
  fmv.s.x f11,x0
  fmv.s.x f12,x0
  fmv.s.x f13,x0
  fmv.s.x f14,x0
  fmv.s.x f15,x0
  fmv.s.x f16,x0
  fmv.s.x f17,x0
  fmv.s.x f18,x0
  fmv.s.x f19,x0
  fmv.s.x f20,x0
  fmv.s.x f21,x0
  fmv.s.x f22,x0
  fmv.s.x f23,x0
  fmv.s.x f24,x0
  fmv.s.x f25,x0
  fmv.s.x f26,x0
  fmv.s.x f27,x0
  fmv.s.x f28,x0
  fmv.s.x f29,x0
  fmv.s.x f30,x0
  fmv.s.x f31,x0
#endif

  # 设置 trap 向量
  la t0, trap_entry
  csrw mtvec, t0

  # 初始化 global pointer
.option push
.option norelax
  la gp, __global_pointer$
.option pop

  # 初始化栈指针
  la sp, _stack_top

  # 清零 BSS
  la t0, _bss_start
  la t1, _bss_end
1:
  bgeu t0, t1, 2f
  SREG zero, 0(t0)
  addi t0, t0, REGBYTES
  j 1b
2:

  # 调用 main
  li a0, 0              # argc = 0
  li a1, 0              # argv = NULL
  call main

  # 退出
  mv a0, a0
  call exit

  # 死循环
3:
  j 3b

# ============================================================
# trap_entry - 异常处理入口
# ============================================================
  .align 2
  .globl trap_entry
trap_entry:
  addi sp, sp, -272

  SREG x1,  1*REGBYTES(sp)
  SREG x2,  2*REGBYTES(sp)
  SREG x3,  3*REGBYTES(sp)
  SREG x4,  4*REGBYTES(sp)
  SREG x5,  5*REGBYTES(sp)
  SREG x6,  6*REGBYTES(sp)
  SREG x7,  7*REGBYTES(sp)
  SREG x8,  8*REGBYTES(sp)
  SREG x9,  9*REGBYTES(sp)
  SREG x10, 10*REGBYTES(sp)
  SREG x11, 11*REGBYTES(sp)
  SREG x12, 12*REGBYTES(sp)
  SREG x13, 13*REGBYTES(sp)
  SREG x14, 14*REGBYTES(sp)
  SREG x15, 15*REGBYTES(sp)
  SREG x16, 16*REGBYTES(sp)
  SREG x17, 17*REGBYTES(sp)
  SREG x18, 18*REGBYTES(sp)
  SREG x19, 19*REGBYTES(sp)
  SREG x20, 20*REGBYTES(sp)
  SREG x21, 21*REGBYTES(sp)
  SREG x22, 22*REGBYTES(sp)
  SREG x23, 23*REGBYTES(sp)
  SREG x24, 24*REGBYTES(sp)
  SREG x25, 25*REGBYTES(sp)
  SREG x26, 26*REGBYTES(sp)
  SREG x27, 27*REGBYTES(sp)
  SREG x28, 28*REGBYTES(sp)
  SREG x29, 29*REGBYTES(sp)
  SREG x30, 30*REGBYTES(sp)
  SREG x31, 31*REGBYTES(sp)

  csrr a0, mcause
  csrr a1, mepc
  mv a2, sp
  call handle_trap
  csrw mepc, a0

  # 保持 M-mode
  li t0, MSTATUS_MPP
  csrs mstatus, t0

  LREG x1,  1*REGBYTES(sp)
  LREG x2,  2*REGBYTES(sp)
  LREG x3,  3*REGBYTES(sp)
  LREG x4,  4*REGBYTES(sp)
  LREG x5,  5*REGBYTES(sp)
  LREG x6,  6*REGBYTES(sp)
  LREG x7,  7*REGBYTES(sp)
  LREG x8,  8*REGBYTES(sp)
  LREG x9,  9*REGBYTES(sp)
  LREG x10, 10*REGBYTES(sp)
  LREG x11, 11*REGBYTES(sp)
  LREG x12, 12*REGBYTES(sp)
  LREG x13, 13*REGBYTES(sp)
  LREG x14, 14*REGBYTES(sp)
  LREG x15, 15*REGBYTES(sp)
  LREG x16, 16*REGBYTES(sp)
  LREG x17, 17*REGBYTES(sp)
  LREG x18, 18*REGBYTES(sp)
  LREG x19, 19*REGBYTES(sp)
  LREG x20, 20*REGBYTES(sp)
  LREG x21, 21*REGBYTES(sp)
  LREG x22, 22*REGBYTES(sp)
  LREG x23, 23*REGBYTES(sp)
  LREG x24, 24*REGBYTES(sp)
  LREG x25, 25*REGBYTES(sp)
  LREG x26, 26*REGBYTES(sp)
  LREG x27, 27*REGBYTES(sp)
  LREG x28, 28*REGBYTES(sp)
  LREG x29, 29*REGBYTES(sp)
  LREG x30, 30*REGBYTES(sp)
  LREG x31, 31*REGBYTES(sp)

  addi sp, sp, 272
  mret

# ============================================================
# HTIF 通信区域
# ============================================================
  .section ".tohost", "aw", @progbits
  .align 6
  .globl tohost
tohost:   .dword 0
  .align 6
  .globl fromhost
fromhost: .dword 0
```

### 9.3 syscalls.c

```c
/* ============================================================
 * syscalls.c - System Calls and Library Functions
 * ============================================================ */

#include <stdint.h>
#include <stdarg.h>
#include <stddef.h>

/* ============================================================
 * HTIF 系统调用
 * ============================================================ */

#define SYS_write 64

extern volatile uint64_t tohost;
extern volatile uint64_t fromhost;

static uintptr_t syscall(uintptr_t which, uint64_t arg0, 
                         uint64_t arg1, uint64_t arg2)
{
    volatile uint64_t magic_mem[8] __attribute__((aligned(64)));
    magic_mem[0] = which;
    magic_mem[1] = arg0;
    magic_mem[2] = arg1;
    magic_mem[3] = arg2;
    __sync_synchronize();
    
    tohost = (uintptr_t)magic_mem;
    while (fromhost == 0)
        ;
    fromhost = 0;
    __sync_synchronize();
    
    return magic_mem[0];
}

void __attribute__((noreturn)) exit(int code)
{
    tohost = (code << 1) | 1;
    while (1)
        ;
}

uintptr_t __attribute__((weak)) handle_trap(uintptr_t cause, 
                                            uintptr_t epc, 
                                            uintptr_t *regs)
{
    (void)cause;
    (void)regs;
    exit(1);
    return epc;
}

/* ============================================================
 * 字符串函数
 * ============================================================ */

size_t strlen(const char *s)
{
    const char *p = s;
    while (*p) p++;
    return p - s;
}

void *memcpy(void *dest, const void *src, size_t n)
{
    char *d = dest;
    const char *s = src;
    while (n--) *d++ = *s++;
    return dest;
}

void *memset(void *dest, int c, size_t n)
{
    unsigned char *d = dest;
    while (n--) *d++ = c;
    return dest;
}

/* ============================================================
 * I/O 函数
 * ============================================================ */

int putchar(int ch)
{
    static char buf[64] __attribute__((aligned(64)));
    static int buflen = 0;
    
    buf[buflen++] = ch;
    
    if (ch == '\n' || buflen == sizeof(buf)) {
        syscall(SYS_write, 1, (uintptr_t)buf, buflen);
        buflen = 0;
    }
    
    return ch;
}

static void print_str(const char *s)
{
    while (*s) putchar(*s++);
}

static void print_num(unsigned long long num, int base, 
                      int width, char pad)
{
    char buf[32];
    int i = 0;
    
    do {
        int d = num % base;
        buf[i++] = d < 10 ? '0' + d : 'a' + d - 10;
        num /= base;
    } while (num);
    
    while (i < width) buf[i++] = pad;
    while (i > 0) putchar(buf[--i]);
}

int printf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    
    while (*fmt) {
        if (*fmt != '%') {
            putchar(*fmt++);
            continue;
        }
        fmt++;
        
        char pad = ' ';
        int width = 0;
        
        if (*fmt == '0') { pad = '0'; fmt++; }
        while (*fmt >= '0' && *fmt <= '9')
            width = width * 10 + (*fmt++ - '0');
        
        int is_long = 0;
        while (*fmt == 'l') { is_long++; fmt++; }
        
        switch (*fmt++) {
        case 'd': case 'i': {
            long long n = is_long >= 2 ? va_arg(ap, long long) :
                          is_long ? va_arg(ap, long) : 
                          va_arg(ap, int);
            if (n < 0) { putchar('-'); n = -n; }
            print_num(n, 10, width, pad);
            break;
        }
        case 'u':
            print_num(is_long >= 2 ? va_arg(ap, unsigned long long) :
                      is_long ? va_arg(ap, unsigned long) :
                      va_arg(ap, unsigned), 10, width, pad);
            break;
        case 'x': case 'X':
            print_num(is_long >= 2 ? va_arg(ap, unsigned long long) :
                      is_long ? va_arg(ap, unsigned long) :
                      va_arg(ap, unsigned), 16, width, pad);
            break;
        case 'p':
            print_str("0x");
            print_num((unsigned long)va_arg(ap, void*), 16, 
                      sizeof(void*)*2, '0');
            break;
        case 's': {
            const char *s = va_arg(ap, const char*);
            print_str(s ? s : "(null)");
            break;
        }
        case 'c':
            putchar(va_arg(ap, int));
            break;
        case '%':
            putchar('%');
            break;
        }
    }
    
    va_end(ap);
    return 0;
}

int puts(const char *s)
{
    print_str(s);
    putchar('\n');
    return 0;
}
```

### 9.4 main.c

```c
/* ============================================================
 * main.c - Hello World
 * ============================================================ */

extern int printf(const char *fmt, ...);

int main(int argc, char **argv)
{
    (void)argc;
    (void)argv;
    
    printf("Hello, Baremetal World!\n");
    printf("This is running on RISC-V.\n");
    
    /* 测试各种 printf 格式 */
    printf("Integer: %d\n", 42);
    printf("Hex: 0x%08x\n", 0xDEADBEEF);
    printf("Pointer: %p\n", (void*)main);
    printf("String: %s\n", "test");
    
    return 0;
}
```

### 9.5 baremetal.lds

```ld
/* ============================================================
 * baremetal.lds - Minimal Linker Script
 * ============================================================ */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 4M
}

SECTIONS
{
    . = ORIGIN(RAM);
    
    .text : {
        *(.text.init)
        *(.text .text.*)
    } > RAM
    
    .rodata : {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    } > RAM
    
    . = ALIGN(8);
    
    .data : {
        *(.data .data.*)
        *(.sdata .sdata.*)
    } > RAM
    
    . = ALIGN(8);
    __global_pointer$ = . + 0x800;
    
    .bss : {
        _bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        _bss_end = .;
    } > RAM
    
    . = ALIGN(64);
    
    .tohost : {
        *(.tohost)
    } > RAM
    
    . = ALIGN(16);
    . = . + 64K;
    _stack_top = .;
    
    _end = .;
    
    /DISCARD/ : {
        *(.comment)
        *(.note.*)
        *(.eh_frame*)
    }
}
```

### 9.6 运行示例

```bash
# 构建
make

# 使用 Spike 运行
spike --isa=rv64gc build/bin/hello.elf

# 预期输出:
# Hello, Baremetal World!
# This is running on RISC-V.
# Integer: 42
# Hex: 0xdeadbeef
# Pointer: 0x80000xxx
# String: test

# 使用 QEMU 运行
qemu-riscv64 build/bin/hello.elf
```

---

## 附录 A: 常用 CSR 寄存器速查

| CSR | 地址 | 说明 |
|-----|------|------|
| mstatus | 0x300 | Machine 状态寄存器 |
| misa | 0x301 | ISA 和扩展 |
| mie | 0x304 | 中断使能 |
| mtvec | 0x305 | Trap 向量基址 |
| mscratch | 0x340 | Machine 临时寄存器 |
| mepc | 0x341 | Machine 异常 PC |
| mcause | 0x342 | Machine 异常原因 |
| mtval | 0x343 | Machine Trap 值 |
| mip | 0x344 | 中断挂起 |
| mcycle | 0xB00 | 周期计数器 |
| minstret | 0xB02 | 指令计数器 |
| mhartid | 0xF14 | Hart ID |

## 附录 B: RISC-V ABI 寄存器约定

| 寄存器 | ABI 名 | 用途 | 调用者/被调用者保存 |
|--------|--------|------|---------------------|
| x0 | zero | 硬连线零 | - |
| x1 | ra | 返回地址 | 调用者 |
| x2 | sp | 栈指针 | 被调用者 |
| x3 | gp | 全局指针 | - |
| x4 | tp | 线程指针 | - |
| x5-x7 | t0-t2 | 临时寄存器 | 调用者 |
| x8 | s0/fp | 保存寄存器/帧指针 | 被调用者 |
| x9 | s1 | 保存寄存器 | 被调用者 |
| x10-x11 | a0-a1 | 参数/返回值 | 调用者 |
| x12-x17 | a2-a7 | 参数 | 调用者 |
| x18-x27 | s2-s11 | 保存寄存器 | 被调用者 |
| x28-x31 | t3-t6 | 临时寄存器 | 调用者 |

---

**文档版本**: 1.0  
**最后更新**: 2024


