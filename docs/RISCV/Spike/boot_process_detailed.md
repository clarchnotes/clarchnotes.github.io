# Spike & PK

## 1. 摘要 (Abstract)

本报告详细阐述了在使用 RISC-V Spike 模拟器执行一个用户程序（如 my_program）时，从敲下命令 `spike pk my_program` 到程序 main 函数开始执行的完整内部流程。核心观点是：这个过程是一个权限交接的链条。

- **Spike (模拟器)** 扮演"硬件"，它加载 BBL (启动加载器)。
- **BBL (运行在 M-mode)** 作为"超级管理员"，它初始化机器并加载 PK (代理内核)。
- **PK (运行在 S-mode)** 作为"操作系统"，它为用户程序建立虚拟内存、设置栈，并准备好参数。
- **PK 最终将控制权交给用户程序 (运行在 U-mode)** 。

本报告将逐一拆解 BBL 和 PK 的定义、它们与真实操作系统的区别（"代理"的含义），并按时间顺序详细分析内存布局、系统调用和启动的每一个技术细节。

## 2. 核心概念：BBL, PK 与"真正"的操作系统

在深入流程之前，我们必须先理解"玩家"是谁。这一切都源于 RISC-V 的权限等级。

### 2.1 权限等级 (Privilege Levels)：RISC-V 的"三界"

为了安全，RISC-V 将CPU的运行状态分为三个主要等级（这里我们忽略 H-mode）：

#### M-Mode (Machine Mode - 机器模式)： "超级管理员"或"造物主"

**权限** ： 最高。可以访问所有内存和所有控制与状态寄存器 (CSR)。

**职责** ： 硬件的直接管理者，负责最底层的启动和安全配置。

**类比** ： 大楼的总房东，拥有所有钥匙。

#### S-Mode (Supervisor Mode - 监管者模式)： "操作系统"模式

**权限** ： 次高。可以管理虚拟内存（页表）、处理中断和异常（陷阱）。

**职责** ： 管理用户程序、分配内存、提供系统服务。

**类比** ： 大楼的物业经理，管理租户（程序）的日常需求（水电、内存）。

#### U-Mode (User Mode - 用户模式)： "应用程序"模式

**权限** ： 最低。被严格限制，不能直接访问硬件或修改关键CSR。

**职责** ： 运行用户程序（如你的 C 程序）。

**类比** ： 大楼的租户，在自己的房间里活动，需要服务时（如打印）必须呼叫物业（ecall）。

### 2.2 什么是 BBL (Berkeley Boot Loader)?

BBL 是一个运行在 M-mode 的程序。它本质上是 Spike（或真实硬件）上电后运行的第一个软件。

**主要职责** ：

- **M-mode 初始化** ： 设置 M-mode 的"陷阱"(Trap) 处理程序、配置内存保护 (PMP)。
- **解析硬件** ： 读取设备树 (FDT - Flattened Device Tree)，了解模拟器"硬件"的配置（有多少内存、多少CPU核心等）。
- **加载"下一阶段"** ： 它的主要目标是加载并跳转到一个 S-mode 的程序（通常是 PK，或者是 Linux 内核）。

### 2.3 什么是 PK (Proxy Kernel)?

PK 是一个运行在 S-mode 的程序。它是一个极简的"内核"。

**主要职责** ：

- **加载用户程序** ： 它负责读取你的 my_program ELF 文件。
- **创建运行环境** ： 为用户程序建立虚拟内存（页表）、分配栈空间。
- **服务用户程序** ： 处理来自用户程序的系统调用 (System Call)。

### 2.4 BBL 与 PK 的关系

BBL 和 PK 经常让人困惑，因为它们通常被编译在同一个 ELF 文件里（bbl 或 pk，名字可能混用，但我们这里叫它 bbl ELF）。

- **bbl ELF 文件同时包含 M-mode 代码 (BBL) 和 S-mode 代码 (PK)** 。
- 启动时，Spike 先加载这个 bbl ELF。
- **bbl (M-mode 部分) 先运行** ，完成它的初始化后，主动降低自己的权限，跳转到 **pk (S-mode 部分)** 开始执行。
- 所以，bbl 是 pk 的"引路人"。

### 2.5 什么是"真正的"操作系统 (Real OS)?

