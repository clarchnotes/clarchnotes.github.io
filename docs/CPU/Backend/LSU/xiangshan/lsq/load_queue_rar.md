
# LoadQueueRAR

## 1. 模块概述

`LoadQueueRAR.scala` 实现了XiangShan处理器中的读后读(RAR: Read-After-Read)依赖检测机制。这个模块负责维护处理器内存访问的顺序一致性，特别是对于可能导致内存模型违例的加载-加载指令序列。与LoadQueueRAW不同，LoadQueueRAR主要处理多核环境下的内存一致性问题。

### 1.1 核心功能

- 检测多核环境下可能违反内存模型顺序约束的加载指令对
- 处理缓存一致性事件（如cache line eviction/release）对加载指令的影响
- 支持RISC-V内存模型下的顺序保证
- 为跨核心的内存一致性提供基础支持
- 在检测到违例时通知相关加载指令进行重新执行

### 1.2 模块定义

```scala
class LoadQueueRAR(implicit p: Parameters) extends XSModule
  with HasDCacheParameters
  with HasCircularQueuePtrHelper
  with HasPerfEvents {
  // 模块实现
}
```

## 2. 数据结构与接口

### 2.1 IO 接口

```scala
val io = IO(new Bundle() {
  // 控制接口
  val redirect = Flipped(Valid(new Redirect))
  val release = Flipped(Valid(new Release))
  val ldWbPtr = Input(new LqPtr)
  
  // 查询接口
  val query = Vec(LoadPipelineWidth, new LoadToLoadQueryIO)
  
  // 状态接口
  val lqFull = Output(Bool())
  val validCount = Output(UInt())
})
```

### 2.2 内部数据结构

```scala
// 已执行的加载指令记录
val allocated = RegInit(VecInit(List.fill(RarQueueSize)(false.B)))  // 条目是否有效
val uop = Reg(Vec(RarQueueSize, new MicroOp))                       // 微操作信息
val paddr = Reg(Vec(RarQueueSize, UInt(16.W)))                      // 压缩后的物理地址(16bits)
val mask = Reg(Vec(RarQueueSize, UInt(8.W)))                        // 访问掩码
val robIdx = Reg(Vec(RarQueueSize, new RobPtr))                     // ROB索引
val released = RegInit(VecInit(List.fill(RarQueueSize)(false.B)))   // 是否被释放标记

// 队列指针管理
val enqPtrExt = RegInit(0.U.asTypeOf(new RarQueuePtr))
val deqPtrExt = RegInit(0.U.asTypeOf(new RarQueuePtr))
```

## 3. RAR依赖违例机制

### 3.1 多核环境下的RAR违例

单核环境下，相同地址的加载指令乱序执行通常不会导致问题。但在多核环境下，如果出现以下情况会导致RAR违例：

1. 当前核心有两个访问相同地址的加载指令A和B（程序顺序中A在前B在后）
2. 这两个加载指令间，另一个核心对相同地址进行了存储操作
3. 如果加载指令B在A之前执行（乱序执行），可能导致B未看到其他核心的存储结果，而A却看到了
4. 这种情况违反了内存一致性模型，称为load-load违例

多核环境下的load-load违例有一个显著特征：当前DCache一定会收到L2 cache发来的Probe请求，使得DCache主动释放掉这个数据副本。这时DCache会通知LoadQueue，将相同地址的已经完成访存的加载指令做一个release标记。

### 3.2 加载指令查询

当加载指令执行到流水线的s2阶段时，需要查询是否存在与之有顺序约束的早期加载指令：

```scala
for (i <- 0 until LoadPipelineWidth) {
  val req = io.query(i).req
  val resp = io.query(i).resp
  
  when (req.valid) {
    // 获取查询信息
    val addr = req.bits.paddr
    val mask = req.bits.mask
    val robIdx = req.bits.robIdx
    
    // 检查是否存在RAR依赖
    val matchVec = VecInit((0 until RarQueueSize).map(j => {
      val validEntry = allocated(j)
      val addrMatch = (paddr(j) & ~(7.U)) === (addr & ~(7.U))
      val maskOverlap = (mask & mask(j)).orR
      
      // 关键判断：当前指令在程序顺序上晚于队列中的指令，
      // 且队列中的指令已被标记为release
      val needFlush = robIdx.needFlush(robIdx(j))
      val isReleased = released(j)
      
      validEntry && addrMatch && maskOverlap && needFlush && isReleased
    }))
    
    // 生成响应
    resp.valid := req.valid
    resp.bits.conflict := matchVec.asUInt.orR
    resp.bits.conflictAddr := PriorityMux(matchVec, paddr)
  }
}
```

