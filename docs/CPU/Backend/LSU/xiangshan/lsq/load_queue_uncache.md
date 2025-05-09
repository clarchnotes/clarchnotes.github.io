
# LoadQueueUncache 模块文档

![](attachments/Pasted%20image%2020250509000613.png)

## 1. 功能描述

LoadQueueUncache 是 XiangShan 处理器 LSQ 系统中的专用组件，负责处理非缓存加载指令，包括内存映射 I/O (MMIO) 和其他非缓存 (NC) 内存区域的访问[^1]。这些特殊访问需要绕过常规缓存系统，通过专用通道直接与外部设备或特殊内存区域交互。

### 1.1 特性 1：入队逻辑

LoadQueueUncache 实现了两阶段流水线入队处理[^1]：

1. **第一阶段(s1)**：根据 ROB 索引对请求进行排序，确保程序顺序。
2. **第二阶段(s2)**：判断请求是否满足入队条件：
	- 未被重定向刷新
	- 无异常
	- 无需重放
	- 是 MMIO 或 NC 请求

符合条件的请求通过 FreeList 分配空闲条目，写入相应的 UncacheEntry。当 Buffer 满且无法分配空间时，会产生回滚请求要求重新执行最老的无法入队请求。

### 1.2 特性 2：出队逻辑

出队逻辑处理已完成的非缓存请求并将结果返回给 LoadUnit[^1]：

- 当 UncacheEntry 完成请求处理、被 redirect 刷新或接收到外部错误响应时，该条目会出队并释放 FreeList 中的标志
- 返回给 LoadUnit 的请求在第一拍选出，第二拍返回
- MMIO 和 NC 有固定的回写端口分配：
	- MMIO 只返回到 LoadUnit 2
	- NC 可返回到 LoadUnit 1/2，通过 entry id 与端口数的余数确定

### 1.3 特性 3：Uncache 交互逻辑

与 Uncache 模块的交互分为三个关键步骤[^1]：

1. **发送请求(req)**：
	- 选择准备好的请求，发送给 Uncache Buffer
	- 请求中包含源 ID (mid)

2. **接收 ID 响应(idResp)**：
	- Uncache Buffer 接收请求后返回 idResp
	- 包含源 ID (mid) 和为该请求分配的目标 ID (sid)
	- LoadQueueUncache 通过 mid 找到对应条目并存储 sid

3. **接收结果响应(resp)**：
	- Uncache Buffer 完成访问后返回结果
	- 通过 sid 找到所有相关条目并传递结果
	- 一个 sid 可能对应多个条目（因为 Uncache Buffer 的合并特性）

## 2. 系统架构

LoadQueueUncache 采用entry buffer设计，包含以下主要组件[^1]：

```scala
val entries = Seq.tabulate(LoadUncacheBufferSize)(i => Module(new UncacheEntry(i)))

val freeList = Module(new FreeList(
  size = LoadUncacheBufferSize,
  allocWidth = LoadPipelineWidth,
  freeWidth = 4,
  enablePreAlloc = true,
  moduleName = "LoadQueueUncache freelist"
))
```

整体架构特点：
- 多个 UncacheEntry 实例并行处理请求
- FreeList 管理条目分配和回收
- 专用接口处理 MMIO 和 NC 请求的分发与回收
- 状态机跟踪每个请求的生命周期

## 3. UncacheEntry 模块

UncacheEntry 是 LoadQueueUncache 的核心组件，负责处理单个非缓存加载请求的完整生命周期[^1]。

### 3.1 特性 1：生命周期及状态机

UncacheEntry 使用状态机跟踪请求处理：

```scala
val s_idle :: s_req :: s_resp :: s_wait :: Nil = Enum(4)
val uncacheState = RegInit(s_idle)
```

- **s_idle**：默认状态，表示无请求或请求尚不具备发送条件
- **s_req**：具备发送条件，等待被选中并由中间寄存器接收
- **s_resp**：请求已被接收，等待 Uncache Buffer 返回访问结果
- **s_wait**：已收到访问结果，等待被选中并由 LoadUnit 接收

状态转换触发条件：
- **s_idle → s_req**：对 MMIO，指令到达 ROB 头部；对 NC，req_valid 有效
- **s_req → s_resp**：请求被 LoadQueueUncache 中间寄存器接收
- **s_resp → s_wait**：收到 Uncache Buffer 返回的访问结果
- **s_wait → s_idle**：写回成功或被刷新

### 3.2 特性 2：redirect 刷新逻辑

