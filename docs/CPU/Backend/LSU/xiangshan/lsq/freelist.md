# FreeList

![](../frlist.svg)

## 1. 模块概述

`FreeList.scala` 实现了一个高效的资源池管理器，用于跟踪、分配和回收有限数量的资源标识符。该模块是 XiangShan 处理器 LSQ 系统的核心基础设施，为 Load Queue 和 Store Queue 提供资源管理支持。

### 1.1 核心功能

- 高效分配和回收资源 ID
- 支持单周期多宽度并行分配和释放操作
- 维护资源使用状态，防止资源泄漏或重复分配
- 通过循环队列机制实现资源的无限复用

### 1.2 模块定义

```scala
class FreeList(
  size: Int,              // 资源池大小
  allocWidth: Int,        // 单周期可分配的最大资源数量
  freeWidth: Int,         // 单周期可释放的最大资源数量
  enablePreAlloc: Boolean = false,  // 是否启用预分配优化
  moduleName: String = ""  // 模块名称，用于日志
)(implicit p: Parameters) extends XSModule
  with HasCircularQueuePtrHelper
  with HasPerfEvents
```

## 2. 数据结构与接口

### 2.1 IO 接口

```scala
val io = IO(new Bundle() {
  // 分配接口
  val allocateReq = Input(Vec(allocWidth, Bool()))    // 分配请求
  val allocateSlot = Output(Vec(allocWidth, UInt()))  // 分配的资源ID
  val canAllocate = Output(Vec(allocWidth, Bool()))   // 是否可分配
  val doAllocate = Input(Vec(allocWidth, Bool()))     // 确认分配

  // 释放接口
  val free = Input(UInt(size.W))                      // 释放资源位图

  // 状态接口
  val validCount = Output(UInt())                     // 已分配资源数量
  val empty = Output(Bool())                          // 资源池是否为空
})
```

### 2.2 内部数据结构

#### 2.2.1 循环队列指针

```scala
class FreeListPtr extends CircularQueuePtr[FreeListPtr](size)
object FreeListPtr {
  def apply(f: Boolean, v: Int): FreeListPtr = {
    val ptr = Wire(new FreeListPtr)
    ptr.flag := f.B
    ptr.value := v.U
    ptr
  }
}

val headPtr = RegInit(FreeListPtr(false, 0))  // 用于分配资源
val headPtrNext = Wire(new FreeListPtr)       // 分配指针的下一个状态
val tailPtr = RegInit(FreeListPtr(true, 0))   // 用于接收释放资源
val tailPtrNext = Wire(new FreeListPtr)       // 释放指针的下一个状态
```

每个指针包含：

- `value`：0 到 size-1 之间的索引值
- `flag`：布尔标志，用于处理环绕情况

#### 2.2.2 资源存储

```scala
val freeList = RegInit(VecInit(
  Seq.tabulate(size)(i => i.U(log2Up(size).W))
))
```

`freeList`存储可用资源的 ID，初始包含 0 到 size-1 的所有 ID。

#### 2.2.3 释放掩码

```scala
val freeMask = RegInit(0.U(size.W))          // 累积待释放资源掩码
val freeSelMask = Wire(UInt(size.W))         // 本周期实际释放的资源掩码
val freeSelMaskVec = Wire(Vec(freeWidth, UInt(size.W)))  // 每个释放通道的选择掩码
```

## 3. 资源分配算法

### 3.1 核心分配流程

```scala
val doAllocate = io.doAllocate.asUInt.orR    // 是否有有效分配
val numAllocate = PopCount(io.doAllocate)    // 本周期实际分配数量

for (i <- 0 until allocWidth) {
  val offset = PopCount(io.allocateReq.take(i))  // 计算当前位置的偏移量

  if (enablePreAlloc) {
    // 预分配模式：提前计算下一周期的分配结果
    val deqPtr = headPtr + numAllocate + offset
    io.canAllocate(i) := RegEnable(isBefore(deqPtr, tailPtr), enablePreAlloc.B)
    io.allocateSlot(i) := RegEnable(freeList(deqPtr.value), enablePreAlloc.B)
  } else {
    // 普通模式：直接计算当前周期的分配结果
    val deqPtr = headPtr + offset
    io.canAllocate(i) := isBefore(deqPtr, tailPtr)
    io.allocateSlot(i) := freeList(deqPtr.value)
  }
}

// 更新分配指针
headPtrNext := headPtr + numAllocate
headPtr := Mux(doAllocate, headPtrNext, headPtr)
```

