
# LoadQueue

## 1. 模块概述

`LoadQueue.scala` 实现了一个综合性的加载队列管理器，作为XiangShan处理器LSQ系统的中央协调组件。它集成了多个专用子模块，共同处理加载指令的内存依赖检查、数据处理和异常处理等功能。

### 1.1 核心功能

- 协调多个专用子模块，形成完整的加载指令处理系统
- 检测并处理内存依赖冲突(RAW、RAR违例)
- 管理加载指令的重放机制
- 处理未缓存加载和异常情况
- 维护加载指令的状态和数据流

### 1.2 模块定义

```scala
class LoadQueue(implicit p: Parameters) extends XSModule
  with HasDCacheParameters
  with HasCircularQueuePtrHelper
  with HasLoadHelper
  with HasPerfEvents {
  // 模块实现
}
```

## 2. 系统架构

LoadQueue采用模块化设计，通过集成多个专用子模块形成完整的加载队列系统：

```scala
val loadQueueRAR = Module(new LoadQueueRAR)      // 读后读违例检查
val loadQueueRAW = Module(new LoadQueueRAW)      // 读后写违例检查
val loadQueueReplay = Module(new LoadQueueReplay) // 重放队列
val virtualLoadQueue = Module(new VirtualLoadQueue) // 控制状态
val exceptionBuffer = Module(new LqExceptionBuffer) // 异常缓冲
val uncacheBuffer = Module(new LoadQueueUncache)  // 未缓存加载处理
```

这种设计将不同的功能分离到独立模块中，实现了高度的模块化和专业化，同时通过明确的接口进行协同工作。

## 3. 数据结构与接口

### 3.1 IO 接口

```scala
val io = IO(new Bundle() {
  // 控制接口
  val redirect = Flipped(Valid(new Redirect))
  
  // LSU接口
  val enq = new LqEnqIO
  val ldu = new Bundle() {
    val stld_nuke_query = Vec(LoadPipelineWidth, Flipped(new LoadNukeQueryIO)) // 从load_s2
    val ldld_nuke_query = Vec(LoadPipelineWidth, Flipped(new LoadNukeQueryIO)) // 从load_s2
    val ldin = Vec(LoadPipelineWidth, Flipped(Decoupled(new LqWriteBundle)))   // 从load_s3
  }
  
  // 存储单元接口
  val sta = new Bundle() {
    val storeAddrIn = Vec(StorePipelineWidth, Flipped(Valid(new LsPipelineBundle))) // 从store_s1
  }
  val std = new Bundle() {
    val storeDataIn = Vec(StorePipelineWidth, Flipped(Valid(new MemExuOutput)))     // 从store_s0
  }
  
  // 存储队列接口
  val sq = new Bundle() {
    val stAddrReadySqPtr = Input(new SqPtr)
    val stAddrReadyVec   = Input(Vec(StoreQueueSize, Bool()))
    val stDataReadySqPtr = Input(new SqPtr)
    val stDataReadyVec   = Input(Vec(StoreQueueSize, Bool()))
    val stIssuePtr       = Input(new SqPtr)
    val sqEmpty          = Input(Bool())
  }
  
  // 输出接口
  val ldout = Vec(LoadPipelineWidth, DecoupledIO(new MemExuOutput))
  val ld_raw_data = Vec(LoadPipelineWidth, Output(new LoadDataFromLQBundle))
  val ncOut = Vec(LoadPipelineWidth, DecoupledIO(new LsPipelineBundle))
  val replay = Vec(LoadPipelineWidth, Decoupled(new LsPipelineBundle))
  
  // 缓存接口
  val tl_d_channel = Input(new DcacheToLduForwardIO)
  val release = Flipped(Valid(new Release))
  
  // 回滚接口
  val nuke_rollback = Vec(StorePipelineWidth, Output(Valid(new Redirect)))
  val nack_rollback = Vec(1, Output(Valid(new Redirect)))
  
  // ROB接口
  val rob = Flipped(new RobLsqIO)
  
  // 特殊处理接口
  val uncache = new UncacheWordIO
  val exceptionAddr = new ExceptionAddrIO
  
  // 状态接口
  val lqFull = Output(Bool())
  val lqDeq = Output(UInt(log2Up(CommitWidth + 1).W))
  val lqCancelCnt = Output(UInt(log2Up(VirtualLoadQueueSize+1).W))
  val lq_rep_full = Output(Bool())
  val lqEmpty = Output(Bool())
  val lqDeqPtr = Output(new LqPtr)
  val rarValidCount = Output(UInt())
})
```

