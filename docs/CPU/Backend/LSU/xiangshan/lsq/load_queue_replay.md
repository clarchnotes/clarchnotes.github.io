
# LoadQueueReplay 模块文档

## 1. 模块概述

LoadQueueReplay 是 XiangShan 处理器 LoadQueue 系统中的关键组件，负责存储和管理需要重放的加载指令。它处理各种原因导致的重放需求，如缓存未命中、TLB 未命中、内存依赖冲突等，并在适当条件满足时安排这些指令重新执行[^1]。

## 2. 存储信息

LoadQueueReplay 存储以下关键信息[^1]：

| 字段                 | 描述                                       |
| ------------------ | ---------------------------------------- |
| allocated          | 是否已经被分配，也代表是否该项是否有效                      |
| scheduled          | 是否已经被调度，代表该项已经被选出，已经或即将被发送至LoadUnit进行重发  |
| uop                | load指令执行包括的uop信息                         |
| vecReplay          | 向量load指令相关信息                             |
| vaddrModule        | Load指令的虚拟地址                              |
| cause              | 某load replay queue项对应load指令重发的原因         |
| blocking           | Load指令正在被阻塞                              |
| strict             | 访存依赖预测器判断指令是否需要等待它之前的所有store指令执行完毕进入调度阶段 |
| blockSqIdx         | 与load指令有相关性的store指令的StoreQueue Index     |
| missMSHRId         | load指令的dcache miss请求接受ID                 |
| tlbHintId          | load指令的tlb miss请求接受ID                    |
| replacementUpdated | DCcahe的替换算法是否已经更新                        |
| replayCarry        | DCache的路预测器预测信息                          |
| missDbUpdated      | ChiselDB中Miss相关情况更新                      |
| dataInLastBeatReg  | Load指令需要的数据在两笔回填请求的最后一笔                  |


## 3. 重放原因与优先级

LoadQueueReplay 模块处理多种重放原因，按优先级从高到低排列[^1]：

```scala
val C_MA  = 0  // 存储-加载预测违例
val C_TM  = 1  // TLB未命中
val C_FF  = 2  // 存储-加载转发(store数据未准备好)
val C_DR  = 3  // DCache拒绝(无法分配MSHR)
val C_DM  = 4  // DCache未命中
val C_WF  = 5  // 路预测器预测错误
val C_BC  = 6  // DCache bank冲突
val C_RAR = 7  // 读后读队列空间不足
val C_RAW = 8  // 读后写队列空间不足
val C_NK  = 9  // LoadUnit监测到store-to-load-forwarding违例
val C_MF  = 10 // LoadMisalignBuffer空间不足
```

优先级设计确保了更关键的重放原因优先处理，避免潜在的死锁问题。

## 4. 核心特性

### 4.1 特性1：乱序分配

LoadQueueReplay 采用 Freelist 进行队列空闲管理[^1]：

- Freelist 的大小为 LoadQueueReplay 的项数
- 分配宽度为 Load 的宽度（LoadUnit 的数量）
- 释放宽度为 4

分配流程：

- 当 LoadUnit S3 传入一条 load 请求后，首先判断是否需要入队
- 如果不需要重发、发生异常或因 redirect 被冲刷，则不需要入队
- 为每个 LoadUnit 从空闲项中选出一个项索引
- 根据索引将指令信息填入对应的索引项中

回收流程：

- 成功重发或被刷新的 load 指令占用的项需要回收
- 通过位图 FreeMask 保存正在释放的项
- 每个周期 Freelist 最多回收 4 项

```scala
// 分配逻辑示例
when (needEnqueue(w) && enq.ready) {
  freeList.io.doAllocate(w) := !enq.bits.isLoadReplay
  allocated(enqIndex) := true.B
  scheduled(enqIndex) := false.B
  uop(enqIndex) := enq.bits.uop
  // 其他字段设置...
}

// 回收逻辑示例
when (enq.valid && enq.bits.isLoadReplay) {
  when (!needReplay(w) || hasExceptions(w)) {
    allocated(schedIndex) := false.B
    freeMaskVec(schedIndex) := true.B
  }
}
```

### 4.2 特性2：唤醒机制

不同阻塞条件有不同的唤醒条件[^1]：

| 重放原因 | 唤醒条件 |
|---------|----------|
| C_MA | 如果strict=1，需等待load指令之前所有store指令地址计算完成；否则只需等待blockSqIdx对应store指令地址计算完成 |
| C_TM | 如果TLB无空间处理miss请求，标记为可重发等待调度；否则等待TLB返回tlbHintId匹配的hint信号 |
| C_FF | 等待blockSqIdx对应store指令数据准备完成 |
| C_DR | 可直接标记为可重发状态，等待调度 |
| C_DM | 等待与missMSHRId匹配的L2 Hint信号 |
| C_WF | 可直接标记为可重发状态，等待调度 |
| C_BC | 可直接标记为可重发状态，等待调度 |
| C_RAR | 等待LoadQueueRAR有空闲空间或该条指令是最老的load指令 |
| C_RAW | 等待LoadQueueRAW有空闲空间或该条load指令在之前store指令地址都计算完成 |
| C_MF | 等待LoadMisalignBuffer有空闲空间 |

