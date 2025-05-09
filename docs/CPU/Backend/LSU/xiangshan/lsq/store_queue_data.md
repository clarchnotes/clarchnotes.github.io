# StoreQueueData

## 1. 模块概述

`StoreQueueData.scala` 实现了XiangShan处理器存储队列的数据存储和检索功能，是内存子系统的关键组件。该模块作为StoreQueue的核心数据存储结构，负责管理存储指令的地址、数据和掩码，并提供高效的数据转发机制，支持存储-加载转发功能。

### 1.1 核心功能

- 管理存储指令的地址、数据和掩码信息
- 实现高效的内容寻址匹配(CAM)机制用于地址比较
- 支持字节粒度的数据转发
- 提供并行化的数据读写和比较逻辑
- 支持缓存行级别的操作标记
- 为LoadQueue提供高效的存储-加载数据转发机制

### 1.2 主要子模块

StoreQueueData包含三个主要的子模块：

1. **SQAddrModule**：管理存储指令的地址信息，并提供CAM功能
2. **SQData8Module**：处理8位(1字节)粒度的数据存储和转发
3. **SQDataModule**：作为SQData8Module的包装器，管理完整的数据条目

### 1.3 与StoreQueue和LoadQueue的关系

StoreQueueData在XiangShan的LSQ (Load-Store Queue) 系统中扮演着关键角色：

1. **与StoreQueue的关系**：
	- 作为StoreQueue的核心数据存储组件
	- 由StoreQueue实例化和管理
	- 接收来自StoreQueue的写入和转发控制信号
	- 提供数据给StoreQueue用于写回SBuffer和处理MMIO操作

2. **与LoadQueue的关系**：
	- 通过StoreQueue提供加载-存储转发功能
	- 响应LoadQueue发起的地址匹配查询
	- 为LoadQueue提供潜在的转发数据
	- 协助LoadQueue解决内存依赖问题

## 2. SQAddrModule：地址处理模块

### 2.1 模块定义

```scala
class SQAddrModule(
  dataWidth: Int,            // 地址宽度(通常为PAddrBits)
  numEntries: Int,           // 条目数量(StoreQueueSize)
  numRead: Int,              // 读端口数量 
  numWrite: Int,             // 写端口数量
  numForward: Int            // 转发端口数量
)(implicit p: Parameters) extends XSModule with HasDCacheParameters
```

### 2.2 主要接口

```scala
val io = IO(new Bundle {
  // 同步读取端口
  val raddr = Input(Vec(numRead, UInt(log2Up(numEntries).W)))
  val rdata = Output(Vec(numRead, UInt(dataWidth.W)))
  val rlineflag = Output(Vec(numRead, Bool()))
  
  // 写入端口
  val wen   = Input(Vec(numWrite, Bool()))
  val waddr = Input(Vec(numWrite, UInt(log2Up(numEntries).W)))
  val wdata = Input(Vec(numWrite, UInt(dataWidth.W)))
  val wmask = Input(Vec(numWrite, UInt((VLEN/8).W)))
  val wlineflag = Input(Vec(numWrite, Bool()))
  
  // 地址CAM功能端口
  val forwardMdata = Input(Vec(numForward, UInt(dataWidth.W)))
  val forwardDataMask = Input(Vec(numForward, UInt((VLEN/8).W)))
  val forwardMmask = Output(Vec(numForward, Vec(numEntries, Bool())))
  
  // 调试端口
  val debug_data = Output(Vec(numEntries, UInt(dataWidth.W)))
})
```

### 2.3 内部数据结构

```scala
// 存储每个条目的物理地址
val data = Reg(Vec(numEntries, UInt(dataWidth.W)))

// 存储每个条目的访问掩码
val mask = Reg(Vec(numEntries, UInt((VLEN/8).W)))

// 缓存行匹配标志，用于整行操作
val lineflag = Reg(Vec(numEntries, Bool()))
```

### 2.4 地址匹配逻辑

SQAddrModule实现了关键的地址匹配逻辑，用于确定哪些存储指令的地址与加载指令匹配：