一个理论上"完整"的操作系统（如 Linux, Windows）的核心职责远比 PK 复杂：

- **进程/线程管理** ： 创建、调度、切换和销毁多个同时运行的程序。
- **虚拟内存管理** ： 为每个进程提供独立的、受保护的虚拟地址空间。
- **设备驱动** ： 包含大量代码来"驱动"真实的硬件（显卡、网卡、硬盘）。
- **文件系统** ： 在磁盘上管理文件和目录。
- **完整的系统调用接口** ： 提供成百上千种服务（网络、IPC、时间等）。

### 2.6 PK vs. 真实 OS：为什么叫"代理" (Proxy)？

PK 不是一个真正的操作系统。它被称为"代理"内核，因为它不真正管理资源，它只是一个"中间商"和"转发者"。

**PK 实现了什么？**

- 加载单个程序 (不是多进程)。
- 设置虚拟内存 (但很简单)。
- 处理系统调用 (核心)。

**PK 没实现什么 (省略了什么)？**

- **没有调度器** ： 它只能运行 一个 用户程序直到结束。
- **没有设备驱动** ： 它不驱动显卡或网卡。
- **没有文件系统** ： 它不管理磁盘。

**"代理" (Proxy) 的核心含义** ：

当你的 U-mode 程序发起一个系统调用（ecall），比如 printf (内部是 write syscall)：

1. CPU 陷入 (trap) 到 S-mode，PK 获得控制权。
2. PK 看到这是一个 write 请求。
3. PK 不会自己去操作模拟的"显示器"。
4. 相反，**PK 会使用一种特殊的"主机接口" (HTIF - Host-Target Interface) 向 Spike "喊话"** 。
5. **Spike (作为宿主程序) 捕获这个"喊话"，并代替 PK 在你宿主机的终端上打印出字符** 。

PK 只是把 U-mode 程序的请求"代理"给了运行它的 Spike 进程。这就是它叫"代理内核"的根本原因。它是一个轻量级的"垫片"(Shim)，用于连接 U-mode 程序和 Spike 宿主机。

## 3. 完整的启动流程：从 Spike 到 main

我们来分解命令 `spike pk my_program` (这里 pk 就是我们说的 bbl ELF)。

### 3.1 阶段一：Spike 启动 BBL (M-mode)

**Spike 作为"硬件"** ： spike 进程启动，它在内存中创建了一个"模拟的 RISC-V 计算机"（模拟的 CPU 核心、模拟的内存）。

**加载 BBL** ： Spike 读取 pk (BBL ELF) 文件。它像一个加载器一样，把 ELF 文件中标记为"可加载"的段（Segment）复制到它模拟的"内存"中。

**设置入口点** ： Spike 读取 BBL ELF 的头部，找到入口点地址 (Entry Point)，并将模拟 CPU 的 PC 寄存器设置为这个地址。

**开始执行** ： Spike 开始模拟 CPU 循环。CPU 从 PC 寄存器指向的地址（即 BBL 的 `_start`）开始，在 M-mode 下执行第一条指令。

### 3.2 阶段二：BBL (M-mode) 初始化

BBL (M-mode 代码) 现在开始运行了。

**设置 M-mode 陷阱** ： BBL 设置 mtvec 寄存器，指向它的 M-mode 陷阱处理函数。这样，如果发生任何异常，CPU 知道该跳转到哪里。

**清空 BSS** ： BBL 会找到自己的 .bss 段（未初始化的全局变量）并将其清零。

**解析设备树 (FDT)** ： BBL 会在内存中找到 Spike 放置的 FDT blob。它解析这个 FDT，以了解"硬件"配置（例如，内存的起始地址和大小）。

**准备移交 S-mode** ： BBL 知道它的 M-mode 工作即将完成，它需要准备跳转到 S-mode（即 PK 部分）。

### 3.3 阶段三：BBL (M-mode) 移交给 PK (S-mode)

这是最关键的权限"禅让"：

**设置 S-mode 陷阱** ： BBL 设置 stvec 寄存器，使其指向 PK (S-mode 部分) 的陷阱处理函数。

**设置S-mode入口点** ： BBL 将 PK（S-mode）的入口地址写入 mepc (机器异常程序计数器)。