当接收到流水线 redirect 信号时，UncacheEntry 会判断是否需要刷新[^1]：

```scala
val needFlushReg = RegInit(false.B)
val needFlush = req_valid && req.uop.robIdx.needFlush(io.redirect)
val flush = WireInit(false.B)

when(flush){
  needFlushReg := false.B
}.elsewhen(needFlush){
  needFlushReg := true.B
}
```

刷新处理有两种情况：
1. **直接刷新**：处于 s_idle 状态时可立即刷新
2. **延迟刷新**：已发出 uncache 请求时，需等待接收到响应后才能刷新，以保证 uncache 请求和响应的完整对应

### 3.3 特性 3：异常情况

UncacheEntry 处理的主要异常情况是总线返回的错误[^1]：

```scala
val nderr = RegInit(false.B)  // 硬件错误标志

when (io.uncache.resp.fire) {
  uncacheData := io.uncache.resp.bits.data
  nderr := io.uncache.resp.bits.nderr
}

// 设置异常向量
io.mmioOut.bits.uop.exceptionVec(hardwareError) := nderr
io.exception.valid := writeback
io.exception.bits := req
io.exception.bits.uop.exceptionVec(loadAccessFault) := nderr
```

当总线返回 corrupt 或 denied 时：
1. 设置硬件错误标志 (nderr)
2. 在写回阶段将异常信息添加到异常向量
3. 通过异常接口报告给处理器

## 4. 详细数据流分析

### 4.1 入队数据流 (LoadUnit → LoadQueueUncache)

LoadQueueUncache 的入队数据流是一个多阶段流水线处理过程，具体如下[^1]：

```scala
// s1: 对输入请求排序
val s1_sortedVec = HwSort(VecInit(io.req.map { case x => DataWithPtr(x.valid, x.bits, x.bits.uop.robIdx) }))
val s1_req = VecInit(s1_sortedVec.map(_.bits))
val s1_valid = VecInit(s1_sortedVec.map(_.valid))

// s2: 检查请求有效性
val s2_req = (0 until LoadPipelineWidth).map(i => {RegEnable(s1_req(i), s1_valid(i))})
val s2_valid = (0 until LoadPipelineWidth).map(i => {
  RegNext(s1_valid(i)) &&
  !s2_req(i).uop.robIdx.needFlush(RegNext(io.redirect)) &&
  !s2_req(i).uop.robIdx.needFlush(io.redirect)
})
val s2_has_exception = s2_req.map(x => ExceptionNO.selectByFu(x.uop.exceptionVec, LduCfg).asUInt.orR)
val s2_need_replay = s2_req.map(_.rep_info.need_rep)

// 确定是否需要入队
for (w <- 0 until LoadPipelineWidth) {
  s2_enqueue(w) := s2_valid(w) && !s2_has_exception(w) && !s2_need_replay(w) && (s2_req(w).mmio || s2_req(w).nc)
}
```

数据流步骤：
1. **初始输入**：
	- 来自各个 LoadUnit 的请求 (`io.req`) 包含指令信息、地址、MMIO/NC 标志等
	- 每个请求都有效位 (`valid`) 和请求数据 (`bits`)

2. **s1 阶段排序**：
	- 对输入请求基于 ROB 索引排序，确保处理按程序顺序进行
	- 排序结果写入 `s1_sortedVec`，提取有效位 (`s1_valid`) 和数据 (`s1_req`)

3. **s1→s2 寄存**：
	- 有效请求被寄存到 s2 阶段寄存器 (`s2_req`)
	- 有效位考虑可能的重定向，生成 `s2_valid`

4. **s2 阶段筛选**：
	- 检查异常状态 (`s2_has_exception`)
	- 检查重放需求 (`s2_need_replay`)
	- 确认是 MMIO 或 NC 请求
	- 生成最终入队需求 (`s2_enqueue`)

5. **空间分配**：
   ```scala
   for (w <- 0 until LoadPipelineWidth) {
     val offset = PopCount(s2_enqueue.take(w))
     s2_enqValidVec(w) := s2_enqueue(w) && freeList.io.canAllocate(offset)
     s2_enqIndexVec(w) := freeList.io.allocateSlot(offset)
   }
   
   // freeList真正分配
   for (w <- 0 until LoadPipelineWidth) {
     freeList.io.doAllocate(w) := s2_enqValidVec(w)
   }
   ```
	- 计算每个请求的偏移量，确定 FreeList 分配的条目索引
	- 只有当 FreeList 能够分配空间时，请求才能有效入队