```scala
// 内容寻址匹配(CAM)逻辑
for (i <- 0 until numForward) {
  for (j <- 0 until numEntries) {
    // 缓存行命中判断
    val linehit = io.forwardMdata(i)(dataWidth-1, DCacheLineOffset) === 
                 data(j)(dataWidth-1, DCacheLineOffset)
    
    // 128位(16字节)区域命中判断
    val hit128bit = (io.forwardMdata(i)(DCacheLineOffset-1, DCacheVWordOffset) === 
                   data(j)(DCacheLineOffset-1, DCacheVWordOffset)) &&
                  (!StoreQueueForwardWithMask.B || (mask(j) & io.forwardDataMask(i)).orR)
    
    // 最终匹配结果
    io.forwardMmask(i)(j) := linehit && (hit128bit || lineflag(j))
  }
}
```

这个匹配逻辑考虑了两种情况：
1. 普通命中：要求缓存行地址匹配且16字节区域匹配
2. 整行操作命中：缓存行地址匹配且存储指令标记为整行操作

### 2.5 与LoadQueue的交互

当LoadQueue需要检查潜在的内存依赖时，它会通过StoreQueue向SQAddrModule发送地址查询请求：

1. LoadQueue向StoreQueue发送加载地址和掩码
2. StoreQueue将这些信息转发给SQAddrModule的`forwardMdata`和`forwardDataMask`端口
3. SQAddrModule执行并行CAM操作，生成匹配掩码
4. 匹配结果通过`forwardMmask`返回给StoreQueue
5. StoreQueue结合年龄信息处理这些匹配结果，并控制数据转发

这个交互流程是存储-加载转发机制的第一阶段，确定了哪些存储指令可能需要向加载指令提供数据。

## 3. SQData8Module：字节粒度数据处理

### 3.1 模块定义

```scala
class SQData8Module(
  numEntries: Int,          // 条目数量(StoreQueueSize)
  numRead: Int,             // 读端口数量
  numWrite: Int,            // 写端口数量
  numForward: Int           // 转发端口数量
)(implicit p: Parameters) extends XSModule with HasDCacheParameters with HasCircularQueuePtrHelper
```

### 3.2 数据类型

```scala
// 单字节数据条目
class SQData8Entry(implicit p: Parameters) extends XSBundle {
  val valid = Bool()              // 此字节有效标志
  val data = UInt((XLEN/8).W)     // 字节数据
}
```

### 3.3 接口定义

```scala
val io = IO(new Bundle() {
  // 同步读取端口
  val raddr = Vec(numRead, Input(UInt(log2Up(numEntries).W)))
  val rdata = Vec(numRead, Output(new SQData8Entry))
  
  // 数据写入端口
  val data = new Bundle() {
    val wen   = Vec(numWrite, Input(Bool()))
    val waddr = Vec(numWrite, Input(UInt(log2Up(numEntries).W)))
    val wdata = Vec(numWrite, Input(UInt((XLEN/8).W)))
  }
  
  // 掩码(数据有效位)写入端口
  val mask = new Bundle() {
    val wen   = Vec(numWrite, Input(Bool()))
    val waddr = Vec(numWrite, Input(UInt(log2Up(numEntries).W)))
    val wdata = Vec(numWrite, Input(Bool()))
  }

  // 转发控制和结果端口
  val needForward = Input(Vec(numForward, Vec(2, UInt(numEntries.W))))
  val forwardValidFast = Vec(numForward, Output(Bool()))
  val forwardValid = Vec(numForward, Output(Bool()))
  val forwardData = Vec(numForward, Output(UInt(8.W)))
})
```

### 3.4 多Bank写入设计

SQData8Module采用了多Bank设计，提高写入带宽和并行性：

```scala
// 要求写入Bank数为2的幂次方且大于1
require(isPow2(StoreQueueNWriteBanks))
require(StoreQueueNWriteBanks > 1)

// 提取Bank索引和实际索引
def get_bank(in: UInt): UInt = in(log2Up(StoreQueueNWriteBanks) -1, 0)
def get_bank_index(in: UInt): UInt = in >> log2Up(StoreQueueNWriteBanks)
def get_vec_index(index: Int, bank: Int): Int = {
  (index << log2Up(StoreQueueNWriteBanks)) + bank
}
```

### 3.5 数据转发逻辑

SQData8Module实现了高效的数据转发逻辑，用于存储-加载转发：