## 4. 子模块连接与数据流

LoadQueue的主要功能是将各个子模块连接起来，形成完整的数据流和控制流。

### 4.1 VirtualLoadQueue 连接

VirtualLoadQueue作为控制状态管理者，负责跟踪加载指令状态：

```scala
virtualLoadQueue.io.redirect      <> io.redirect
virtualLoadQueue.io.enq           <> io.enq
virtualLoadQueue.io.ldin          <> io.ldu.ldin
virtualLoadQueue.io.lqFull        <> io.lqFull
virtualLoadQueue.io.lqDeq         <> io.lqDeq
virtualLoadQueue.io.lqCancelCnt   <> io.lqCancelCnt
virtualLoadQueue.io.lqEmpty       <> io.lqEmpty
virtualLoadQueue.io.ldWbPtr       <> io.lqDeqPtr
```

### 4.2 LoadQueueRAR 连接

LoadQueueRAR负责检测读后读依赖冲突：

```scala
loadQueueRAR.io.redirect  <> io.redirect
loadQueueRAR.io.release   <> io.release
loadQueueRAR.io.ldWbPtr   <> virtualLoadQueue.io.ldWbPtr
loadQueueRAR.io.validCount<> io.rarValidCount

for (w <- 0 until LoadPipelineWidth) {
  loadQueueRAR.io.query(w).req    <> io.ldu.ldld_nuke_query(w).req
  loadQueueRAR.io.query(w).resp   <> io.ldu.ldld_nuke_query(w).resp
  loadQueueRAR.io.query(w).revoke := io.ldu.ldld_nuke_query(w).revoke
}
```

### 4.3 LoadQueueRAW 连接

LoadQueueRAW负责检测写后读依赖冲突：

```scala
loadQueueRAW.io.redirect         <> io.redirect
loadQueueRAW.io.storeIn          <> io.sta.storeAddrIn
loadQueueRAW.io.stAddrReadySqPtr <> io.sq.stAddrReadySqPtr
loadQueueRAW.io.stIssuePtr       <> io.sq.stIssuePtr

for (w <- 0 until LoadPipelineWidth) {
  loadQueueRAW.io.query(w).req    <> io.ldu.stld_nuke_query(w).req
  loadQueueRAW.io.query(w).resp   <> io.ldu.stld_nuke_query(w).resp
  loadQueueRAW.io.query(w).revoke := io.ldu.stld_nuke_query(w).revoke
}
```

### 4.4 异常处理连接

异常缓冲器处理加载指令执行过程中可能出现的异常：

```scala
exceptionBuffer.io.redirect <> io.redirect

for (i <- 0 until LoadPipelineWidth) {
  exceptionBuffer.io.req(i).valid := io.ldu.ldin(i).valid
  exceptionBuffer.io.req(i).bits := io.ldu.ldin(i).bits
}

io.exceptionAddr <> exceptionBuffer.io.exceptionAddr
```

### 4.5 LoadQueueReplay 连接

LoadQueueReplay负责管理需要重放的加载指令：

```scala
loadQueueReplay.io.redirect         <> io.redirect
loadQueueReplay.io.enq              <> io.ldu.ldin
loadQueueReplay.io.storeAddrIn      <> io.sta.storeAddrIn
loadQueueReplay.io.storeDataIn      <> io.std.storeDataIn
loadQueueReplay.io.replay           <> io.replay
loadQueueReplay.io.tl_d_channel     <> io.tl_d_channel
loadQueueReplay.io.stAddrReadySqPtr <> io.sq.stAddrReadySqPtr
loadQueueReplay.io.stAddrReadyVec   <> io.sq.stAddrReadyVec
loadQueueReplay.io.stDataReadySqPtr <> io.sq.stDataReadySqPtr
loadQueueReplay.io.stDataReadyVec   <> io.sq.stDataReadyVec
loadQueueReplay.io.sqEmpty          <> io.sq.sqEmpty
loadQueueReplay.io.lqFull           <> io.lq_rep_full
loadQueueReplay.io.ldWbPtr          <> virtualLoadQueue.io.ldWbPtr
loadQueueReplay.io.rarFull          <> loadQueueRAR.io.lqFull
loadQueueReplay.io.rawFull          <> loadQueueRAW.io.lqFull
```

## 5. 加载指令处理流程

### 5.1 加载指令入队