6. **写入 UncacheEntry**：
   ```scala
   entries.zipWithIndex.foreach {
     case (e, i) =>
       // 入队
       for (w <- 0 until LoadPipelineWidth) {
         when (s2_enqValidVec(w) && (i.U === s2_enqIndexVec(w))) {
           e.io.req.valid := true.B
           e.io.req.bits := s2_req(w)
         }
       }
   }
   ```
	- 根据分配的索引，将请求写入对应的 UncacheEntry
	- 设置 UncacheEntry 的请求有效位和数据

### 4.2 UncacheEntry 内部数据流

每个 UncacheEntry 内部维护请求的完整生命周期，数据在状态机控制下流动[^1]：

```scala
// 关键寄存器
val req_valid = RegInit(false.B)    // 条目是否有效
val req = Reg(new LqWriteBundle)    // 请求内容
val slaveAccept = RegInit(false.B)  // 是否被 Uncache 接受
val slaveId = Reg(UInt(UncacheBufferIndexWidth.W)) // Uncache 分配的 ID
val uncacheState = RegInit(s_idle)  // 状态机状态
val uncacheData = Reg(io.uncache.resp.bits.data.cloneType) // 响应数据
val nderr = RegInit(false.B)        // 硬件错误标志
```

数据流转详细过程：

1. **请求接收与存储**：
   ```scala
   when (io.req.valid) {
     req_valid := true.B
     slaveAccept := false.B
     req := io.req.bits
     nderr := false.B
   }
   ```
	- 接收请求时，设置 `req_valid` 并存储请求内容
	- 初始化错误标志和接受状态

2. **状态转换与处理**：
   ```scala
   switch (uncacheState) {
     is (s_idle) {
       when (needFlush) {
         uncacheState := s_idle
         flush := true.B
       }.elsewhen (canSendReq) {
         uncacheState := s_req
       }
     }
     
     is (s_req) {
       when(needFlush) {
         uncacheState := s_idle
         flush := true.B
       }.elsewhen(io.uncache.req.fire) {
         uncacheState := s_resp
       }
     }
     
     is (s_resp) {
       when (io.uncache.resp.fire) {
         when (needFlush || needFlushReg) {
           uncacheState := s_idle
           flush := true.B
         }.otherwise {
           uncacheState := s_wait
         }
       }
     }
     
     is (s_wait) {
       when (needFlush || writeback) {
         uncacheState := s_idle
         flush := true.B
       }
     }
   }
   ```
	- `canSendReq` 触发条件:
		- 对 MMIO: 指令必须到达 ROB 头部 (`pendingld && req.uop.robIdx === pendingPtr`)
		- 对 NC: 只需 `req_valid` 为真

3. **ID 响应处理**：
   ```scala
   when(slaveAck) {
     slaveAccept := true.B
     slaveId := io.uncache.idResp.bits.sid
   }
   ```
	- 收到 Uncache 的 ID 响应时，记录 `slaveId` 并设置 `slaveAccept`

4. **数据响应处理**：
   ```scala
   when (io.uncache.resp.fire) {
     uncacheData := io.uncache.resp.bits.data
     nderr := io.uncache.resp.bits.nderr
   }
   ```
	- 接收 Uncache 返回的数据并存储
	- 记录可能的硬件错误状态

5. **结果处理与格式化**：
   ```scala
   val selUop = req.uop
   val func = selUop.fuOpType
   val raddr = req.paddr
   val rdataSel = LookupTree(raddr(2, 0), List(
     "b000".U -> uncacheData(63,  0),
     // ... 其他字节偏移选择
   ))
   val rdataPartialLoad = rdataHelper(selUop, rdataSel)
   ```
	- 根据地址的低3位选择数据字节
	- 根据指令类型处理数据（符号扩展、字节选择等）

### 4.3 Uncache 交互数据流

与 Uncache 模块的交互是 LoadQueueUncache 的核心数据流，分为请求发送和响应处理两部分[^1]：

1. **请求通道选择**：
   ```scala
   val uncacheReq = Wire(DecoupledIO(io.uncache.req.bits.cloneType))
   val mmioSelect = entries.map(e => e.io.mmioSelect).reduce(_ || _)
   val mmioReq = Wire(DecoupledIO(io.uncache.req.bits.cloneType))
   val ncReqArb = Module(new RRArbiterInit(io.uncache.req.bits.cloneType, LoadUncacheBufferSize))
   
   when(mmioSelect) {
     uncacheReq <> mmioReq
   }.otherwise {
     uncacheReq <> ncReqArb.io.out
   }
   
   // 连接到输出
   AddPipelineReg(uncacheReq, io.uncache.req, false.B)
   ```
	- 优先处理 MMIO 请求，然后处理 NC 请求
	- 使用轮询仲裁器 (RRArbiter) 选择 NC 请求
	- 请求通过流水线寄存器发送到 Uncache