### 3.3 Release标记处理

LoadQueueRAR中的加载指令被标记为release有四种情况：

1. **missQueue模块的replace_req**：在mainpipe流水线的s3栈发起release释放dcache块
2. **probeQueue模块的probe_req**：在mainpipe流水线的s3栈发起release释放dcache块
3. **atomicsUnit模块的请求**：在mainpipe流水线的s3栈发生miss时需要释放dcache块
4. **非缓存(nc)指令**：如果入队请求是nc指令，在入队时就被标记为release

```scala
// 处理缓存释放事件
when (io.release.valid) {
  val releaseAddr = io.release.bits.paddr
  
  // 检查所有已记录的加载指令
  for (i <- 0 until RarQueueSize) {
    val addrMatch = (paddr(i) & ~(lineBytesOffset.U)) === (releaseAddr & ~(lineBytesOffset.U))
    
    // 当加载地址匹配被释放的缓存行时，该加载标记为released
    when (allocated(i) && addrMatch) {
      released(i) := true.B
    }
  }
}
```

## 4. 队列管理机制

### 4.1 入队操作

当加载指令执行到流水线s2阶段时，判断是否满足入队条件。如果在当前加载指令之前有未完成的加载指令，且当前指令没有被flush时，当前加载可以入队：

```scala
// 记录加载指令信息
for (i <- 0 until LoadPipelineWidth) {
  val ld = io.query(i)
  
  // 判断是否需要入队
  val needEnqueue = ld.req.valid && !ld.req.bits.robIdx.needFlush(io.redirect.bits)
  
  when (needEnqueue && io.canAllocate(i)) {
    val idx = io.allocateSlot(i)
    
    // 记录加载信息
    allocated(idx) := true.B
    uop(idx) := ld.req.bits.uop
    paddr(idx) := ld.req.bits.paddr(PAddrBits-1, PAddrBits-16) // 压缩的16位物理地址
    mask(idx) := ld.req.bits.mask
    robIdx(idx) := ld.req.bits.robIdx
    
    // 如果是nc指令，直接标记为released
    released(idx) := ld.req.bits.isUncache
  }
}

// 更新入队指针
val enqNum = PopCount(io.doAllocate)
enqPtrExt := enqPtrExt + enqNum
```

### 4.2 出队操作

LoadQueueRAR通过监视LoadQueue的写回指针来实现条目清理：

```scala
// 基于ldWbPtr清理条目
for (i <- 0 until RarQueueSize) {
  // 当指令已提交或被取消时，标记为可清除
  when (allocated(i) && (robIdx(i).needFlush(io.redirect.bits) || isBefore(robIdx(i), io.ldWbPtr))) {
    allocated(i) := false.B
    released(i) := false.B
  }
}

// 更新出队指针
val deqNum = PopCount(deqMask)
deqPtrExt := deqPtrExt + deqNum
```

## 5. 具体示例：多核环境下的RAR违例

为了更好地理解LoadQueueRAR的工作机制，下面详细说明一个多核环境下RAR违例检测的场景。

### 场景设置

假设有两个核心，在当前核心有以下加载指令序列：
1. `LD x1, [0x1000]` (robIdx=10, 较老的指令)
2. `LD x2, [0x1000]` (robIdx=20, 较新的指令)

但由于乱序执行，指令2先于指令1执行。同时，另一个核心在两者执行之间对地址0x1000执行了存储操作。

### 第1步：指令2先执行

1. 指令2在流水线s2阶段查询RAR依赖：
   ```
   io.query(0).req.valid = true
   io.query(0).req.bits.paddr = 0x1000
   io.query(0).req.bits.mask = 0xFF
   io.query(0).req.bits.robIdx = 20
   ```

2. 此时LoadQueueRAR没有相关条目，没有检测到违例：
   ```
   io.query(0).resp.bits.conflict = false
   ```