1. 分发阶段将加载指令发送到LoadQueue的`enq`接口
2. VirtualLoadQueue分配条目并更新状态
3. 返回分配结果到分发单元

### 5.2 加载地址生成

1. 加载单元在S1阶段计算加载地址
2. 通过`stld_nuke_query`和`ldld_nuke_query`接口检查RAW和RAR冲突
3. LoadQueueRAW和LoadQueueRAR分别处理这些查询请求

### 5.3 内存访问

1. 加载单元在S2阶段访问数据缓存
2. 对于命中的加载，准备数据返回
3. 对于未命中的加载，准备进入重放机制

### 5.4 加载完成

1. 加载单元在S3阶段通过`ldin`接口向LoadQueue发送结果
2. 结果同时分发给多个子模块：
	- VirtualLoadQueue更新指令状态
	- LoadQueueReplay处理可能的重放
	- 异常缓冲器记录可能的异常

### 5.5 加载重放

对于需要重放的加载指令(如缓存未命中)：
1. LoadQueueReplay记录重放信息
2. 当条件满足时(如缓存行返回)，通过`replay`接口发送重放请求
3. 加载单元重新执行这些指令

### 5.6 内存依赖冲突处理

1. 如果检测到RAW冲突：
	- LoadQueueRAW生成回滚信号
	- 通过`nuke_rollback`接口发送到ROB
	- 处理器从正确点恢复执行

2. 如果检测到RAR冲突：
	- LoadQueueRAR生成适当的响应
	- 可能导致指令重排序或重放

## 6. 未缓存加载处理

对于访问未缓存内存区域(如I/O设备)的加载指令：

```scala
uncacheBuffer.io.redirect <> io.redirect
uncacheBuffer.io.mmioOut <> io.ldout
uncacheBuffer.io.ncOut <> io.ncOut
uncacheBuffer.io.mmioRawData <> io.ld_raw_data
uncacheBuffer.io.rob <> io.rob
uncacheBuffer.io.uncache <> io.uncache

for ((buff, w) <- uncacheBuffer.io.req.zipWithIndex) {
  val ldinBits = io.ldu.ldin(w).bits
  buff.valid := io.ldu.ldin(w).valid && !ldinBits.nc_with_data
  buff.bits := ldinBits
}

io.nack_rollback(0) := uncacheBuffer.io.rollback
```

1. 识别未缓存访问请求
2. 通过专用接口处理这些请求
3. 处理可能的访问失败或异常情况

## 7. 标量加载指令处理流程示例

通过一个完整示例详细说明标量加载指令在各子模块间的流动过程。

### 初始状态

假设处理器正在执行一条加载指令: `LD x5, 0(x6)`

### 第1步: 指令分发阶段

1. 分发单元将指令发送到LoadQueue:
   ```
   io.enq.req(0).valid = true
   io.enq.req(0).bits = 加载指令信息
   ```

2. VirtualLoadQueue分配一个条目:
   ```
   allocated(idx) = true
   robIdx(idx) = 指令的ROB索引
   committed(idx) = false
   ```

3. 返回分配结果:
   ```
   io.enq.resp(0) = 分配的队列索引
   ```

### 第2步: 地址生成和冲突检查

1. 加载单元计算地址后查询依赖冲突:
   ```
   io.ldu.stld_nuke_query(0).req.valid = true
   io.ldu.stld_nuke_query(0).req.bits.addr = 0x1000
   io.ldu.stld_nuke_query(0).req.bits.mask = 0xFF
   ```

2. LoadQueueRAW检查是否存在写后读冲突:
	- 扫描地址重叠的存储指令
	- 检查这些存储指令是否在当前加载之前

3. 加载单元同时查询读后读冲突:
   ```
   io.ldu.ldld_nuke_query(0).req.valid = true
   io.ldu.ldld_nuke_query(0).req.bits = 同上
   ```

4. LoadQueueRAR检查可能的顺序违例

### 第3步: 内存访问

1. 如果没有冲突，加载单元访问数据缓存
2. 假设这是一次缓存命中，数据立即可用

### 第4步: 加载完成和状态更新

1. 加载单元将结果发送给LoadQueue:
   ```
   io.ldu.ldin(0).valid = true
   io.ldu.ldin(0).bits.uop = 微操作信息
   io.ldu.ldin(0).bits.data = 0xABCDEF01
   io.ldu.ldin(0).bits.rep_info.need_rep = false
   ```

