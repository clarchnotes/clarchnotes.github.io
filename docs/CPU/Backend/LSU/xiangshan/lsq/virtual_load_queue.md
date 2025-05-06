# VirtualLoadQueue

## 1. 模块概述

`VirtualLoadQueue.scala` 实现了一个高效的逻辑加载队列，用于跟踪、管理和监控处理器中标量加载指令的状态。该模块是 XiangShan 处理器 LSQ 系统的核心组件，作为所有 load 指令的"控制平面"，负责维护指令顺序和状态。

### 1.1 核心功能

- 追踪所有标量 load 指令的微操作和执行状态
- 维护 load 指令的分配、执行和提交状态
- 处理重定向和异常恢复机制
- 管理指令队列的入队和出队操作
- 确保内存访问的正确顺序

### 1.2 模块定义

```scala
class VirtualLoadQueue(implicit p: Parameters) extends XSModule
  with HasDCacheParameters
  with HasCircularQueuePtrHelper
  with HasLoadHelper
  with HasPerfEvents {
  // 模块实现
}
```

## 2. 数据结构与接口

### 2.1 IO 接口

```scala
val io = IO(new Bundle() {
  // 控制接口
  val redirect    = Flipped(Valid(new Redirect))          // 重定向/恢复信号

  // 分发阶段接口
  val enq         = new LqEnqIO                           // 入队请求和响应

  // 加载单元接口
  val ldin        = Vec(LoadPipelineWidth, Flipped(DecoupledIO(new LqWriteBundle))) // 从加载单元S3阶段接收

  // 指针接口
  val ldWbPtr     = Output(new LqPtr)                     // 提供给其他模块的写回指针

  // 状态输出
  val lqFull      = Output(Bool())                        // 队列已满指示
  val lqEmpty     = Output(Bool())                        // 队列为空指示

  // 分发控制
  val lqDeq       = Output(UInt(log2Up(CommitWidth + 1).W)) // 每周期出队数量
  val lqCancelCnt = Output(UInt(log2Up(VirtualLoadQueueSize+1).W)) // 取消指令数量
})
```

### 2.2 内部数据结构

#### 2.2.1 队列状态跟踪

```scala
// 每个队列条目的状态标志
val allocated = RegInit(VecInit(List.fill(VirtualLoadQueueSize)(false.B))) // 条目已分配标志
val robIdx = Reg(Vec(VirtualLoadQueueSize, new RobPtr))                    // ROB索引
val uopIdx = Reg(Vec(VirtualLoadQueueSize, UopIdx()))                      // 微操作索引
val committed = Reg(Vec(VirtualLoadQueueSize, Bool()))                     // 指令已提交标志

// 调试信息
val debug_mmio = Reg(Vec(VirtualLoadQueueSize, Bool()))                    // MMIO指令标志
val debug_paddr = Reg(Vec(VirtualLoadQueueSize, UInt(PAddrBits.W)))        // 物理地址
```

#### 2.2.2 队列指针管理

```scala
// 队列指针
val enqPtrExt = RegInit(VecInit((0 until io.enq.req.length).map(_.U.asTypeOf(new LqPtr))))
val enqPtr = enqPtrExt(0).value                          // 入队指针
val deqPtr = Wire(new LqPtr)                             // 出队指针
val deqPtrNext = Wire(new LqPtr)                         // 下一个出队指针
```

## 3. 入队算法

VirtualLoadQueue 处理来自分发阶段的标量加载指令请求。

### 3.1 可用空间检查

```scala
// 计算有效条目数和判断是否可接受新请求
val validCount = distanceBetween(enqPtrExt(0), deqPtr)
val allowEnqueue = validCount <= (VirtualLoadQueueSize - LSQLdEnqWidth).U
```

### 3.2 入队过程

```scala
// 对于每个队列条目
for(i <- 0 until VirtualLoadQueueSize) {
  val entryCanEnqSeq = (0 until io.enq.req.length).map { j =>
    val entryHitBound = enqLowBound(j).value <= i.U && i.U < enqUpBound(j).value
    canEnqueue(j) && !enqCancel(j) && entryHitBound
  }
  val entryCanEnq = entryCanEnqSeq.reduce(_ || _)
  val selectBits = ParallelPriorityMux(entryCanEnqSeq, io.enq.req.map(_.bits))

  when (entryCanEnq) {
    allocated(i) := true.B
    robIdx(i) := selectBits.robIdx
    uopIdx(i) := selectBits.uopIdx
    committed(i) := false.B

    debug_mmio(i) := false.B
    debug_paddr(i) := 0.U
  }
}
```

### 3.3 入队回应

```scala
// 向分发阶段提供分配结果
for (i <- 0 until io.enq.req.length) {
  val lqIdx = enqPtrExt(0) + i.U
  val index = io.enq.req(i).bits.lqIdx
  XSError(canEnqueue(i) && !enqCancel(i) && index.value =/= lqIdx.value,
          s"must be the same entry $i\n")
  io.enq.resp(i) := lqIdx
}
```

