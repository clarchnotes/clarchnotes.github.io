# RISC-V H扩展 (Hypervisor Extension) 虚拟化技术

本节深入探讨RISC-V H扩展的核心技术原理与实现机制。

## 内容导航

- [H扩展概述](overview.md) - 设计目标、架构概览与核心概念
- [虚拟化特权级模型](privilege_model.md) - HS/VS/VU模式与陷阱处理机制
- [两阶段地址翻译](two_stage_translation.md) - GVA→GPA→HPA翻译过程详解
- [关键CSR寄存器](csr_registers.md) - hgatp、hstatus、vs*系列寄存器剖析
- [虚拟中断处理](virtual_interrupts.md) - 中断委托与注入机制
- [新增指令集](new_instructions.md) - HFENCE.VVMA/GVMA指令详解
- [性能优化技术](performance_optimization.md) - VMID、TLB管理与最佳实践

## 技术要点

H扩展通过以下三大核心机制实现高效的硬件辅助虚拟化：

1. **特权级分层** - 在S模式基础上引入HS/VS/VU模式
2. **陷阱委托机制** - 通过hedeleg/hideleg最小化Hypervisor介入
3. **两阶段地址翻译** - 硬件支持Guest虚拟地址到主机物理地址的高效翻译

这些机制协同工作，使Guest OS能够以接近裸机的性能运行，同时为Hypervisor提供完整的隔离和管理能力。

