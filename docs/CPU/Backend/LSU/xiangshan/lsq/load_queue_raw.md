
# LoadQueueRAW

## 1. 模块概述

`LoadQueueRAW.scala` 实现了XiangShan处理器中的写后读(RAW: Read-After-Write)依赖检测机制，这是确保乱序处理器中内存操作正确性的关键组件。该模块负责检测加载指令可能违反的存储-加载数据依赖，并在必要时触发流水线回滚。

### 1.1 核心功能

- 检测加载指令与早先存储指令之间的数据依赖
- 高效识别地址重叠的存储-加载操作
- 生成精确的违例信号和回滚请求
- 支持推测执行和原子性保证
- 处理内存一致性模型要求的顺序约束

### 1.2 模块定义

```scala
class LoadQueueRAW(implicit p: Parameters) extends XSModule
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
  
  // 存储指令接口
  val storeIn = Vec(StorePipelineWidth, Flipped(Valid(new LsPipelineBundle)))
  val stAddrReadySqPtr = Input(new SqPtr)
  val stIssuePtr = Input(new SqPtr)
  
  // 查询接口
  val query = Vec(LoadPipelineWidth, new LoadToStoreQueryIO)
  
  // 回滚接口
  val rollback = Vec(StorePipelineWidth, Output(Valid(new Redirect)))
  
  // ROB接口
  val rob = Flipped(new RobLsqIO)
  
  // 状态接口
  val lqFull = Output(Bool())
})
```

### 2.2 内部数据结构

```scala
// 已执行的加载指令记录
val uop = Reg(Vec(RawQueueSize, new MicroOp))
val mask = Reg(Vec(RawQueueSize, UInt(8.W)))
val paddr = Reg(Vec(RawQueueSize, UInt(PAddrBits.W)))
val allocated = RegInit(VecInit(List.fill(RawQueueSize)(false.B)))
val addrvalid = RegInit(VecInit(List.fill(RawQueueSize)(false.B)))
val datavalid = RegInit(VecInit(List.fill(RawQueueSize)(false.B)))

// 队列指针管理
val enqPtrExt = RegInit(0.U.asTypeOf(new RawQueuePtr))
val deqPtrExt = RegInit(0.U.asTypeOf(new RawQueuePtr))
val enqPtr = enqPtrExt.value
val deqPtr = deqPtrExt.value
```

其中，`RawQueuePtr`是一个特殊的循环队列指针类型，用于处理队列的环绕逻辑。

## 3. 依赖检测算法

### 3.1 加载指令查询

加载指令在执行阶段需要查询是否存在与之依赖的存储指令：

```scala
def addrMatch(addr1: UInt, addr2: UInt, mask1: UInt, mask2: UInt): Bool = {
  val overlap = (mask1 & mask2).orR
  val matchAddr = (addr1 & ~0x7.U) === (addr2 & ~0x7.U)
  overlap && matchAddr
}

// 处理查询请求
for (i <- 0 until LoadPipelineWidth) {
  val req = io.query(i).req
  val resp = io.query(i).resp
  
  when (req.valid) {
    // 获取查询信息
    val queryAddr = req.bits.addr
    val queryMask = req.bits.mask
    val queryRobIdx = req.bits.robIdx
    
    // 检查与所有已地址就绪但数据未就绪的存储之间的依赖
    val matchVec = VecInit((0 until StoreQueueSize).map(j => {
      val stReady = stAddrReadyVec(j) && !stDataReadyVec(j)
      val match = addrMatch(queryAddr, stAddr(j), queryMask, stMask(j))
      stReady && match
    }))
    
    // 判断是否有依赖冲突
    resp.bits.conflict := matchVec.asUInt.orR
    resp.bits.conflictAddr := PriorityMux(matchVec, stAddr)
    resp.valid := req.valid
  }
}
```

### 3.2 存储指令地址就绪

当存储指令地址就绪时，需要检查已经执行过的加载指令是否可能违反了内存依赖：