2. **Entry 请求生成**：
   ```scala
   io.uncache.req.valid := uncacheState === s_req && !needFlush
   io.uncache.req.bits.cmd := MemoryOpConstants.M_XRD
   io.uncache.req.bits.addr := req.paddr
   io.uncache.req.bits.vaddr := req.vaddr
   io.uncache.req.bits.mask := Mux(req.paddr(3), req.mask(15, 8), req.mask(7, 0))
   io.uncache.req.bits.id := entryIndex.U
   io.uncache.req.bits.nc := req.nc
   ```
	- 当 UncacheEntry 处于 s_req 状态且未被刷新时，生成有效请求
	- 包含物理地址、虚拟地址、掩码、请求 ID 等信息
	- 区分 MMIO (nc=false) 和 NC (nc=true)

3. **ID 响应路由**：
   ```scala
   // 对每个 Entry
   when(i.U === io.uncache.idResp.bits.mid) {
     e.io.uncache.idResp <> io.uncache.idResp
   }
   ```
	- 根据响应中的 mid (源 ID) 将 idResp 路由到对应的 UncacheEntry

4. **数据响应路由**：
   ```scala
   // 对每个 Entry
   when (e.io.slaveId.valid && e.io.slaveId.bits === io.uncache.resp.bits.id) {
     e.io.uncache.resp <> io.uncache.resp
   }
   ```
	- 根据响应中的 id 与 Entry 存储的 slaveId 比较
	- 将数据响应路由到匹配的 UncacheEntry

### 4.4 结果回写数据流 (LoadQueueUncache → LoadUnit)

完成处理后，结果需要回写到 LoadUnit，这一过程区分了 MMIO 和 NC 两种路径[^1]：

1. **MMIO 结果准备**：
   ```scala
   io.mmioOut.valid := (uncacheState === s_wait) && !needFlush
   io.mmioOut.bits.uop := selUop
   io.mmioOut.bits.uop.lqIdx := req.uop.lqIdx
   io.mmioOut.bits.uop.exceptionVec(hardwareError) := nderr
   io.mmioOut.bits.data := rdataPartialLoad
   io.mmioOut.bits.debug.isMMIO := true.B
   io.mmioOut.bits.debug.paddr := req.paddr
   io.mmioOut.bits.debug.vaddr := req.vaddr
   io.mmioRawData.lqData := uncacheData
   io.mmioRawData.uop := req.uop
   io.mmioRawData.addrOffset := req.paddr
   ```
	- 当 UncacheEntry 处于 s_wait 状态且未被刷新时，准备回写数据
	- 包含处理后的数据、uop 信息、地址信息等
	- 设置异常状态（如有）

2. **NC 结果准备**：
   ```scala
   io.ncOut.valid := (uncacheState === s_wait) && !needFlush
   io.ncOut.bits.uop := selUop
   io.ncOut.bits.uop.lqIdx := req.uop.lqIdx
   io.ncOut.bits.uop.exceptionVec(hardwareError) := nderr
   io.ncOut.bits.data := rdataPartialLoad
   io.ncOut.bits.paddr := req.paddr
   io.ncOut.bits.vaddr := req.vaddr
   io.ncOut.bits.nc := true.B
   io.ncOut.bits.mask := Mux(req.paddr(3), req.mask(15, 8), req.mask(7, 0))
   ```
	- 与 MMIO 类似，但路径和部分字段有所不同
	- 明确标记 nc=true

3. **输出端口分配**：
   ```scala
   // 对 MMIO
   AddPipelineReg(mmioOut, io.mmioOut(UncacheWBPort), false.B)
   io.mmioRawData(UncacheWBPort) := RegEnable(mmioRawData, mmioOut.fire)

   // 对 NC（针对多端口）
   (0 until NC_WB_MOD).map { w =>
     val (idx, ncOutValid) = PriorityEncoderWithFlag(ncOutValidVecRem(w))
     val port = NCWBPorts(w)
     when((i.U === idx) && ncOutValid) {
       ncOut(port).valid := ncOutValid
       ncOut(port).bits := e.io.ncOut.bits
       e.io.ncOut.ready := ncOut(port).ready
     }
   }
   
   // 流水线注册
   (0 until LoadPipelineWidth).foreach { i => 
     AddPipelineReg(ncOut(i), io.ncOut(i), false.B) 
   }
   ```
	- MMIO 固定使用 UncacheWBPort (=2) 端口
	- NC 可使用 NCWBPorts 中定义的多个端口
	- 通过优先编码器选择要回写的条目
	- 输出经过流水线寄存器，确保时序稳定