关键要点：

1. 计算每个分配位置的偏移量，确保资源连续分配
2. 通过`isBefore`检查资源可用性，考虑循环队列环绕
3. 返回对应位置的资源 ID
4. 根据实际分配数量更新指针

### 3.2 预分配模式（可选）

当`enablePreAlloc=true`时，模块会提前计算下一周期的分配结果，减少关键路径延迟。这主要通过`RegEnable`实现，提前一个周期计算并寄存结果。

## 4. 资源释放算法

资源释放是 FreeList 中最复杂的部分，实现了高效的多通道并行释放机制。

### 4.1 交错分组

```scala
// 按照位置模freeWidth的余数提取位
def getRemBits(input: UInt)(rem: Int): UInt = {
  VecInit((0 until size / freeWidth).map(i => { input(freeWidth * i + rem) })).asUInt
}

// 更新待释放资源掩码
freeMask := (io.free | freeMask) & ~freeSelMask

// 为每个释放通道提取负责的资源位
val remFreeSelMaskVec = VecInit(Seq.tabulate(freeWidth)(rem =>
  getRemBits((freeMask & ~freeSelMask))(rem)))
```

`getRemBits`函数实现了交错分组策略：

- 将资源按照位置模`freeWidth`的余数分配给不同释放通道
- 每个通道只处理其负责的资源子集，避免冲突

### 4.2 资源选择

```scala
// 为每个释放通道选择一个资源
val remFreeSelIndexOHVec = VecInit(Seq.tabulate(freeWidth)(fport => {
  val highIndexOH = PriorityEncoderOH(remFreeSelMaskVec(fport))  // 优先选择高位的1
  val freeIndexOHVec = Wire(Vec(size, Bool()))
  freeIndexOHVec.foreach(e => e := false.B)  // 初始化为全0
  for (i <- 0 until size / freeWidth) {
    freeIndexOHVec(i * freeWidth + fport) := highIndexOH(i)  // 映射回原始位置
  }
  freeIndexOHVec.asUInt
}))
```

每个通道通过优先编码器从其资源子集中选择一个资源，然后将选择结果映射回原始位置。

### 4.3 执行释放

```scala
// 确定哪些通道有有效请求
val freeReq = GatedRegNext(VecInit(remFreeSelMaskVec.map(_.asUInt.orR)))
val freeSlotOH = GatedRegNext(remFreeSelIndexOHVec)
val doFree = freeReq.asUInt.orR  // 是否有任何释放操作

// 执行实际释放
for (i <- 0 until freeWidth) {
  val offset = PopCount(freeReq.take(i))  // 计算当前通道的偏移量
  val enqPtr = tailPtr + offset  // 计算放置位置

  when (freeReq(i)) {
    freeList(enqPtr.value) := OHToUInt(freeSlotOH(i))  // 将资源ID放回freeList
  }

  freeSelMaskVec(i) := Mux(freeReq(i), freeSlotOH(i), 0.U)
}

// 更新释放指针
tailPtrNext := tailPtr + PopCount(freeReq)
tailPtr := Mux(doFree, tailPtrNext, tailPtr)
```

关键步骤：

1. 确定每个通道是否有有效请求
2. 计算偏移量以确保资源紧凑放置
3. 将资源 ID 放回 freeList 相应位置
4. 更新尾指针，反映新增的可用资源

## 5. 状态管理与性能监控

```scala
// 计算可用资源数量
val freeSlotCnt = RegInit(size.U(log2Up(size + 1).W))
freeSlotCnt := distanceBetween(tailPtrNext, headPtrNext)

// 输出状态信号
io.empty := freeSlotCnt === 0.U
io.validCount := size.U - freeSlotCnt

// 性能计数
XSPerfAccumulate("empty", io.empty)
val perfEvents: Seq[(String, UInt)] = Seq(
  ("empty", io.empty)
)
generatePerfEvent()
```

## 6. 正确性验证