```scala
for (i <- 0 until StorePipelineWidth) {
  val stIn = io.storeIn(i)
  
  when (stIn.valid && !io.redirect.valid) {
    // 获取存储信息
    val stAddr = stIn.bits.vaddr
    val stMask = stIn.bits.mask
    val stRobIdx = stIn.bits.uop.robIdx
    
    // 检查所有已执行的加载指令
    val violationVec = VecInit((0 until RawQueueSize).map(j => {
      val ldValid = allocated(j) && addrvalid(j)
      val ldRobIdx = uop(j).robIdx
      
      // 判断顺序: 加载在该存储之后发射但已经执行
      val ordering = ldRobIdx.needBrFlush(stRobIdx)
      
      // 判断地址重叠
      val match = addrMatch(paddr(j), stAddr, mask(j), stMask)
      
      ldValid && ordering && match
    }))
    
    // 找到最早的违例加载
    val violationIdx = PriorityEncoder(violationVec)
    val hasViolation = violationVec.asUInt.orR
    
    // 生成回滚请求
    when (hasViolation) {
      io.rollback(i).valid := true.B
      io.rollback(i).bits.robIdx := uop(violationIdx).robIdx
      io.rollback(i).bits.ftqIdx := uop(violationIdx).cf.ftqPtr
      io.rollback(i).bits.ftqOffset := uop(violationIdx).cf.ftqOffset
      io.rollback(i).bits.level := RedirectLevel.flush
      io.rollback(i).bits.memPredUpdate := false.B
    }
  }
}
```

## 4. 队列管理机制

LoadQueueRAW的队列管理包括入队操作和多种清理机制，确保队列资源的高效利用。

### 4.1 入队操作

当加载指令执行时，其信息被记录到LoadQueueRAW中：

```scala
// 记录加载指令信息
for (i <- 0 until LoadPipelineWidth) {
  val ld = io.query(i)
  
  when (ld.req.valid && ld.req.bits.isFirstIssue && !ld.resp.bits.conflict) {
    val idx = enqPtr + PopCount(ld.req.bits.isFirstIssue.take(i))
    
    // 记录加载信息
    uop(idx) := ld.req.bits.uop
    paddr(idx) := ld.req.bits.addr
    mask(idx) := ld.req.bits.mask
    allocated(idx) := true.B
    addrvalid(idx) := true.B
    
    // 更新指针
    enqPtrExt := enqPtrExt + PopCount(ld.req.bits.isFirstIssue)
  }
}
```

### 4.2 条目清理机制

LoadQueueRAW中的条目清理有三种主要途径：

#### 4.2.1 正常提交清理

对于没有冲突的加载指令，它们在ROB中正常提交时被清理：

```scala
// 识别已提交的加载指令
val commitMask = WireInit(0.U(RawQueueSize.W))

// 遍历所有ROB提交的指令
for (i <- 0 until CommitWidth) {
  when (io.rob.commits(i).valid && io.rob.commits(i).bits.isLoad) {
    val robIdx = io.rob.commits(i).bits.uop.robIdx
    
    // 在队列中查找匹配的条目
    for (j <- 0 until RawQueueSize) {
      when (allocated(j) && uop(j).robIdx === robIdx) {
        commitMask(j) := true.B
      }
    }
  }
}

// 清理已提交的条目
for (i <- 0 until RawQueueSize) {
  when (commitMask(i)) {
    allocated(i) := false.B
    addrvalid(i) := false.B
  }
}
```

#### 4.2.2 重定向清理

当处理器发生重定向时（如分支预测错误），需要清理错误路径上的指令：

```scala
// 处理重定向
val cancelMask = WireInit(0.U(RawQueueSize.W))
when (io.redirect.valid) {
  // 标记需要取消的条目
  for (i <- 0 until RawQueueSize) {
    when (allocated(i) && uop(i).robIdx.needFlush(io.redirect.bits)) {
      cancelMask(i) := true.B
    }
  }
  
  // 恢复入队指针
  val cancelCnt = PopCount(cancelMask)
  enqPtrExt := enqPtrExt - cancelCnt
}
```

#### 4.2.3 违例回滚清理

当检测到违例并触发回滚时，相关条目会在下一个重定向周期被清理。

### 4.3 出队指针更新

基于提交和取消的清理操作，更新出队指针：

```scala
// 合并提交和取消掩码
val clearMask = commitMask | cancelMask

// 计算清理数量并更新出队指针
val deqNum = PopCount(clearMask)
deqPtrExt := deqPtrExt + deqNum
```

### 4.4 清理优化机制

LoadQueueRAW实现了多种优化机制来提高清理效率：

#### 4.4.1 批量处理

支持每周期批量处理多个提交指令：

```scala
// 支持多宽度提交
val commitMask = WireInit(0.U(RawQueueSize.W))
for (i <- 0 until CommitWidth) {
  // 处理每个提交通道
}

// 一次性清理所有匹配条目
val commitNum = PopCount(commitMask)
```

#### 4.4.2 安全清理控制