4. **完成后释放**：
   ```scala
   when ((e.io.mmioSelect && e.io.mmioOut.fire) || e.io.ncOut.fire || e.io.flush) {
     freeMaskVec(i) := true.B
   }
   
   freeList.io.free := freeMaskVec.asUInt
   ```
	- 当回写成功或条目被刷新时，标记为可释放
	- 将释放掩码传递给 FreeList，完成资源回收

### 4.5 资源满回滚处理详细流程

当 LoadQueueUncache 资源不足时，完整的回滚生成流程[^1]：

1. **识别受阻请求**：
   ```scala
   val reqNeedCheck = VecInit((0 until LoadPipelineWidth).map(w =>
     s2_enqueue(w) && !s2_enqValidVec(w)
   ))
   ```
	- 找出所有需要入队但无法分配空间的请求

2. **构建回滚请求**：
   ```scala
   val allRedirect = (0 until LoadPipelineWidth).map(i => {
     val redirect = Wire(Valid(new Redirect))
     redirect.valid := reqNeedCheck(i)
     redirect.bits.robIdx := reqSelUops(i).robIdx
     redirect.bits.ftqIdx := reqSelUops(i).ftqPtr
     redirect.bits.ftqOffset := reqSelUops(i).ftqOffset
     redirect.bits.level := RedirectLevel.flush
     redirect.bits.cfiUpdate.target := reqSelUops(i).pc
     // 其他字段...
     redirect
   })
   ```
	- 为每个受阻请求创建潜在的回滚请求
	- 包含必要的重定向信息：ROB 索引、FTQ 索引和偏移等

3. **选择最老请求**：
	- 通过比较 ROB 索引找出最老的请求
	- 生成一个 one-hot 向量，表示应选择哪个请求
	- 使用 Mux1H 选择最终的回滚请求

4. **验证与输出**：
   ```scala
   io.rollback.valid := GatedValidRegNext(oldestRedirect.valid &&
                       !oldestRedirect.bits.robIdx.needFlush(io.redirect) &&
                       !oldestRedirect.bits.robIdx.needFlush(lastCycleRedirect) &&
                       !oldestRedirect.bits.robIdx.needFlush(lastLastCycleRedirect))
   io.rollback.bits := RegEnable(oldestRedirect.bits, oldestRedirect.valid)
   ```
	- 保存最近两个周期的重定向信息
	- 确保选中的请求未被这些重定向刷新
	- 将验证通过的回滚请求在下一周期输出

### 4.6 完整数据流示例：MMIO 加载指令

以一个 MMIO 加载指令为例，完整数据流如下：

1. **加载单元检测与发送**：
	- 加载单元执行 `LD x5, 0x10000000` 指令，地址映射到设备寄存器
	- 检测到 MMIO 属性，设置 `mmio=true, nc=false`
	- 请求通过 `io.req(w)` 发送到 LoadQueueUncache

2. **LoadQueueUncache 入队处理**：
	- s1 阶段对请求按 ROB 索引排序
	- s2 阶段验证有效性，确认为 MMIO 请求
	- 从 FreeList 分配条目号（例如 3）
	- 将请求写入 UncacheEntry(3)

3. **等待 ROB 头部**：
	- UncacheEntry(3) 处于 s_idle 状态，等待指令到达 ROB 头部
	- 当条件满足时，状态变为 s_req

4. **请求发送到 Uncache**：
	- UncacheEntry(3) 被选中发送请求
	- 通过流水线寄存器发送到 Uncache，包含 mid=3

5. **接收 ID 响应**：
	- Uncache 返回 ID 响应，包含 sid=7
	- UncacheEntry(3) 存储 slaveId 并进入 s_resp 状态

6. **等待数据响应**：
	- Uncache 执行总线访问，获取设备寄存器数据
	- 返回数据响应，UncacheEntry(3) 接收数据并进入 s_wait 状态

7. **结果处理与回写**：
	- UncacheEntry(3) 准备回写数据
	- 数据通过 `io.mmioOut(UncacheWBPort)` 发送到 LoadUnit