**配置 mstatus** ： BBL 修改 mstatus 寄存器：
- MPP (Machine Previous Privilege) 位设为 S。这告诉 CPU："当我执行 mret 后，请进入 S-mode"。
- MPIE (Machine Previous Interrupt Enable) 位设为 0。

**执行 mret** ： BBL 执行 mret (机器模式返回) 指令。
- CPU 看到 mret，它会查看 mstatus.MPP，发现是 S。
- CPU 自动将权限级别从 M-mode 降为 S-mode。
- CPU 将 PC 设置为 mepc 寄存器中的值（即 PK 的入口点）。

**控制权成功从 M-mode (BBL) 移交给了 S-mode (PK)** 。

### 3.4 阶段四：PK (S-mode) 加载用户程序

PK (S-mode 代码) 现在开始运行了。

**S-mode 初始化** ： PK 也进行一些自己的初始化（清空自己的 .bss 段等）。

**找到用户程序** ： PK 会在启动参数中找到 my_program (你的 C 程序) 的名字。

**加载 ELF 文件** ： PK 会打开 my_program (通过向 Spike 代理"文件打开"请求)，并开始解析 ELF 文件。

**识别段 (Segment)** ： PK 会遍历 ELF 的程序头表 (Program Header Table)，寻找所有 PT_LOAD 类型的段。这通常包括：
- .text 段 (代码)
- .data 段 (已初始化的数据)
- .rodata 段 (只读数据)

### 3.5 阶段五：PK (S-mode) 建立用户内存空间

这是 PK 作为"内核"的核心工作：为用户程序创建虚拟内存环境。

**创建页表 (Page Tables)** ： PK 作为 S-mode 程序，有权操作 satp 寄存器（页表基址）。它在内存中创建一套S-mode 页表。

**映射程序段** ： 对于上一步找到的每个段，PK 会：
- 分配物理内存页面。
- 将 ELF 文件中的数据（如 .text 和 .data）从磁盘（通过 Spike 代理）读入这些物理页面。
- 在页表中建立虚拟地址 (VA) 到物理地址 (PA) 的映射。
- 设置权限位：
  - .text 段：映射为 Read | Execute
  - .data 段：映射为 Read | Write
  - .rodata 段：映射为 Read

**处理 .bss 段** ： .bss 段（未初始化的全局变量）在 ELF 文件中不占空间。PK 只需：
- 分配一些物理页面（通常是全零页面）。
- 在页表中将 .bss 对应的虚拟地址范围映射到这些页面，权限为 Read | Write。

**创建用户栈 (User Stack)** ：
- PK 会分配几页内存作为用户程序的栈。
- 它在页表中将这些页面映射到一个高的虚拟地址（例如 0x7FFF_FFFF 向下）。
- PK 会初始化 sp (栈指针) 寄存器，使其指向这个栈的顶部。

**准备 argc, argv, envp (关键细节)** ：
- C 程序的 main 函数需要 argc (参数个数) 和 argv (参数字符串数组)。
- PK 会在用户栈的顶部（sp 指向的位置）手动构建这个数据结构。
- 它会把 my_program 和其他参数字符串复制到栈上，并设置好指针数组 argv。

**准备堆 (Heap) 与 sbrk** ：
- PK 会在 .bss 段之后（内存中）记录一个"程序中断点" (break) 的地址，我们称之为 mem_end。
- 这就是堆的起始位置。
- 当用户程序调用 malloc (内部是 sbrk syscall) 时，PK 会处理这个 sbrk 请求（见 4.3 节）。

### 3.6 阶段六：PK (S-mode) 移交给用户程序 (U-mode)

万事俱备，PK 要进行最后一次"禅让"：

**激活页表** ： PK 将它刚刚创建的页表的基地址写入 satp 寄存器，开启虚拟内存。

**设置 U-mode 入口点** ： PK 将 my_program 的入口点地址（`_start`，注意：不是 main）写入 sepc (监管者异常程序计数器)。

**配置 sstatus** ： PK 修改 sstatus 寄存器：
- SPP (Supervisor Previous Privilege) 位设为 U。这告诉 CPU："当我执行 sret 后，请进入 U-mode"。
- SPIE (Supervisor Previous Interrupt Enable) 位设为 1，以便 U-mode 可以响应中断。