确保不会过早清理可能仍需要的条目：

```scala
// 确保指令已经结束使用才清理
val safeToCommit = WireInit(VecInit(Seq.fill(RawQueueSize)(false.B)))

for (i <- 0 until RawQueueSize) {
  // 只有当指令完全完成所有检查后才标记安全提交
  safeToCommit(i) := allocated(i) && datavalid(i)
}

// 修改提交逻辑，确保安全
for (i <- 0 until RawQueueSize) {
  when (commitMask(i) && safeToCommit(i)) {
    allocated(i) := false.B
  }
}
```

## 5. 具体示例：标量加载与存储的依赖处理

### 5.1 违例检测示例

假设处理器中有以下指令序列：
1. `ST [0x1000], x1` (ROB索引: 42)
2. `LD x2, [0x1000]` (ROB索引: 43)

但由于乱序执行，假设加载指令在存储指令计算地址之前就已经执行完成。

#### 第1步：加载指令执行

1. 加载指令在执行阶段发送查询请求：
   ```
   io.query(0).req.valid = true
   io.query(0).req.bits.addr = 0x1000
   io.query(0).req.bits.mask = 0xFF
   io.query(0).req.bits.uop.robIdx = 43
   ```

2. 此时存储指令的地址尚未就绪，因此没有检测到冲突：
   ```
   io.query(0).resp.bits.conflict = false
   ```

3. 加载指令被记录到队列中：
   ```
   uop(enqPtr) = 加载指令uop(robIdx=43)
   paddr(enqPtr) = 0x1000
   mask(enqPtr) = 0xFF
   allocated(enqPtr) = true
   addrvalid(enqPtr) = true
   ```

#### 第2步：存储指令地址生成

稍后，存储指令完成地址计算：

1. 存储地址信息发送到LoadQueueRAW：
   ```
   io.storeIn(0).valid = true
   io.storeIn(0).bits.vaddr = 0x1000
   io.storeIn(0).bits.mask = 0xFF
   io.storeIn(0).bits.uop.robIdx = 42
   ```

2. 检查是否有加载指令违反了与该存储的依赖：
   ```
   // 对于队列中的每个条目
   val ldValid = allocated(j) && addrvalid(j)  // 条目有效
   val ldRobIdx = uop(j).robIdx  // 加载的ROB索引=43
   val stRobIdx = 42  // 存储的ROB索引
   
   // 判断顺序: 43需要在42之后执行，但已经执行了
   val ordering = ldRobIdx.needBrFlush(stRobIdx)  // 返回true
   
   // 地址匹配: 0x1000和0x1000, 掩码都是0xFF
   val match = addrMatch(0x1000, 0x1000, 0xFF, 0xFF)  // 返回true
   
   // 违例检测结果
   violationVec(j) = ldValid && ordering && match  // 返回true
   ```

3. 发现违例并生成回滚请求：
   ```
   io.rollback(0).valid = true
   io.rollback(0).bits.robIdx = 43  // 违例加载的ROB索引
   io.rollback(0).bits.level = RedirectLevel.flush
   ```

### 5.2 无冲突加载的清理示例

假设有一个加载指令：`LD x2, [0x2000]` (ROB索引: 50)，它与前面的存储指令没有地址重叠，因此不存在RAW冲突。

#### 第1步：加载指令执行和记录

1. 加载指令执行并查询潜在冲突：
   ```
   io.query(0).req.valid = true
   io.query(0).req.bits.addr = 0x2000
   io.query(0).req.bits.mask = 0xFF
   io.query(0).req.bits.uop.robIdx = 50
   ```

2. 查询结果表明没有冲突：
   ```
   io.query(0).resp.bits.conflict = false
   ```

3. 加载指令被记录到队列中：
   ```
   uop(enqPtr) = 加载指令uop(robIdx=50)
   paddr(enqPtr) = 0x2000
   mask(enqPtr) = 0xFF
   allocated(enqPtr) = true
   addrvalid(enqPtr) = true
   ```

#### 第2步：指令正常提交

加载指令最终在ROB中正常提交：

1. ROB发送提交信号：
   ```
   io.rob.commits(0).valid = true
   io.rob.commits(0).bits.isLoad = true
   io.rob.commits(0).bits.uop.robIdx = 50
   ```

2. LoadQueueRAW识别匹配的条目：
   ```
   // 遍历队列寻找匹配条目
   for (j <- 0 until RawQueueSize) {
     when (allocated(j) && uop(j).robIdx === 50) {
       commitMask(j) := true.B
     }
   }
   ```