```scala
// 定义转发结果封装
def parallelFwd(xs: Seq[Data]): Data = {
  ParallelOperation(xs, (a: Data, b: Data) => {
    val l = a.asTypeOf(new FwdEntry)
    val r = b.asTypeOf(new FwdEntry)
    val res = Wire(new FwdEntry)
    res.validFast := l.validFast || r.validFast
    res.valid := l.valid || r.valid
    res.data := Mux(r.valid, r.data, l.data)
    res
  })
}

// 每个转发通道处理
for (j <- 0 until numEntries) {
  val needCheck0 = io.needForward(i)(0)(j)
  val needCheck1 = io.needForward(i)(1)(j)
  val needCheck0Reg = RegNext(needCheck0)
  val needCheck1Reg = RegNext(needCheck1)

  // 快速路径(当前周期)和标准路径(下一周期)
  matchResultVec(j).validFast := needCheck0 && data(j).valid
  matchResultVec(j).valid := needCheck0Reg && data(j).valid
  matchResultVec(j).data := data(j).data
  
  matchResultVec(numEntries + j).validFast := needCheck1 && data(j).valid
  matchResultVec(numEntries + j).valid := needCheck1Reg && data(j).valid
  matchResultVec(numEntries + j).data := data(j).data
}

// 并行结果合并
val parallelFwdResult = parallelFwd(matchResultVec).asTypeOf(new FwdEntry)

// 输出结果
io.forwardValidFast(i) := parallelFwdResult.validFast  // 当前周期生成
io.forwardValid(i) := parallelFwdResult.valid         // 下一周期生成
io.forwardData(i) := parallelFwdResult.data           // 下一周期生成
```

这个转发逻辑实现了两种时序的转发处理：
1. **快速路径** (`forwardValidFast`)：在查询的同一周期生成，用于快速检查
2. **标准路径** (`forwardValid` 和 `forwardData`)：在查询的下一周期生成，包含完整数据

## 4. SQDataModule：数据模块包装器

### 4.1 模块定义

```scala
class SQDataModule(
  numEntries: Int,          // 条目数量(StoreQueueSize)
  numRead: Int,             // 读端口数量
  numWrite: Int,            // 写端口数量
  numForward: Int           // 转发端口数量
)(implicit p: Parameters) extends XSModule with HasDCacheParameters with HasCircularQueuePtrHelper
```

### 4.2 数据类型

```scala
// 完整的存储数据条目
class SQDataEntry(implicit p: Parameters) extends XSBundle {
  val mask = UInt((VLEN/8).W)   // 字节有效掩码
  val data = UInt(VLEN.W)       // 完整数据
}
```

### 4.3 接口定义

```scala
val io = IO(new Bundle() {
  // 同步读取端口
  val raddr = Vec(numRead, Input(UInt(log2Up(numEntries).W)))
  val rdata = Vec(numRead, Output(new SQDataEntry))
  
  // 数据写入端口
  val data = new Bundle() {
    val wen   = Vec(numWrite, Input(Bool()))
    val waddr = Vec(numWrite, Input(UInt(log2Up(numEntries).W)))
    val wdata = Vec(numWrite, Input(UInt(VLEN.W)))
  }
  
  // 掩码写入端口
  val mask = new Bundle() {
    val wen   = Vec(numWrite, Input(Bool()))
    val waddr = Vec(numWrite, Input(UInt(log2Up(numEntries).W)))
    val wdata = Vec(numWrite, Input(UInt((VLEN/8).W)))
  }

  // 转发控制和结果端口
  val needForward = Input(Vec(numForward, Vec(2, UInt(numEntries.W))))
  val forwardMaskFast = Vec(numForward, Output(Vec((VLEN/8), Bool())))
  val forwardMask = Vec(numForward, Output(Vec((VLEN/8), Bool())))
  val forwardData = Vec(numForward, Output(Vec((VLEN/8), UInt(8.W))))
})
```

### 4.4 内部结构和数据流

SQDataModule是SQData8Module的包装器，使用16个SQData8Module实例来处理完整的128位(16字节)VLEN数据：