```scala
val enableFreeListCheck = false
if (enableFreeListCheck) {
  // 计算有效资源区域掩码
  val differentFlag = tailPtr.flag ^ headPtr.flag
  val headMask = UIntToMask(headPtr.value, size)
  val tailMask = UIntToMask(tailPtr.value, size)
  val validMask1 = Mux(differentFlag, ~tailMask, tailMask ^ headMask)
  val validMask2 = Mux(differentFlag, headMask, 0.U(size.W))
  val validMask = ~(validMask1 | validMask2)

  // 检查重复资源
  for (i <- 0 until size) {
    for (j <- i+1 until size) {
      if (i != j) {
        XSError(validMask(i) && validMask(j) && freeList(i) === freeList(j),
                s"Found same entry in free list! (i=$i j=$j)\n")
      }
    }
  }
}
```

## 7. FreeList 资源释放算法实例分析：`freeWidth=2, size=4`

我将通过一个具体例子详细展示 FreeList 的资源释放算法流程。本例中，我们使用以下参数：

- `size = 4`（资源池大小为 4）
- `freeWidth = 2`（每周期最多并行释放 2 个资源）
- 要释放的资源 ID 为 1 和 3

### 初始状态

假设系统的初始状态为：

- `freeList = [0, 2, x, x]`（x 表示尚未使用的位置）
- `headPtr = {value=2, flag=0}`（下一个要分配的位置）
- `tailPtr = {value=0, flag=0}`（下一个释放资源将放入的位置）
- `freeMask = 0000`（当前无累积的待释放资源）

### 第 1 步：接收释放请求

资源 ID 1 和 3 需要释放，对应的释放位图为：

```
io.free = 1010 (二进制，最右边是位置0)
           │ │
           │ └── 位置1 (资源ID 1)
           └──── 位置3 (资源ID 3)
```

### 第 2 步：更新 freeMask

```scala
freeMask := (io.free | freeMask) & ~freeSelMask
```

计算过程：

- `io.free = 1010`
- `freeMask = 0000`（初始值）
- `freeSelMask = 0000`（初始值，表示本周期尚未选择任何资源）
- 新的`freeMask = (1010 | 0000) & ~0000 = 1010`

结果：`freeMask = 1010`，表示资源 ID 1 和 3 待释放。

### 第 3 步：交错分组

根据`getRemBits`函数将资源按照余数分组：

```
资源位置:    3  2  1  0
freeMask:    1  0  1  0
            -----------
余数(位置%2):  1  0  1  0
            -----------
负责通道:     c1 c0 c1 c0
```

提取各通道负责的位：

- 通道 0 (rem=0) 负责偶数位: `[b2,b0] = [0,0]`
- 通道 1 (rem=1) 负责奇数位: `[b3,b1] = [1,1]`

所以`remFreeSelMaskVec`结果为：

- `remFreeSelMaskVec(0) = 00` (通道 0 无资源可释放)
- `remFreeSelMaskVec(1) = 11` (通道 1 有两个资源可释放)

### 第 4 步：选择要释放的资源

```scala
val remFreeSelIndexOHVec = VecInit(Seq.tabulate(freeWidth)(fport => {
  val highIndexOH = PriorityEncoderOH(remFreeSelMaskVec(fport))
  val freeIndexOHVec = Wire(Vec(size, Bool()))
  freeIndexOHVec.foreach(e => e := false.B)
  for (i <- 0 until size / freeWidth) {
    freeIndexOHVec(i * freeWidth + fport) := highIndexOH(i)
  }
  freeIndexOHVec.asUInt
}))
```

对于每个通道使用优先编码器选择：

- 通道 0：`remFreeSelMaskVec(0) = 00`，无可选资源，`highIndexOH = 00`
- 通道 1：`remFreeSelMaskVec(1) = 11`，优先选择高位，`highIndexOH = 10`（选择了第 1 位，二进制表示中从右往左数的第二个 1）

将选择映射回原始位置：

- 通道 0：无选择，结果为`0000`
- 通道 1：选择了子集中的索引 1，映射到原始位置为`1*2+1 = 3`，结果为`1000`（资源 ID 3）

所以`remFreeSelIndexOHVec`结果为：

- `remFreeSelIndexOHVec(0) = 0000`
- `remFreeSelIndexOHVec(1) = 1000`

### 第 5 步：确定实际释放请求

```scala
val freeReq = GatedRegNext(VecInit(remFreeSelMaskVec.map(_.asUInt.orR)))
val freeSlotOH = GatedRegNext(remFreeSelIndexOHVec)
val doFree = freeReq.asUInt.orR
```