2. 结果同时分发给各子模块:
	- VirtualLoadQueue将条目标记为已提交: `committed(idx) = true`
	- 异常缓冲器检查并记录可能的异常
	- LoadQueueReplay判断不需要重放

3. 加载结果通过LoadQueue的输出接口返回给处理器后端:
   ```
   io.ldout(0).valid = true
   io.ldout(0).bits.data = 处理后的加载数据
   ```

### 第5步: 指令提交

1. 当ROB准备提交该指令时，VirtualLoadQueue将相应条目出队
2. 队列指针更新，该条目可被新指令重用

## 8. 存储指令抵达时的冲突检测过程

当存储指令的地址生成完成后，需要检查与现有加载指令的依赖关系。

### 存储地址生成完成

1. 存储单元将地址信息发送到LoadQueue:
   ```
   io.sta.storeAddrIn(0).valid = true
   io.sta.storeAddrIn(0).bits.addr = 0x2000
   io.sta.storeAddrIn(0).bits.mask = 0xFF
   ```

2. LoadQueueRAW接收存储地址:
   ```
   loadQueueRAW.io.storeIn <> io.sta.storeAddrIn
   ```

3. LoadQueueRAW执行违例检查:
	- 扫描所有已执行但未提交的加载
	- 检查地址是否与新存储指令重叠
	- 检查加载是否应该在该存储之后执行

4. 如果检测到违例，生成回滚信号:
   ```
   io.nuke_rollback(0).valid = true
   io.nuke_rollback(0).bits.robIdx = 违例加载的ROB索引
   ```

## 9. 重放机制示例

对于需要重放的加载指令(如缓存未命中)，处理过程如下:

### 第1步: 标记为需要重放

1. 加载单元在结果中标记重放需求:
   ```
   io.ldu.ldin(0).valid = true
   io.ldu.ldin(0).bits.rep_info.need_rep = true
   io.ldu.ldin(0).bits.rep_info.rep_type = ReSelectNew
   ```

2. LoadQueueReplay记录重放信息:
	- 存储加载指令的地址、掩码和其他必要信息
	- 记录重放类型和原因

### 第2步: 等待重放条件满足

1. 对于缓存未命中导致的重放:
	- 监听`tl_d_channel`接口的缓存行返回
	- 检查返回的地址是否与等待重放的加载匹配

2. 对于依赖存储的重放:
	- 监控相关存储指令的状态
	- 当存储数据准备好时触发重放

### 第3步: 发起重放

1. 条件满足时，LoadQueueReplay发送重放请求:
   ```
   io.replay(0).valid = true
   io.replay(0).bits = 原始加载指令信息(可能包含转发数据)
   ```

2. 加载单元重新执行该指令:
	- 可能直接使用转发的数据
	- 或重新访问现在已经在缓存中的数据

## 10. 性能监控与调试

LoadQueue模块集成了丰富的性能监控和调试功能：

```scala
// 子模块满状态监控
val full_mask = Cat(loadQueueRAR.io.lqFull, loadQueueRAW.io.lqFull, loadQueueReplay.io.lqFull)
XSPerfAccumulate("full_mask_000", full_mask === 0.U)
XSPerfAccumulate("full_mask_001", full_mask === 1.U)
// ...更多状态计数

// 回滚监控
XSPerfAccumulate("nuke_rollback", io.nuke_rollback.map(_.valid).reduce(_ || _).asUInt)
XSPerfAccumulate("nack_rollabck", io.nack_rollback.map(_.valid).reduce(_ || _).asUInt)

// 综合性能事件收集
val perfEvents = Seq(virtualLoadQueue, loadQueueRAR, loadQueueRAW, loadQueueReplay)
                  .flatMap(_.getPerfEvents) ++ Seq(
  // 其他性能监控点
)
generatePerfEvent()
```

这些监控点可以帮助识别性能瓶颈和潜在问题，特别是对于复杂的违例处理和重放情况。

## 11. 总结与应用

LoadQueue作为XiangShan处理器LSQ系统的中央协调组件，具有以下核心特性：

1. **模块化设计**：将不同功能分离到专用子模块，实现高度模块化
2. **全面的依赖检测**：同时支持RAW和RAR依赖检测
3. **灵活的重放机制**：处理各种需要重放的场景
4. **完整的异常处理**：支持各类加载异常情况
5. **高性能设计**：多通道并行处理和流水线操作

在乱序处理器中，LoadQueue确保了内存访问的一致性和正确性，同时通过积极的推测执行和精确的违例检测，实现了高效的内存访问系统。