## 4. 队列管理算法

### 4.1 指针更新

```scala
// 更新入队指针
when (lastLastCycleRedirect.valid) {
  // 重定向后恢复指针
  enqPtrExt := VecInit(enqPtrExt.map(_ - redirectCancelCount))
} .otherwise {
  // 正常更新指针
  enqPtrExt := VecInit(enqPtrExt.map(_ + enqNumber))
}
```

### 4.2 出队逻辑

```scala
// 查找可以出队的条目
val DeqPtrMoveStride = CommitWidth
val deqLookupVec = VecInit((0 until DeqPtrMoveStride).map(deqPtr + _.U))
val deqLookup = VecInit(deqLookupVec.map(ptr =>
  allocated(ptr.value) && committed(ptr.value) && ptr =/= enqPtrExt(0)))
val deqInSameRedirectCycle = VecInit(deqLookupVec.map(ptr => needCancel(ptr.value)))

// 计算出队数量
val deqCountMask = Wire(UInt(DeqPtrMoveStride.W))
deqCountMask := deqLookup.asUInt & (~deqInSameRedirectCycle.asUInt).asUInt
val commitCount = PopCount(PriorityEncoderOH(~deqCountMask) - 1.U)
val lastCommitCount = GatedRegNext(commitCount)

// 更新出队指针
val deqPtrUpdateEna = lastCommitCount =/= 0.U
deqPtrNext := deqPtr + lastCommitCount
deqPtr := RegEnable(deqPtrNext, 0.U.asTypeOf(new LqPtr), deqPtrUpdateEna)
```

## 5. 加载写回处理

VirtualLoadQueue 接收来自加载单元的执行结果，并更新相应条目的状态。

```scala
for(i <- 0 until LoadPipelineWidth) {
  io.ldin(i).ready := true.B
  val loadWbIndex = io.ldin(i).bits.uop.lqIdx.value

  val need_rep = io.ldin(i).bits.rep_info.need_rep
  val need_valid = io.ldin(i).bits.updateAddrValid

  when (io.ldin(i).valid) {
    val hasExceptions = ExceptionNO.selectByFu(io.ldin(i).bits.uop.exceptionVec, LduCfg).asUInt.orR
    when (!need_rep && need_valid) {
      committed(loadWbIndex) := true.B
      debug_mmio(loadWbIndex) := io.ldin(i).bits.mmio
      debug_paddr(loadWbIndex) := io.ldin(i).bits.paddr
    }
  }
}
```

## 6. 恢复机制

当发生分支预测错误或异常时，VirtualLoadQueue 需要恢复到正确状态。

```scala
// 计算需要取消的条目
val needCancel = WireInit(VecInit((0 until VirtualLoadQueueSize).map(i => {
  robIdx(i).needFlush(io.redirect) && allocated(i)
})))

// 取消相关条目的分配
for (i <- 0 until VirtualLoadQueueSize) {
  when (needCancel(i)) {
    allocated(i) := false.B
  }
}

// 计算取消数量用于恢复指针
val lastCycleCancelCount = PopCount(lastNeedCancel)
val redirectCancelCount = RegEnable(lastCycleCancelCount + lastEnqCancel, 0.U, lastCycleRedirect.valid)
```

## 7. 状态管理与性能监控

```scala
// 输出队列状态
io.lqEmpty := RegNext(validCount === 0.U)
io.lqFull := !allowEnqueue
io.lqDeq := GatedRegNext(lastCommitCount)
io.lqCancelCnt := redirectCancelCount
io.ldWbPtr := deqPtr

// 性能计数
QueuePerf(VirtualLoadQueueSize, validCount, !allowEnqueue)
XSPerfAccumulate("mem_stall_anyload", memStallAnyLoad)
```

## 8. 标量加载指令处理流程示例

下面通过一个标量加载指令的处理流程来说明 VirtualLoadQueue 的工作机制。

### 初始状态

假设系统的初始状态为：

- 队列容量：`VirtualLoadQueueSize = 32`
- 当前队列状态：`enqPtr = {value=10, flag=0}`，`deqPtr = {value=8, flag=0}`
- 大部分条目未分配

### 第 1 步：指令分发阶段

当处理器分发一条标量加载指令（如 LD x5, 0(x6)）时：

```scala
io.enq.req(0).valid = true
io.enq.req(0).bits.robIdx = 42  // 在ROB中的索引
io.enq.req(0).bits.uopIdx = 3   // 微操作索引
```

1. **队列状态检查**：

	- `validCount = 10 - 8 = 2`（当前有 2 个有效条目）
	- `allowEnqueue = true`（队列未满，可以接受新请求）