```scala
// 创建16个字节处理模块
val data16 = Seq.fill(16)(Module(new SQData8Module(numEntries, numRead, numWrite, numForward)))

// 连接写入端口
for (i <- 0 until numWrite) {
  for (j <- 0 until 16) {
    // 掩码写入
    data16(j).io.mask.waddr(i) := io.mask.waddr(i)
    data16(j).io.mask.wdata(i) := io.mask.wdata(i)(j)
    data16(j).io.mask.wen(i)   := io.mask.wen(i)
    
    // 数据写入
    data16(j).io.data.waddr(i) := io.data.waddr(i)
    data16(j).io.data.wdata(i) := io.data.wdata(i)(8*(j+1)-1, 8*j)
    data16(j).io.data.wen(i)   := io.data.wen(i)
  }
}

// 连接读取端口
for (i <- 0 until numRead) {
  // 向所有字节模块发送读地址
  for (j <- 0 until 16) {
    data16(j).io.raddr(i) := io.raddr(i)
  }
  
  // 组合读取结果
  io.rdata(i).mask := VecInit((0 until 16).map(j => data16(j).io.rdata(i).valid)).asUInt
  io.rdata(i).data := VecInit((0 until 16).map(j => data16(j).io.rdata(i).data)).asUInt
}

// 连接转发端口
for (i <- 0 until numForward) {
  for (j <- 0 until 16) {
    // 转发控制信号
    data16(j).io.needForward(i) <> io.needForward(i)
    
    // 转发结果收集
    io.forwardMaskFast(i) := VecInit((0 until 16).map(j => data16(j).io.forwardValidFast(i)))
    io.forwardMask(i) := VecInit((0 until 16).map(j => data16(j).io.forwardValid(i)))
    io.forwardData(i) := VecInit((0 until 16).map(j => data16(j).io.forwardData(i)))
  }
}
```

## 5. LSQ系统中的数据流分析

### 5.1 StoreQueueData在LSQ系统中的数据流

以下是StoreQueueData在整个LSQ系统中的数据流概述：

1. **存储指令入队阶段**:
	- StoreQueue从后端接收存储指令
	- 为指令分配队列条目
	- 初始化相关状态标志

2. **地址和数据写入阶段**:
	- StoreQueue从执行单元接收计算好的存储地址，写入SQAddrModule
	- StoreQueue从执行单元接收存储数据，写入SQDataModule
	- 设置适当的状态标志指示地址和数据就绪

3. **转发检查阶段**:
	- LoadQueue通过StoreQueue向SQAddrModule发送地址查询请求
	- SQAddrModule执行CAM操作，生成地址匹配掩码
	- StoreQueue基于地址匹配和指令年龄信息，计算最终的转发需求
	- 转发需求通过`needForward`信号发送给SQDataModule
	- SQDataModule产生转发结果，返回给StoreQueue
	- StoreQueue将转发数据提供给LoadQueue

4. **存储提交阶段**:
	- ROB通知StoreQueue某存储指令可以提交
	- StoreQueue从SQDataModule读取完整的存储数据
	- 根据存储类型(普通存储、MMIO等)处理数据写回

### 5.2 存储-加载转发完整流程

存储-加载转发是StoreQueueData最关键的功能之一，下面详细说明完整的转发流程：

1. **加载地址生成**:
	- LoadUnit计算加载指令的地址

2. **转发查询初始化**:
	- LoadQueue构造转发查询，包括地址、掩码和队列索引信息
	- 查询通过LoadQueue的`forward`接口发送到StoreQueue

3. **StoreQueue转发处理**:
	- StoreQueue接收查询请求
	- 向SQAddrModule发送地址匹配查询
	- 接收地址匹配结果(`forwardMmask`)
	- 应用年龄过滤和指针比较，生成最终需要检查的条目掩码
	- 将需要检查的条目掩码通过`needForward`信号发送给SQDataModule

4. **SQDataModule数据转发**:
	- 针对每个字节，检查指定条目是否有效且需要转发
	- 使用优先级逻辑选择最新的匹配数据
	- 生成转发结果:
		- `forwardValidFast`: 快速路径，当前周期有效
		- `forwardValid`和`forwardData`: 完整路径，下一周期有效

5. **转发结果返回**:
	- StoreQueue接收SQDataModule的转发结果
	- 将结果通过`forward`接口返回给LoadQueue

6. **LoadQueue处理转发结果**:
	- 接收转发结果(是否有匹配、转发数据)
	- 根据结果决定是否:
		- 使用转发的数据
		- 等待存储指令完成
		- 继续正常的加载操作