3. 指令2被记录到LoadQueueRAR：
   ```
   idx = 分配的条目索引
   allocated(idx) = true
   paddr(idx) = 0x1000的压缩地址
   mask(idx) = 0xFF
   robIdx(idx) = 20
   released(idx) = false (尚未释放)
   ```

### 第2步：其他核心执行存储操作

另一个核心对地址0x1000执行存储操作，触发缓存一致性机制：

1. L2 cache向当前核心发送Probe请求
2. DCache接收到请求，释放包含0x1000的缓存行
3. DCache通知LoadQueueRAR：
   ```
   io.release.valid = true
   io.release.bits.paddr = 0x1000所在的缓存行地址
   ```

4. LoadQueueRAR标记相关条目为released：
   ```
   // 对于包含指令2的条目idx
   val addrMatch = (paddr(idx) & ~(lineBytesOffset.U)) === (releaseAddr & ~(lineBytesOffset.U))
   when (allocated(idx) && addrMatch) {
     released(idx) = true
   }
   ```

### 第3步：指令1后执行

1. 指令1在流水线s2阶段查询RAR依赖：
   ```
   io.query(0).req.valid = true
   io.query(0).req.bits.paddr = 0x1000
   io.query(0).req.bits.mask = 0xFF
   io.query(0).req.bits.robIdx = 10
   ```

2. LoadQueueRAR检查队列中的条目：
   ```
   // 对于包含指令2的条目idx
   val validEntry = allocated(idx)  // true
   val addrMatch = (paddr(idx) & ~(7.U)) === (0x1000压缩地址 & ~(7.U))  // true
   val maskOverlap = (0xFF & mask(idx)).orR  // true
   
   // 关键判断：指令2(robIdx=20)在程序顺序上晚于指令1(robIdx=10)
   val needFlush = 10.needFlush(20)  // true，这里指的是如果flush robIdx=10，则需要同时flush robIdx=20
   val isReleased = released(idx)  // true，已被标记为released
   
   // 检测结果
   matchVec(idx) = true
   ```

3. 检测到违例并生成响应：
   ```
   io.query(0).resp.bits.conflict = true
   io.query(0).resp.bits.conflictAddr = 0x1000
   ```

4. 流水线接收到响应，需要将违例的加载指令1及其后的所有指令刷新，确保正确性。

## 6. 接口时序

### 6.1 LoadQueueRAR请求入队时序

1. 当`io.query(i).req.valid`和`io.query(i).req.ready`都为高时，表示握手成功
2. 如果`needEnqueue`和`io.canAllocate(i)`都为高，则将`io.doAllocate(i)`置为高
3. `io.allocateSlot(i)`提供接收入队的条目索引
4. 该条目写入相关信息

### 6.2 load-load违例检查时序

1. 第一拍：查询请求握手成功，执行条件匹配生成`matchVec`掩码
2. 第二拍：将`io.query(i).resp.valid`置为高，给出响应
3. 如果`io.query(i).resp.valid`和`io.query(i).resp.bits.conflict`都为高，表示发生RAR违例

## 7. 性能监控与分析

```scala
// 队列使用情况监控
val validCount = distanceBetween(enqPtrExt, deqPtrExt)
io.validCount := validCount

// 队列满状态监控
val allowEnqueue = validCount <= (RarQueueSize - LoadPipelineWidth).U
io.lqFull := !allowEnqueue

// 冲突和重放监控
XSPerfAccumulate("rar_conflict", io.query.map(_.resp.bits.conflict && _.resp.valid).reduce(_||_))
XSPerfAccumulate("release_events", io.release.valid)

// 队列性能监控
QueuePerf(RarQueueSize, validCount, !allowEnqueue)
```

## 8. 总结与应用

LoadQueueRAR模块实现了XiangShan处理器中多核环境下内存顺序一致性保障的关键机制：

1. **多核RAR违例检测**：识别不同核心间交互导致的加载-加载顺序违例
2. **缓存一致性支持**：处理缓存一致性事件对已执行加载指令的影响
3. **精确恢复机制**：在检测到违例时提供精确的回滚信息
4. **高效实现**：通过压缩地址和优化的检测算法实现高性能

在现代多核处理器中，LoadQueueRAR是确保内存一致性的关键组件，它与LoadQueueRAW共同构成了完整的内存依赖检测系统，在保证程序正确性的同时尽可能提供高性能。