2. **条目分配**：

	- 条目 10 被分配给该指令：

     ```scala
     allocated(10) = true
     robIdx(10) = 42
     uopIdx(10) = 3
     committed(10) = false
     ```

3. **指针更新**：

	- `enqPtrExt` 更新为 11（增加一个条目）

4. **返回分配结果**：
	- `io.enq.resp(0) = {value=10, flag=0}`

### 第 2 步：执行阶段

加载指令进入执行阶段，流经加载单元的流水线：

1. **加载发射**：指令从保留站发射到加载单元
2. **地址计算**：在 S1 阶段计算有效地址
3. **缓存访问**：在 S2 阶段访问数据缓存
4. **数据返回**：在 S3 阶段获取数据并写回

### 第 3 步：写回 VirtualLoadQueue

当加载指令在 S3 阶段完成后，结果通过 `ldin` 接口写回 VirtualLoadQueue：

```scala
io.ldin(0).valid = true
io.ldin(0).bits.uop.lqIdx.value = 10
io.ldin(0).bits.rep_info.need_rep = false  // 不需要重播
io.ldin(0).bits.updateAddrValid = true     // 地址有效
io.ldin(0).bits.paddr = 0x80001000         // 访问的物理地址
io.ldin(0).bits.mmio = false               // 不是MMIO访问
```

VirtualLoadQueue 处理该写回：

```scala
when (!need_rep && need_valid) {
  committed(10) := true.B          // 标记为已提交
  debug_mmio(10) := false          // 记录MMIO状态
  debug_paddr(10) := 0x80001000    // 记录物理地址
}
```

### 第 4 步：出队处理

在接下来的周期中，VirtualLoadQueue 会检查哪些条目可以出队：

1. **出队检查**：
	- 对于条目 8 和 9（假设已提交）
	- 对于条目 10（我们的加载指令）
		- `allocated(10) = true`
		- `committed(10) = true`
		- 可以出队

2. **计算出队数量**：

	- `deqCountMask = 0b111`（条目 8-10 都可以出队）
	- `commitCount = 3`（可以出队 3 个条目）

3. **更新出队指针**：

	- `deqPtrNext = 8 + 3 = 11`
	- 下一个周期 `deqPtr` 更新为 11

4. **释放条目**：
	- 条目 8-10 的 `allocated` 标志设置为 `false`
	- 这些条目现在可以被重新分配

### 第 5 步：状态更新

最终队列状态：

- `enqPtr = {value=11, flag=0}`
- `deqPtr = {value=11, flag=0}`
- 条目 8-10 被释放
- `validCount = 0`，队列为空

## 9. 重定向处理示例

当发生分支预测错误时，VirtualLoadQueue 需要取消错误路径上的指令。

### 初始状态

假设队列中有多个条目，其中一些来自错误预测的路径：

- 条目 12-15：来自正确路径的指令（`robIdx = 40-43`）
- 条目 16-18：来自错误路径的指令（`robIdx = 44-46`）
- `enqPtr = {value=19, flag=0}`

### 重定向处理

1. **接收重定向信号**：

   ```scala
   io.redirect.valid = true
   io.redirect.bits.robIdx = 44  // 从robIdx=44开始的指令都需要取消
   ```

2. **识别需要取消的条目**：

   ```scala
   needCancel = [false, false, false, ..., false, true, true, true, false, ...]
                 条目0   条目1   条目2      条目11  条目16 条目17 条目18 条目19
   ```

3. **取消分配**：

   ```scala
   for (i <- 0 until VirtualLoadQueueSize) {
     when (needCancel(i)) {
       allocated(i) := false.B
     }
   }
   ```

   条目 16-18 被标记为未分配

4. **计算取消数量**：

```
   lastCycleCancelCount = 3  // 取消了3个条目
```

5. **恢复入队指针**：
   ```
   enqPtrExt := VecInit(enqPtrExt.map(_ - redirectCancelCount))
   // 从19减至16
   ```

最终状态：

- `enqPtr = {value=16, flag=0}`
- 条目 16-18 被标记为未分配
- 系统可以从正确路径继续执行

## 10. 总结与应用

VirtualLoadQueue 模块实现了一个高效的标量加载指令跟踪队列，具有以下特点：

1. **高效分配**：O(1)时间复杂度的资源分配
2. **状态跟踪**：精确跟踪每条加载指令的执行状态
3. **快速恢复**：提供高效的重定向恢复机制
4. **循环复用**：使用循环队列机制高效利用有限资源
5. **协同工作**：与其他 LSQ 模块协作，维护内存访问顺序

在 XiangShan 处理器中，VirtualLoadQueue 作为 LSQ 系统的核心组件，负责维护加载指令的状态和顺序，为正确的乱序执行提供基础保障。通过与 LoadQueueRAW、LoadQueueRAR 等模块的协同工作，确保内存访问的一致性和正确性，是实现高性能内存系统的关键部分。