这些唤醒条件决定了指令何时从阻塞状态转为可重放状态：

```scala
// 更新阻塞条件示例
(0 until LoadQueueReplaySize).map(i => {
  // 对于C_MA原因
  when (cause(i)(LoadReplayCauses.C_MA)) {
    blocking(i) := Mux(stAddrDeqVec(i), false.B, blocking(i))
  }
  
  // 对于C_TM原因
  when (cause(i)(LoadReplayCauses.C_TM)) {
    blocking(i) := Mux(io.tlb_hint.resp.valid &&
                   (io.tlb_hint.resp.bits.replay_all ||
                   io.tlb_hint.resp.bits.id === tlbHintId(i)), false.B, blocking(i))
  }
  
  // 其他原因的处理...
})
```

### 4.3 特性3：选择调度

LoadQueueReplay 采用三种选择调度方式[^1]：

1. **根据入队年龄**：
	- 使用3个年龄矩阵(每一个Bank对应一个年龄矩阵)记录入队时间
	- 从已准备好可重发的指令中选择入队时间最长的指令

2. **根据Load指令的年龄**：
	- 根据LqPtr判断靠近最老的load指令进行重发
	- 判断宽度为OldestSelectStride=4

3. **数据相关优先调度**：
	- 首先调度因L2 Hint唤醒的重发（L2 Cache回填前2-3拍提前给出唤醒信号）
	- 如不存在L2 Hint情况，将重放原因分为高低优先级：
    	- 高优先级：dcache缺失(C_DM)或转发失败(C_FF)导致的重放
    	- 低优先级：其他重放原因

```scala
// 重放优先级选择逻辑
val s0_remPriorityReplaySelVec = VecInit((0 until LoadPipelineWidth).map(rem => {
  Mux(s0_remHintSelValidVec(rem), s0_remLoadHintSelMask(rem),
    Mux(ParallelORR(s0_remLoadHigherPriorityReplaySelMask(rem)), 
        s0_remLoadHigherPriorityReplaySelMask(rem), 
        s0_remLoadLowerPriorityReplaySelMask(rem)))
}))
```

## 5. 数据流分析

### 5.1 入队流程

入队时序有两种情况：重发入队和非重发入队[^1]。

非重发入队流程：
1. LoadUnit 执行指令发现需要重放（如缓存未命中）
2. 通过 `io.enq` 接口发送信息到 LoadQueueReplay
3. LoadQueueReplay 分配一个条目并记录重放信息：

```scala
when (needEnqueue(w) && enq.ready) {
  // 分配新条目
  allocated(enqIndex) := true.B
  scheduled(enqIndex) := false.B
  uop(enqIndex) := enq.bits.uop
  
  // 设置重放原因和状态
  cause(enqIndex) := replayInfo.cause.asUInt
  blocking(enqIndex) := true.B  // 默认阻塞直到条件满足
  
  // 根据不同重放原因设置特定状态
  // ...
}
```

重发入队流程：
1. 已重放但仍需再次重放的指令返回到 LoadQueueReplay
2. 不重新分配条目，而是更新现有条目的状态：

```scala
when (enq.valid && enq.bits.isLoadReplay) {
  when (!needReplay(w) || hasExceptions(w)) {
    // 如果不再需要重放或有异常，释放重放条目
    allocated(schedIndex) := false.B
    freeMaskVec(schedIndex) := true.B
  } .otherwise {
    // 否则，重置调度状态，准备下一次重放
    scheduled(schedIndex) := false.B
  }
}
```

### 5.2 重放流水线

重放过程分为三个阶段[^1]：

1. **S0阶段**：选择需要重放的条目
	- 优先处理L2 Hint唤醒的条目
	- 然后是高优先级原因（C_DM和C_FF）
	- 最后是其他原因的重放条目
	- 可能还会考虑入队年龄和指令年龄

2. **S1阶段**：读取虚拟地址并标记调度状态
   ```scala
   for (i <- 0 until LoadPipelineWidth) {
     // 更新调度状态
     when (s0_can_go && s0_oldestSel(i).valid && s0_oldestSelIndexOH(j)) {
       scheduled(j) := true.B
     }
     
     // 读取虚拟地址
     vaddrModule.io.ren(i) := s1_oldestSel(i).valid && s1_can_go(i)
     vaddrModule.io.raddr(i) := s1_oldestSel(i).bits
   }
   ```

3. **S2阶段**：发送重放请求到加载单元
   ```scala
   replay_req(i).valid := s2_oldestSel(i).valid
   replay_req(i).bits.uop := s2_replayUop
   replay_req(i).bits.vaddr := vaddrModule.io.rdata(i)
   replay_req(i).bits.isLoadReplay := true.B
   
   // 连接到输出接口
   io.replay(i) <> replay_req(i)
   ```

另外，LoadQueueReplay 还实现了重放冷却机制，避免频繁重放导致资源浪费：

```scala
// 冷却机制实现
when (lastReplay(i) && io.replay(i).fire) {
  coldCounter(i) := coldCounter(i) + 1.U
} .elsewhen (coldDownNow(i)) {
  coldCounter(i) := coldCounter(i) + 1.U
} .otherwise {
  coldCounter(i) := 0.U
}
```

