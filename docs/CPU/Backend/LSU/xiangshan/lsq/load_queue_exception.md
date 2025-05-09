
# Load 异常缓冲 LqExceptionBuffer 模块

## 1. 模块概述

`LqExceptionBuffer` 是 XiangShan 处理器 LSQ 系统中的专用组件，负责跟踪和管理加载指令执行过程中可能出现的各类异常。当加载指令执行过程中发生异常（如页错误、访问错误等），该模块负责捕获、缓存这些异常信息，并确保它们能够在适当的时机被精确处理[^1]。

### 1.1 核心功能

- 跟踪记录各类加载指令产生的异常情况
- 根据 ROB 索引选择最老的异常指令
- 向精确异常处理机制提供必要的异常信息和地址
- 支持重定向时的异常条目刷新

## 2. 异常来源

LqExceptionBuffer 处理的异常来自三种主要来源[^1]：

1. **标量加载异常**：来自加载单元(LDU) S3 阶段的标量加载指令异常
2. **向量加载异常**：来自向量加载合并缓冲器(vlMergeBuffer)的向量加载指令异常
3. **MMIO 异常**：来自 LoadUncacheBuffer 的 MMIO non-data 异常

## 3. 流水线结构

LqExceptionBuffer 采用两级流水线结构处理异常[^1]：

1. **第一级流水线**：
   - 缓存来自 LDU 的 S3 阶段输出的信息
   - 记录异常指令的各种信息，包括 ROB 索引、指令类型、虚拟地址和异常向量

2. **第二级流水线**：
   - 根据 ROB 索引(robIdx)选取最老的发生异常的指令
   - 输出该指令的虚拟地址(vaddr)给精确异常处理机制

这种流水线设计使得异常检测和选择可以在高频处理器中高效进行，同时保持异常处理的精确性。

## 4. 数据结构与接口

LqExceptionBuffer 的接口结构大致如下：

```scala
val io = IO(new Bundle() {
  // 控制接口
  val redirect = Flipped(Valid(new Redirect))  // 重定向/恢复信号

  // 输入接口：从加载单元接收执行结果
  val req = Vec(LoadPipelineWidth, Flipped(Valid(new LqWriteBundle)))

  // 输出接口：报告异常地址
  val exceptionAddr = new ExceptionAddrIO
})
```

其中 `ExceptionAddrIO` 包含：
- 异常指令的 ROB 索引
- 异常指令的虚拟地址
- 可能的物理地址
- 异常类型向量

## 5. 异常选择机制

LqExceptionBuffer 使用以下机制选择需要报告的异常：

1. **最老优先**：根据 ROB 索引(robIdx)选择流水线中最老的异常指令
2. **异常优先级**：对于同一指令的多个异常，按照预定义的优先级选择最高优先级的异常
3. **有效性过滤**：只考虑未被重定向刷新的有效异常指令

```scala
// 伪代码示例
val oldestExceptionIdx = Wire(UInt())
// 遍历所有缓存的异常指令，选择最老的一个
for (i <- 0 until BufferSize) {
  when (entries(i).valid && 
        isOlder(entries(i).robIdx, entries(oldestExceptionIdx).robIdx)) {
    oldestExceptionIdx := i.U
  }
}
```

## 6. 重定向处理

当处理器发生重定向（如分支预测错误）时，LqExceptionBuffer 需要清除所有不再有效的异常条目[^1]：

```scala
// 伪代码示例
when (io.redirect.valid) {
  // 清除被重定向刷新的异常条目
  for (i <- 0 until BufferSize) {
    when (entries(i).valid && entries(i).robIdx.needFlush(io.redirect.bits)) {
      entries(i).valid := false.B
    }
  }
}
```

这确保了只有真正有效的异常会被保留并最终报告给处理器的异常处理机制。

## 7. 异常地址报告

LqExceptionBuffer 在第二级流水线中完成异常地址的报告：

```scala
// 伪代码示例
io.exceptionAddr.valid := hasValidException
io.exceptionAddr.bits.robIdx := entries(oldestExceptionIdx).robIdx
io.exceptionAddr.bits.vaddr := entries(oldestExceptionIdx).vaddr
io.exceptionAddr.bits.exceptionVec := entries(oldestExceptionIdx).exceptionVec
```

这些信息将被传递给 ROB，当该异常指令到达提交点时，处理器将使用这些信息进行精确异常处理。

## 8. 典型工作流程

### 8.1 异常捕获和记录

1. 加载单元执行加载指令，检测到异常（如页错误）
2. 异常信息通过 `io.req` 接口发送到 LqExceptionBuffer
3. 第一级流水线缓存该异常信息，包括指令的 ROB 索引、虚拟地址和异常向量

### 8.2 异常选择和报告

1. 第二级流水线扫描所有缓存的异常条目
2. 根据 ROB 索引选择最老的异常指令
3. 将该指令的虚拟地址和异常信息通过 `io.exceptionAddr` 接口报告

### 8.3 异常处理

1. ROB 在尝试提交该指令时检查异常标志
2. 当发现异常时，触发处理器的精确异常处理机制
3. 处理器保存上下文并跳转到相应的异常处理程序

## 9. 总结

LqExceptionBuffer 是 XiangShan 处理器 LSQ 系统中处理加载指令异常的关键组件。它通过两级流水线高效地跟踪来自三种不同来源的异常，并根据程序顺序选择最老的异常进行报告。这个模块是实现精确异常处理的重要部分，确保了乱序执行的处理器能够按照程序顺序处理异常，维护了程序执行的正确性和可预测性。

[^1]: [Load 异常缓冲 LqExceptionBuffer - 香山开源处理器设计文档](https://docs.xiangshan.cc/projects/design/zh-cn/latest/memblock/LSU/LSQ/LqExceptionBuffer/)
