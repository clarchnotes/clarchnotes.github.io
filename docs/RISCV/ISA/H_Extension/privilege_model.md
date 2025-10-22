# 虚拟化特权级模型与陷阱处理

## 虚拟化特权级模型

H扩展引入了一个关键概念：当`V=1`时，系统处于虚拟化模式。这在S模式之上叠加了一层，形成了新的特权级。

### 特权级定义

*  **HS-mode (Hypervisor-extended Supervisor mode):**  Hypervisor运行的模式。在这里，`V=0`。
*  **VS-mode (Virtual Supervisor mode):**  Guest OS内核运行的模式。在这里，`V=1`。
*  **VU-mode (Virtual User mode):**  Guest OS用户程序运行的模式。在这里，`V=1`。

当CPU在VS或VU模式下运行时，所有特权操作，如访问CSR、执行`SRET`等，都会受到Hypervisor的控制。

### 特权级转换

```text
M-mode (机器模式)
    ↕ MRET/异常
HS-mode (V=0, Hypervisor)
    ↕ SRET/异常 
VS-mode (V=1, Guest内核)
    ↕ SRET/异常
VU-mode (V=1, Guest用户)
```

## 陷阱委托机制

### 委托控制寄存器

当在`V=1`模式下（即在Guest内部）发生异常或中断时，硬件需要决定这个陷阱应该由Guest OS（在VS-mode）处理，还是需要退出到Hypervisor（在HS-mode）处理。这个决策过程由以下CSR控制：

1.  **`hedeleg` (Hypervisor Exception Delegation):**  决定哪些 **同步异常** （如缺页、非法指令）可以被委托给Guest OS自己处理，而无需Hypervisor介入。
2.  **`hideleg` (Hypervisor Interrupt Delegation):**  决定哪些 **中断** 可以被委托给Guest OS自己处理。
3.  **`hgatp` (Hypervisor Guest Address Translation and Protection):**  第二阶段地址翻译失败（Guest Page Fault）总是会陷入到Hypervisor。

### 陷阱处理流程

**流程示例：**
假设一个运行在VU-mode的程序发生了缺页异常（Store page fault）。

1.  **硬件检查`hedeleg`寄存器** 中对应"Store page fault"的比特位。

2.  **如果该位为1（委托）：** 
   * 陷阱被路由到Guest OS的VS-mode
   * 硬件会自动更新`vscause`, `vsepc`, `vstvec`等VS-mode的CSRs
   * 跳转到Guest OS的异常处理程序
   * 整个过程Hypervisor **完全不感知** 

3.  **如果该位为0（不委托）：** 
   * 陷阱被路由到Hypervisor的HS-mode
   * 硬件会更新`scause`, `sepc`等HS-mode的CSRs
   * 跳转到Hypervisor的异常处理程序
   * 由Hypervisor来决定如何处理这个异常

### hedeleg寄存器详解

`hedeleg`是一个64位寄存器，每个位对应一种异常类型：

| 位 | 异常类型 | 描述 |
|----|----------|------|
| 0  | Instruction address misaligned | 指令地址未对齐 |
| 1  | Instruction access fault | 指令访问错误 |
| 2  | Illegal instruction | 非法指令 |
| 3  | Breakpoint | 断点 |
| 4  | Load address misaligned | 加载地址未对齐 |
| 5  | Load access fault | 加载访问错误 |
| 6  | Store/AMO address misaligned | 存储/原子操作地址未对齐 |
| 7  | Store/AMO access fault | 存储/原子操作访问错误 |
| 8  | Environment call from U-mode | 来自U模式的环境调用 |
| 9  | Environment call from S-mode | 来自S模式的环境调用 |
| 12 | Instruction page fault | 指令缺页 |
| 13 | Load page fault | 加载缺页 |
| 15 | Store/AMO page fault | 存储/原子操作缺页 |

### hideleg寄存器详解

`hideleg`控制中断的委托：

| 位 | 中断类型 | 描述 |
|----|----------|------|
| 1  | Supervisor software interrupt | 监管者软件中断 |
| 5  | Supervisor timer interrupt | 监管者定时器中断 |
| 9  | Supervisor external interrupt | 监管者外部中断 |

## 陷阱处理性能优化

这种委托机制是性能的关键，它使得Guest OS可以像在裸机上一样高效地处理自己的异常和中断。

### 典型的委托配置

```c
// 将大多数异常委托给Guest OS处理
hedeleg = (1 << 0)  |  // Instruction address misaligned
          (1 << 1)  |  // Instruction access fault  
          (1 << 2)  |  // Illegal instruction
          (1 << 4)  |  // Load address misaligned
          (1 << 5)  |  // Load access fault
          (1 << 6)  |  // Store address misaligned
          (1 << 7)  |  // Store access fault
          (1 << 8)  |  // U-mode ecall
          (1 << 12) |  // Instruction page fault
          (1 << 13) |  // Load page fault
          (1 << 15);   // Store page fault

// 将定时器和软件中断委托给Guest OS
hideleg = (1 << 1) |   // Supervisor software interrupt
          (1 << 5);    // Supervisor timer interrupt
          // 注意：外部中断通常不委托，由Hypervisor处理后注入
```

### 不可委托的异常

某些异常 **永远不会被委托**  ，总是陷入到Hypervisor：

1.  **第二阶段地址翻译失败**  - 因为只有Hypervisor管理第二阶段页表
2.  **Guest尝试访问Hypervisor专用CSR**  - 安全隔离要求
3.  **Hypervisor自身的异常**  - 当`V=0`时发生的所有异常

这种精细的控制机制确保了虚拟化的安全性和性能的平衡。