3. 清理已提交的条目：
   ```
   // 假设匹配到索引为k的条目
   when (commitMask(k)) {
     allocated(k) := false.B
     addrvalid(k) := false.B
   }
   ```

4. 更新出队指针：
   ```
   deqPtrExt := deqPtrExt + 1
   ```

## 6. 优化机制

LoadQueueRAW实现了多种优化机制来提高性能和准确度：

### 6.1 多路并行查询

```scala
// 支持多个加载单元并行查询
for (i <- 0 until LoadPipelineWidth) {
  // 查询处理逻辑
}
```

### 6.2 精确冲突地址识别

```scala
// 不仅返回冲突状态，还返回具体的冲突地址
resp.bits.conflictAddr := PriorityMux(matchVec, stAddr)
```

### 6.3 优先级编码选择

```scala
// 对于多个违例，选择最早的一个进行回滚
val violationIdx = PriorityEncoder(violationVec)
```

### 6.4 队列压缩

```scala
// 通过提交和取消优化队列利用率
val deqNum = PopCount(commitMask | cancelMask)
deqPtrExt := deqPtrExt + deqNum
```

## 7. 性能监控与分析

LoadQueueRAW包含丰富的性能监控机制：

```scala
// 冲突和回滚监控
XSPerfAccumulate("raw_conflict", io.query.map(_.resp.bits.conflict && _.resp.valid).reduce(_||_))
XSPerfAccumulate("rollback", io.rollback.map(_.valid).reduce(_||_))

// 清理相关计数
XSPerfAccumulate("commit_clear", PopCount(commitMask))
XSPerfAccumulate("redirect_clear", PopCount(cancelMask))
XSPerfAccumulate("total_clear", PopCount(clearMask))

// 队列利用率监控
val validCount = distanceBetween(enqPtrExt, deqPtrExt)
QueuePerf(RawQueueSize, validCount, !allowEnqueue)
io.lqFull := !allowEnqueue

// 条目寿命监控
val oldestAge = RegInit(VecInit(Seq.fill(RawQueueSize)(0.U(8.W))))
for (i <- 0 until RawQueueSize) {
  when (allocated(i)) {
    oldestAge(i) := oldestAge(i) + 1.U
  } .otherwise {
    oldestAge(i) := 0.U
  }
}
XSPerfAccumulate("max_age", Mux(validCount > 0.U, 
                               oldestAge.fold(0.U)((a, b) => Mux(a > b, a, b)), 
                               0.U))
```

## 8. 实现挑战与解决方案

### 8.1 跨时序依赖检测

**挑战**：乱序执行使得加载指令可能在其依赖的存储地址就绪前就执行。

**解决方案**：
1. 记录所有已执行的加载指令信息
2. 当存储地址就绪时回溯检查可能的违例
3. 一旦发现违例立即触发回滚
4. 通过记录ROB索引确保正确的顺序判断

### 8.2 数据结构高效性

**挑战**：需要高效存储和查询大量加载指令信息。

**解决方案**：
1. 使用适当大小的循环队列数据结构
2. 通过标志位快速识别有效条目
3. 利用优先级编码器快速定位违例条目
4. 并行处理多个查询和存储条目

### 8.3 精确恢复与性能平衡

**挑战**：违例检测需要平衡及时性和误报率。

**解决方案**：
1. 确保地址比较的精确性，减少误报
2. 对于地址部分重叠的访问进行精确的掩码比较
3. 优先处理最早的违例，减少级联回滚
4. 在合适的流水线阶段执行检查以减少延迟

## 9. 总结：完整的条目生命周期

一个加载指令在LoadQueueRAW中完整的生命周期包括：

1. **入队**：执行阶段记录到队列中
2. **冲突检查**：作为被查询对象参与后续存储指令的违例检测
3. **清理**：通过以下三种方式之一被清理
   - **正常提交**：指令在ROB中提交时
   - **重定向**：发生分支预测错误等重定向事件时
   - **违例回滚**：由于该加载自身违例而被回滚时

即使没有发生任何冲突，加载指令在正常执行完毕并提交后，也会通过监听ROB提交信号，被从LoadQueueRAW队列中正常清除，确保队列资源可以被新的加载指令使用。

这种多路径的清理机制和精确的依赖检测，使LoadQueueRAW能够在XiangShan处理器中实现高效的内存一致性保障，平衡了性能和正确性的需求，是乱序执行内存系统的关键组件。