这个完整流程确保了加载指令能够正确地从尚未提交到缓存的存储指令中获取数据，是乱序处理器中保证数据依赖正确性的关键机制。

## 6. 优化设计分析

StoreQueueData模块包含多项优化设计，提高性能和效率：

### 6.1 多Bank设计

```scala
require(isPow2(StoreQueueNWriteBanks))
require(StoreQueueNWriteBanks > 1)
```

- 将存储队列条目分布在多个Bank中
- 减少写端口冲突，提高并行度
- 通过哈希函数(get_bank)平衡Bank间负载

### 6.2 并行CAM操作

```scala
for (i <- 0 until numForward) {
  for (j <- 0 until numEntries) {
    // 并行比较所有条目
    io.forwardMmask(i)(j) := linehit && (hit128bit || lineflag(j))
  }
}
```

- 同时比较所有存储队列条目
- 支持多个并发转发请求
- 使用优化的掩码比较提高性能

### 6.3 字节粒度处理

```scala
val data16 = Seq.fill(16)(Module(new SQData8Module(...)))
```

- 每个字节由专用模块处理
- 支持细粒度的部分转发
- 减少不必要的数据移动

### 6.4 两级时序设计

```scala
// 快速路径(当前周期)
matchResultVec(j).validFast := needCheck0 && data(j).valid

// 标准路径(下一周期)
matchResultVec(j).valid := needCheck0Reg && data(j).valid
```

- 提供快速检查路径(validFast)和完整数据路径(valid+data)
- 允许更灵活的时序优化
- 平衡性能和实现复杂度

## 7. StoreQueueData在LSQ系统架构中的位置

```
+-------------------------+
|      处理器后端         |
+------------+------------+
             |
             v
+------------+------------+
|         ROB            |
+------------+------------+
             |                     
             v                     
+------------+------------+        +-----------------+
|      StoreQueue         | <----> |    LoadQueue    |
+------------+------------+        +-----------------+
       |          ^                        ^
       |          |                        |
       v          |                        |
+------------+----+-------+        +-------+----------+
| StoreQueueData          | <----> |    LoadUnit      |
+-------------------------+        +------------------+
       |                                    |
       v                                    v
+-------------------------+        +-----------------+
|    SBuffer/MMIO         | <----> |    缓存/内存     |
+-------------------------+        +-----------------+
```

StoreQueueData是整个LSQ系统的核心数据存储组件，具有以下关键特性：

1. **对StoreQueue提供服务**：
	- 存储所有存储指令的地址、数据和掩码
	- 支持StoreQueue对提交指令的数据读取
	- 辅助StoreQueue完成存储指令的完整处理

2. **与LoadQueue协同工作**：
	- 通过StoreQueue向LoadQueue提供转发服务
	- 快速响应LoadQueue的地址匹配查询
	- 为LoadQueue提供精确的字节级转发数据

3. **促进内存一致性维护**：
	- 支持乱序执行中的数据依赖正确性
	- 减少因存储-加载依赖导致的流水线停顿
	- 提高指令级并行性

这种设计使StoreQueueData成为连接StoreQueue和LoadQueue的桥梁，对于实现高效的乱序执行至关重要。

## 8. 总结

StoreQueueData实现了XiangShan处理器中存储队列的数据存储和转发机制，采用模块化设计和多项优化技术：

1. **层次化设计**：使用SQAddrModule、SQData8Module和SQDataModule分层管理不同类型的数据
2. **高效地址匹配**：实现并行CAM操作，快速识别匹配的存储指令
3. **精细数据转发**：支持字节粒度的数据转发，优化内存依赖处理
4. **多级转发时序**：同时提供快速检查和完整数据路径，平衡性能和实现复杂度
5. **多Bank存储设计**：通过多Bank结构提高访问并行度，减少结构冲突

在LSQ系统中，StoreQueueData通过与StoreQueue和LoadQueue的紧密协作，实现了以下核心功能：

1. **存储指令数据管理**：为StoreQueue提供高效的数据存储机制
2. **存储-加载转发**：支持关键的数据依赖处理，维护程序语义
3. **内存一致性支持**：协助维护在乱序执行中内存访问的一致性和正确性

这些设计使StoreQueueData能够高效处理存储数据并支持关键的存储-加载转发功能，是实现高性能乱序处理器的重要组件。 