检查每个通道是否有有效请求：

- `freeReq(0) = 00.orR = 0`（通道 0 无请求）
- `freeReq(1) = 11.orR = 1`（通道 1 有请求）

所以`freeReq = 01`，`doFree = true`。

### 第 6 步：执行释放操作

```scala
for (i <- 0 until freeWidth) {
  val offset = PopCount(freeReq.take(i))
  val enqPtr = tailPtr + offset

  when (freeReq(i)) {
    freeList(enqPtr.value) := OHToUInt(freeSlotOH(i))
  }

  freeSelMaskVec(i) := Mux(freeReq(i), freeSlotOH(i), 0.U)
}
```

处理每个通道：

- 通道 0 (i=0)：

	- `offset = 0`（前面没有有效请求）
	- `enqPtr = tailPtr + 0 = 0`
	- `freeReq(0) = 0`，不执行操作
	- `freeSelMaskVec(0) = 0000`

- 通道 1 (i=1)：
	- `offset = 0`（前面通道 0 没有有效请求）
	- `enqPtr = tailPtr + 0 = 0`
	- `freeReq(1) = 1`，执行释放：`freeList(0) = OHToUInt(1000) = 3`
	- `freeSelMaskVec(1) = 1000`

最终`freeSelMask = freeSelMaskVec(0) | freeSelMaskVec(1) = 0000 | 1000 = 1000`

### 第 7 步：更新尾指针

```scala
tailPtrNext := tailPtr + PopCount(freeReq)
tailPtr := Mux(doFree, tailPtrNext, tailPtr)
```

- `PopCount(freeReq) = PopCount(01) = 1`（共有 1 个有效释放请求）
- `tailPtrNext = tailPtr + 1 = 1`
- 由于`doFree = true`，所以`tailPtr`更新为 1

### 第 8 步：更新状态

在下一个周期，系统状态更新为：

- `freeList = [3, 2, x, x]`（释放的资源 ID 3 已放入位置 0）
- `headPtr = {value=2, flag=0}`（保持不变）
- `tailPtr = {value=1, flag=0}`（已更新）
- `freeMask = 0010`（1010 & ~1000，资源 ID 1 仍待释放）

### 下一周期

在接下来的周期，系统会继续处理剩余的释放请求（资源 ID 1）：

1. **freeMask 更新**：仍为 0010
2. **交错分组**：
	- 通道 0: `[b2,b0] = [0,0]` 无资源
	- 通道 1: `[b3,b1] = [0,1]` 有资源 ID 1
3. **选择资源**：
	- 通道 1 选择资源 ID 1
4. **执行释放**：
	- `freeList(1) = 1`
5. **更新尾指针**：
	- `tailPtr`更新为 2

最终状态：

- `freeList = [3, 1, x, x]`
- `headPtr = {value=2, flag=0}`
- `tailPtr = {value=2, flag=0}`
- `freeMask = 0000`（所有释放请求已处理）

### 关键机制总结

这个例子展示了 FreeList 释放算法的核心机制：

1. **交错分组**：按余数将资源分配给不同通道（偶数位给通道 0，奇数位给通道 1）
2. **优先选择**：每个通道内部使用优先编码器选择高位
3. **压缩布置**：根据有效请求计算偏移量，确保资源紧凑放置
4. **独立处理**：每个通道可以独立处理自己负责的资源子集

这种设计能够在保证正确性的同时实现高效的并行资源释放。

## 8. 总结与应用

FreeList 模块实现了一个"循环 ID 管理队列"数据结构，具有以下特点：

1. **高效分配**：O(1)时间复杂度的资源分配
2. **并行释放**：通过交错分组支持多通道无冲突并行释放
3. **循环复用**：使用循环队列机制实现有限资源的无限复用
4. **正确性保证**：通过指针和标志位维护资源状态
5. **性能优化**：可选的预分配功能减少关键路径延迟

在 XiangShan 处理器的 LSQ 系统中，FreeList 为 LoadQueue 和 StoreQueue 提供了基础资源管理功能，是乱序执行核心的关键组件之一。



!!! Warning 
	潜在问题: free的bitmap如果映射到了同一个freeport应该怎么办，理论上一个port一次只能处理一个(PriorityEncoder选出)