### 5.3 LoadQueueReplay 与 LoadQueue 的关系

LoadQueueReplay 与 LoadQueue 是相互配合但状态独立的两个模块：

1. **独立的条目管理**：
	- LoadQueueReplay 有自己独立的条目，不直接修改 LoadQueue 中的条目状态
	- 每个需要重放的加载指令在 LoadQueueReplay 中有独立的追踪条目
	- LoadQueue 中的原始条目保持其状态，直到最终执行成功或被取消

2. **数据流向**：
   ```
   LoadQueue -> 加载单元 -> [执行] -> 
     如需重放: -> LoadQueueReplay -> 加载单元 -> [再次执行] -> 
       如成功: -> LoadQueue (通过 io.ldu.ldin 接口)
       如仍需重放: -> 返回 LoadQueueReplay
   ```

重放后的数据无论是正常执行还是重放执行，其最终结果都通过相同的接口（`io.ldu.ldin`）返回给 LoadQueue。这意味着：

1. 重放指令使用与原始指令相同的 LQ 索引（lqIdx）
2. LoadQueue 不区分数据来自正常执行还是重放执行
3. 只有当指令成功执行（不再需要重放）时，LoadQueue 才会将条目标记为已提交

```scala
// 加载单元重新执行重放指令后，结果通过 io.ldu.ldin 接口返回给 LoadQueue
for(i <- 0 until LoadPipelineWidth) {
  io.ldin(i).ready := true.B
  val loadWbIndex = io.ldin(i).bits.uop.lqIdx.value

  when (io.ldin(i).valid) {
    // 如果执行成功且不需要再次重放，更新 LoadQueue 中对应条目的状态
    when (!need_rep && need_valid && !io.ldin(i).bits.isvec) {
      committed(loadWbIndex) := true.B
      // 其他状态更新...
    }
  }
}
```

## 6. 与其他子模块的协作

### 6.1 与 VirtualLoadQueue 的协作

```scala
// LoadQueueReplay 从 VirtualLoadQueue 获取写回指针信息
loadQueueReplay.io.ldWbPtr          <> virtualLoadQueue.io.ldWbPtr
```

LoadQueueReplay 使用 VirtualLoadQueue 提供的写回指针（ldWbPtr）来：
- 确定队列中指令的相对顺序
- 实现基于程序顺序的最旧指令选择（优先选择接近写回指针的指令）
- 解除 RAR/RAW 阻塞条件（判断指令是否已超过写回界限）

### 6.2 与 LoadQueueRAR/RAW 的协作

```scala
loadQueueReplay.io.rarFull          <> loadQueueRAR.io.lqFull
loadQueueReplay.io.rawFull          <> loadQueueRAW.io.lqFull
```

LoadQueueReplay 监控 RAR 和 RAW 队列的状态：
- 如果队列满，阻塞对应原因的重放
- 当队列有空间时，解除阻塞并允许重放
- 这确保了依赖冲突检测模块不会被大量重放指令压垮

## 7. 典型数据流场景示例

### 缓存未命中重放的完整数据流：

1. 加载指令在 VirtualLoadQueue 分配条目（lqIdx = 10）
2. 加载单元执行指令，发现缓存未命中，设置重放标志
3. 执行结果通过 `io.ldu.ldin` 返回，同时：
	- VirtualLoadQueue 保持原始条目状态不变
	- 执行结果同时发送到 LoadQueueReplay 的 `io.enq` 接口
4. LoadQueueReplay 分配条目（例如 idx = 5），记录:
	- 原始 uop（包含 lqIdx = 10）
	- 原因 = C_DM（缓存未命中）
	- 虚拟地址和 MSHR ID
5. 收到 L2 提示或缓存行返回时：
	- LoadQueueReplay 解除条目（idx = 5）的阻塞
	- 通过 `io.replay` 接口发送重放请求到加载单元
6. 加载单元重新执行指令：
	- 使用相同的 lqIdx = 10
	- 这次从缓存或 MSHR 获取数据
1. 重放结果通过 `io.ldu.ldin` 返回：
	- 不需要继续重放时，LoadQueue 更新 lqIdx = 10 的条目状态（committed = true）
	- LoadQueueReplay 释放条目 idx = 5
	- 最终数据通过 LoadQueue 的输出接口传递给处理器后端

## 8. 总结

LoadQueueReplay 是 XiangShan 处理器内存系统的关键组件，负责管理需要重放的加载指令。它通过乱序分配、复杂的唤醒机制和智能的选择调度，高效地处理各种内存访问异常情况。它维护自己独立的条目状态，但与 LoadQueue 及其他子模块紧密协作，形成完整的数据流和控制流。重放后的数据总是通过标准路径返回到 LoadQueue，保持了数据流的一致性，同时确保了程序的正确执行。

[^1]: [LoadQueueReplay - 香山开源处理器设计文档](https://docs.xiangshan.cc/projects/design/zh-cn/latest/memblock/LSU/LSQ/LoadQueueReplay/)
