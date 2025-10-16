# 关键CSR寄存器详解

H扩展引入了大量CSR来为Guest OS构建一个"虚拟的硬件环境"，同时为Hypervisor提供管理和控制能力。

## Hypervisor控制寄存器

### hstatus (Hypervisor Status Register)

`hstatus`寄存器包含Hypervisor的状态信息：

| 字段 | 位 | 描述 |
|------|----|----- |
| SPV  | 7  | Supervisor Previous Virtualization mode |
| GVA  | 6  | Guest Virtual Address |
| SPVP | 8  | Supervisor Previous Virtual Privilege |
| VGEIN| 17:12 | Virtual Guest External Interrupt Number |

**关键字段详解：**

- **SPV (Supervisor Previous Virtualization mode):** 用于记录在陷入Hypervisor之前，`V`是0还是1。当从HS-mode返回时，硬件会恢复这个状态。

- **GVA (Guest Virtual Address):** 如果为1，表示当`htval`中写入GPA时，`htval`的最高位也应该被设置。

- **VGEIN (Virtual Guest External Interrupt Number):** 控制Hypervisor如何向Guest注入外部中断。

### htval & htinst

这两个寄存器在处理第二阶段地址翻译异常时至关重要：

**htval (Hypervisor Trap Value):**

- 当发生由第二阶段地址翻译引起的异常时，`htval`会保存导致错误的GPA
- 为Hypervisor提供了精确的错误地址信息

**htinst (Hypervisor Trap Instruction):**

- 保存导致错误的指令本身或其部分信息
- 帮助Hypervisor理解异常的上下文和处理方式

### hedeleg & hideleg

控制异常和中断的委托机制：

```c
// hedeleg - Hypervisor Exception Delegation
// 每个位对应一种异常，1表示委托给Guest OS处理
hedeleg register format:
Bit 0:  Instruction address misaligned
Bit 1:  Instruction access fault
Bit 2:  Illegal instruction
Bit 3:  Breakpoint
...
Bit 15: Store/AMO page fault

// hideleg - Hypervisor Interrupt Delegation  
// 每个位对应一种中断，1表示委托给Guest OS处理
hideleg register format:
Bit 1:  Supervisor software interrupt
Bit 5:  Supervisor timer interrupt
Bit 9:  Supervisor external interrupt
```

## Guest虚拟化CSR (vs*系列)

H扩展为Guest OS提供了一整套虚拟的S-mode CSRs：

### vsstatus (Virtual Supervisor Status)

Guest OS的状态寄存器，格式与`sstatus`相同：

| 字段 | 位 | 描述 |
|------|----|----- |
| SIE  | 1  | Supervisor Interrupt Enable |
| SPIE | 5  | Supervisor Previous Interrupt Enable |
| SPP  | 8  | Supervisor Previous Privilege |
| SUM  | 18 | Supervisor User Memory access |
| MXR  | 19 | Make eXecutable Readable |

### vsie & vsip (Virtual Supervisor Interrupt Enable/Pending)

虚拟中断控制寄存器：

```c
vsie (Virtual Supervisor Interrupt Enable):
Bit 1:  SSIE (Supervisor Software Interrupt Enable)
Bit 5:  STIE (Supervisor Timer Interrupt Enable)  
Bit 9:  SEIE (Supervisor External Interrupt Enable)

vsip (Virtual Supervisor Interrupt Pending):
Bit 1:  SSIP (Supervisor Software Interrupt Pending)
Bit 5:  STIP (Supervisor Timer Interrupt Pending)
Bit 9:  SEIP (Supervisor External Interrupt Pending)
```

### vstvec (Virtual Supervisor Trap Vector Base)

Guest OS的陷阱向量基址：

| 字段 | 位范围 | 描述 |
|------|--------|------|
| BASE | XLEN-1:2 | 陷阱向量基址 |
| MODE | 1:0 | 向量模式 (0=Direct, 1=Vectored) |

### 其他vs*寄存器

- **vsscratch:** Guest OS的临时寄存器，用于保存上下文
- **vsepc:** Guest异常程序计数器，保存异常发生时的PC
- **vscause:** Guest异常原因寄存器，记录异常或中断的类型
- **vstval:** Guest陷阱值寄存器，提供异常相关的额外信息
- **vsatp:** Guest地址翻译寄存器，控制第一阶段地址翻译

## CSR访问重定向

当Guest OS执行CSR指令时，硬件会自动重定向到对应的虚拟CSR：

```assembly
# Guest OS代码
csrrw x1, satp, x2     # 实际访问的是vsatp，不是物理的satp
csrr  x3, sstatus      # 实际访问的是vsstatus
csrw  stvec, x4        # 实际访问的是vstvec
```

### 访问映射表

| Guest OS访问的CSR | 实际访问的CSR | 说明 |
|------------------|---------------|------|
| sstatus | vsstatus | 虚拟状态寄存器 |
| sie     | vsie     | 虚拟中断使能 |
| sip     | vsip     | 虚拟中断挂起 |
| stvec   | vstvec   | 虚拟陷阱向量 |
| sscratch| vsscratch| 虚拟临时寄存器 |
| sepc    | vsepc    | 虚拟异常PC |
| scause  | vscause  | 虚拟异常原因 |
| stval   | vstval   | 虚拟陷阱值 |
| satp    | vsatp    | 虚拟地址翻译 |

## 示例：中断注入过程

Hypervisor向Guest注入定时器中断的完整过程：

```c
// 1. Hypervisor接收物理定时器中断
void hypervisor_timer_handler() {
    // 2. 决定哪个Guest应该接收这个中断
    int target_vm = select_target_vm();
    
    // 3. 在目标Guest的vsip中设置定时器中断挂起位
    csr_set(vsip, STIP_BIT);
    
    // 4. 切换到目标Guest执行
    switch_to_guest(target_vm);
}

// 当Guest恢复执行时：
// - 硬件检查vsip & vsie  
// - 发现挂起且使能的定时器中断
// - 自动触发陷阱到Guest的VS-mode
// - Guest的定时器中断处理程序被调用
```

## 性能优化考虑

### CSR访问开销

虚拟CSR的实现需要考虑性能：

1. **寄存器映射:** vs*寄存器通常作为独立的物理寄存器实现
2. **上下文切换:** VM切换时需要保存/恢复所有vs*寄存器
3. **访问频率:** 频繁访问的CSR（如vsatp）需要特别优化

### 硬件优化技术

1. **寄存器重命名:** 将vs*寄存器映射到物理寄存器文件
2. **延迟同步:** 某些CSR的更新可以延迟到必要时才同步
3. **缓存机制:** 将常用的CSR值缓存在处理器内部

这种精心设计的CSR架构使得Guest OS可以无缝运行，同时为Hypervisor提供了完整的控制和监控能力。