**执行 sret** ： PK 执行 sret (监管者模式返回) 指令。
- CPU 看到 sret，它会查看 sstatus.SPP，发现是 U。
- CPU 自动将权限级别从 S-mode 降为 U-mode。
- CPU 将 PC 设置为 sepc 寄存器中的值（即 my_program 的 `_start` 地址）。
- CPU 自动切换到使用 satp 指定的页表进行地址翻译。

**控制权成功从 S-mode (PK) 移交给了 U-mode (用户程序)** 。

## 4. 程序的执行与"代理"

### 4.1 从 `_start` 到 main

你的程序不会从 main 开始。它从 C 语言运行时 (CRT) 的 `_start` 标签开始。

- `_start` (由链接器加入) 会执行少量设置（例如设置 fp 寄存器）。
- 它会从 sp 寄存器（由 PK 设置）中获取 argc 和 argv。
- `_start` 代码最后会调用 `main(argc, argv, envp)`。

现在，你的 main 函数终于开始执行了！

### 4.2 系统调用 (ECALL) 的"代理"

当你的 main 函数执行 `printf("Hello")` 时：

1. printf (C 库) 最终会调用 write 系统调用。
2. C 库将 write 的系统调用号 (例如 SYS_write) 放入 a7 寄存器，参数（文件描述符、缓冲区地址、长度）放入 a0, a1, a2。
3. C 库执行 `ecall` (环境调用) 指令。

**Trap!** CPU 发现 U-mode 试图 ecall，立即暂停 U-mode 程序。
- CPU 自动将权限提升到 S-mode。
- CPU 将当前的 PC（ecall 的下一条指令）存入 sepc，将陷入原因（ecall from U-mode）存入 scause。
- CPU 跳转到 stvec 指向的地址，即 PK 的 S-mode 陷阱处理函数。

**PK (S-mode) 接管** ：
- PK 查看 scause，发现是 ecall。
- PK 查看 a7，发现是 SYS_write。
- PK 从 a0, a1, a2 读取参数。

**"代理"开始** ： 
- PK 使用 HTIF (主机接口) 向 Spike 发送一个"write"请求，附带数据。
- Spike 进程捕获这个 HTIF 请求，并在你宿主机的终端上打印出 "Hello"。

**返回 U-mode** ：
- PK 将 write 的返回值（例如 5）放入 a0 寄存器。
- PK 执行 sret。
- CPU 权限降回 U-mode，PC 从 sepc 恢复，你的 C 程序从 ecall 的下一条指令继续执行，仿佛什么都没发生过（除了 a0 中多了个返回值）。

### 4.3 sbrk 的实现 (Heap)

当你的程序调用 malloc，它最终会请求 sbrk 系统调用来扩大堆。

1. ecall 陷入 S-mode (同上)。
2. PK 发现是 SYS_sbrk 请求。
3. PK 不会向 Spike 代理。它只是在内部更新它为该程序维护的 mem_end 指针。
   - 例如，请求 4KB，PK 就将 mem_end 增加 4096，并可能在页表中映射一个新的页面（如果需要）。
4. PK 将旧的 mem_end 地址作为返回值（通过 a0）返回给 U-mode。
5. malloc 库现在知道它获得了 [old_mem_end, new_mem_end) 这段内存。

## 5. 总结

`spike pk my_program` 这个简单的命令背后，是一个精妙的权限交接和环境设置过程：

1. **Spike (硬件模拟)** 启动
2. **BBL (M-mode)** 接管，初始化机器，然后 mret...
3. **PK (S-mode)** 接管，解析用户 ELF，建立页表，设置栈，然后 sret...
4. **my_program (U-mode)** 接管，从 `_start` 运行到 main。
5. **my_program 通过 ecall 向 PK (S-mode) 请求服务** 。
6. **PK (S-mode) 将这些请求"代理"给 Spike (宿主机) 来完成** 。

这个设计使得 pk 非常轻量，它不需要成为一个完整的操作系统，却能为用户程序提供一个"看起来像"操作系统的标准运行环境，使其能专注于算法和向量计算（如果您在跑向量程序），而无需关心底层的启动和I/O细节。