8. **完成与释放**：
	- 回写成功后，标记 UncacheEntry(3) 为可释放
	- FreeList 回收条目，UncacheEntry(3) 返回 s_idle 状态

## 5. 接口时序

### 5.1 入队接口时序实例

入队时序展示了请求分配条目的过程[^1]：
- 请求经过排序后按顺序分配空闲条目
- 当队列满时，无法分配条目的请求会触发回滚
- 回滚请求在排序后的下两个周期产生

### 5.2 出队接口时序实例

出队时序展示了结果回写的过程[^1]：
- 第一个周期选出写回项
- 更新 freeList 并寄存一个周期
- 下一个周期将结果写回 LoadUnit

### 5.3 uncache 接口时序实例

uncache 交互时序分为两种情况[^1]：

1. **无未完成请求**：
	- 每段只能发出一个请求，直到收到回复
	- 请求发出后，Uncache 下一周期返回 idResp
	- 经过总线访问后，最终收到访问结果

2. **有未完成请求**：
	- 可以连续发出多个请求
	- 请求可能会因为 Uncache 满而被中间寄存器暂存
	- 多个请求可能会在不同时间收到回复

## 6. 与系统其他模块的交互

### 6.1 与 LoadQueue 系统交互

LoadQueueUncache 作为 LoadQueue 的子模块，与其他组件协同工作[^1]：

```scala
// 在 LoadQueue 中连接 LoadQueueUncache
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

### 6.2 与 ROB 协作

MMIO 请求需要与 ROB 协调，确保按程序顺序精确执行[^1]：

```scala
val pendingld = GatedValidRegNext(io.rob.pendingMMIOld)
val pendingPtr = GatedRegNext(io.rob.pendingPtr)
val canSendReq = req_valid && !needFlush && Mux(
  req.nc, true.B,
  pendingld && req.uop.robIdx === pendingPtr
)
```

关键交互点：
- MMIO 请求等待指令到达 ROB 头部
- NC 请求无需等待 ROB 头部
- 向 ROB 报告 MMIO 状态
- 处理可能的异常

### 6.3 与 Uncache 模块交互

与 Uncache 模块的交互包括三个关键接口[^1]：

1. **req 接口**：发送请求到
2. **idResp 接口**：接收 Uncache 分配的 ID
3. **resp 接口**：接收 Uncache 访问结果

## 7. 性能监控

LoadQueueUncache 实现了丰富的性能计数器以监控系统行为[^1]：

```scala
XSPerfAccumulate("mmio_uncache_req", io.uncache.req.fire && !io.uncache.req.bits.nc)
XSPerfAccumulate("mmio_writeback_success", io.mmioOut(0).fire)
XSPerfAccumulate("mmio_writeback_blocked", io.mmioOut(0).valid && !io.mmioOut(0).ready)
XSPerfAccumulate("nc_uncache_req", io.uncache.req.fire && io.uncache.req.bits.nc)
XSPerfAccumulate("nc_writeback_success", io.ncOut(0).fire)
XSPerfAccumulate("nc_writeback_blocked", io.ncOut(0).valid && !io.ncOut(0).ready)
XSPerfAccumulate("uncache_full_rollback", io.rollback.valid)
```

这些计数器提供了重要的性能指标：
- MMIO 和 NC 请求数量
- 回写成功率和阻塞情况
- 因资源不足导致的回滚次数

## 8. 总结

LoadQueueUncache 是 XiangShan 处理器 LSQ 系统中处理非缓存内存访问的专用组件。它通过对 MMIO 和 NC 访问的精确管理，确保了这些特殊内存访问能够按照程序要求正确执行。核心特性包括：

1. **分级流水入队**：排序和条件检查确保请求按程序顺序处理
2. **MMIO/NC 区分**：MMIO 等待 ROB 头部，NC 可立即处理
3. **完整状态机**：四状态跟踪请求生命周期
4. **精确异常处理**：捕获并报告总线错误
5. **资源不足回滚**：确保系统在资源受限时不会死锁

在乱序处理器中，LoadQueueUncache 通过复杂的数据流处理机制，确保了非缓存内存访问的正确性和顺序性，为系统与外部设备的交互提供了可靠的支持。

[^1]: [LoadQueueUncache - 香山开源处理器设计文档](https://docs.xiangshan.cc/projects/design/zh-cn/latest/memblock/LSU/LSQ/LoadQueueUncache/)
