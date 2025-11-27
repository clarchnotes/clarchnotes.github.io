# Spike 模拟器

Spike 是 RISC-V 的官方指令集模拟器（ISA Simulator），用于执行 RISC-V 二进制程序。本节详细介绍 Spike 的工作原理、启动流程以及相关组件。

## 概述

Spike 作为一个功能完整的 RISC-V 模拟器，可以：

- 模拟完整的 RISC-V 处理器（包括 M/S/U 三种权限模式）
- 执行用户程序和操作系统
- 提供调试和追踪功能
- 支持多核和各种 RISC-V 扩展

## 核心组件

使用 Spike 运行用户程序时，涉及以下核心组件：

### Spike（模拟器本身）

作为"虚拟硬件"，Spike 负责：

- 模拟 RISC-V CPU 核心和内存
- 提供主机接口（HTIF）用于 I/O
- 加载并启动引导加载器

### BBL (Berkeley Boot Loader)

运行在 **M-mode（机器模式）**的引导加载器：

- 完成最底层的硬件初始化
- 解析设备树（Device Tree）
- 加载并启动操作系统或代理内核

### PK (Proxy Kernel)

运行在 **S-mode（监管者模式）**的轻量级内核：

- 加载用户程序的 ELF 文件
- 建立虚拟内存环境（页表）
- 处理系统调用并代理给 Spike
- 提供最小化的"类操作系统"环境

## 主要内容

### [启动流程总览](boot_flow_overview.md)

详细解析从 `spike pk my_program` 到 `main` 函数执行的完整过程。

### [RISC-V 权限级别](privilege_levels.md)

深入理解 M-mode、S-mode 和 U-mode 的设计与权限交接机制。

### [BBL 引导加载器](bbl_bootloader.md)

BBL 的职责、初始化流程以及如何移交控制权给 PK。

### [PK 代理内核](pk_proxy_kernel.md)

PK 的"代理"含义、虚拟内存建立、用户程序加载过程。

### [系统调用代理机制](syscall_proxy.md)

深入分析 `ecall` 指令如何触发陷阱、PK 如何代理系统调用给 Spike。

## 关键概念

### 权限交接链

```
Spike (硬件)
  ↓ 加载
BBL (M-mode)
  ↓ mret
PK (S-mode)
  ↓ sret
User Program (U-mode)
```

### "代理"的含义

PK 被称为"代理内核"是因为：

- 它不真正管理硬件资源
- 它将用户程序的系统调用请求转发（代理）给 Spike
- Spike 再在宿主机上完成实际的 I/O 操作

这使得 PK 非常轻量，但足以让用户程序"以为"自己运行在完整的操作系统上。

## 适用场景

Spike + PK 组合适用于：

- ✅ 单进程程序的功能验证
- ✅ RISC-V 指令集测试
- ✅ 向量运算和算法原型开发
- ❌ 多进程/多线程的真实操作系统场景（应使用 Linux）
- ❌ 需要真实硬件驱动的场景

## 与真实操作系统的对比

| 特性 | PK (代理内核) | Linux (真实 OS) |
|-----|-------------|----------------|
| 进程管理 | ❌ 仅支持单进程 | ✅ 多进程调度 |
| 虚拟内存 | ✅ 基础页表 | ✅ 完整内存管理 |
| 设备驱动 | ❌ 无 | ✅ 大量驱动 |
| 文件系统 | ❌ 无（通过 HTIF 代理） | ✅ 完整文件系统 |
| 系统调用 | ✅ 有限支持 | ✅ 完整 POSIX API |
| 启动时间 | ⚡ 极快 | 🐢 较慢 |

## 参考资源

- [RISC-V Spike 官方仓库](https://github.com/riscv-software-src/riscv-isa-sim)
- [RISC-V PK 官方仓库](https://github.com/riscv-software-src/riscv-pk)
- [RISC-V 特权架构规范](https://github.com/riscv/riscv-isa-manual)



