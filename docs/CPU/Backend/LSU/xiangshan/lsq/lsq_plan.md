
# XiangShan LSQ 学习计划文档

## 一、概述

XiangShan处理器的访存子系统中，LSQ（Load-Store Queue）是处理器乱序执行中负责处理访存指令重排序、内存依赖检查和提交的关键模块。本学习计划将系统性地介绍XiangShan LSQ相关代码结构和工作原理。

## 二、LSQ架构概览

### 1. 总体架构

LSQ主要包含以下核心组件：
- **VirtualLoadQueue**: 跟踪Load指令执行状态的队列
- **StoreQueue**: 跟踪Store指令执行状态的队列
- **LoadQueueRAW**: 写后读违例检查模块
- **LoadQueueRAR**: 读后读违例检查模块
- **LoadQueueReplay**: Load重发队列
- **LSQWrapper**: LSQ总体包装模块，负责将各个子模块连接

### 2. 整体框图

```
                  +-------------------+
                  |                   |
    Dispatch ----->    LSQWrapper     <----- ROB
                  |                   |
                  +-------------------+
                     |        |
            +--------+        +--------+
            |                          |
  +---------v----------+  +------------v--------+
  |  VirtualLoadQueue  |  |     StoreQueue      |
  +--------------------+  +---------------------+
           |                         |
           v                         v
  +-------------------+    +-------------------+
  | LoadQueueReplay   |    | Load/Store Units  |
  | LoadQueueRAW      |    | SBuffer           |
  | LoadQueueRAR      |    +-------------------+
  | LoadQueueUncache  |
  +-------------------+
```

## 三、学习顺序

根据模块的依赖关系和复杂性，建议按照以下顺序学习LSQ代码：

### 第一阶段：基础设施和数据结构

1. **FreeList.scala**
   - 功能：LSQ中使用的空闲列表管理器
   - 核心概念：空闲列表管理、分配与回收逻辑

### 第二阶段：Load队列系统

2. **VirtualLoadQueue.scala**
   - 功能：存储所有load指令的MicroOp，维护load指令之间的顺序
   - 核心概念：入队、出队、提交逻辑

3. **LoadQueue.scala**
   - 功能：Load队列的具体实现
   - 核心概念：Load队列的操作和状态管理

4. **LoadQueueData.scala**
   - 功能：Load队列的数据存储结构
   - 核心概念：数据存储和访问方式

5. **LoadQueueRAW.scala**
   - 功能：写后读违例检查
   - 核心概念：内存依赖检查算法

6. **LoadQueueRAR.scala**
   - 功能：读后读违例检查
   - 核心概念：内存顺序一致性维护

7. **LoadQueueReplay.scala**
   - 功能：Load重发队列
   - 核心概念：指令重发机制

8. **LoadQueueUncache.scala**
   - 功能：Uncache Load处理单元
   - 核心概念：非缓存访问处理

9. **LoadExceptionBuffer.scala**
   - 功能：Load异常缓冲
   - 核心概念：异常处理机制

10. **LoadMisalignBuffer.scala**
    - 功能：非对齐Load处理
    - 核心概念：地址非对齐访问处理

### 第三阶段：Store队列系统

11. **StoreQueue.scala**
    - 功能：Store队列的具体实现
    - 核心概念：Store队列的操作和状态管理

12. **StoreQueueData.scala**
    - 功能：Store队列的数据存储结构
    - 核心概念：数据存储和访问方式

13. **StoreMisalignBuffer.scala**
    - 功能：非对齐Store处理
    - 核心概念：地址非对齐访问处理

### 第四阶段：集成和接口

14. **LSQWrapper.scala**
    - 功能：LSQ总体包装模块
    - 核心概念：各模块间的连接和协调

## 四、每个模块的详细学习计划

### 1. FreeList.scala

#### 功能描述
FreeList管理LSQ中的可用条目，提供分配和释放机制。

#### 学习要点
- 循环队列指针辅助器（CircularQueuePtrHelper）的使用
- 分配和释放逻辑
- 空闲槽位计数机制

#### 接口分析
- 分配请求和响应
- 释放机制
- 计数器管理

### 2. VirtualLoadQueue.scala

#### 功能描述
VirtualLoadQueue是一个队列，用于存储所有load指令的MicroOp，维护load指令之间的顺序，类似于load指令的ROB，其主要功能为跟踪Load指令执行状态。

#### 学习要点
- Load指令状态跟踪：allocated、isvec、committed
- 入队逻辑（dispatch阶段）
- 流水线写回（load流水线S3阶段）
- 出队条件和逻辑

#### 接口分析
- 入队请求和响应
- 流水线写回接口
- 与ROB的交互接口

### 3. LoadQueue.scala

#### 功能描述
LoadQueue实现了Load队列的主要功能，管理Load指令的执行和提交。

#### 学习要点
- Load队列的操作和状态管理
- 与VirtualLoadQueue的交互
- 加载操作的执行和提交

#### 接口分析
- 与执行单元的接口
- 与ROB的交互接口
- 与StoreQueue的交互接口

### 4-13. 其他模块

类似地分析其他模块的功能描述、学习要点和接口分析。

### 14. LSQWrapper.scala

#### 功能描述
LSQWrapper是LSQ系统的顶层模块，负责将VirtualLoadQueue、StoreQueue等各个子模块连接起来，形成完整的LSQ系统。

#### 学习要点
- 各模块间的连接方式
- 控制信号的传递和处理
- 指令入队和出队的总体流程
- 异常和重定向处理机制

#### 接口分析
- 与派遣阶段的接口
- 与ROB的接口
- 与执行单元的接口
- 与缓存系统的接口

## 五、高级主题

完成基本模块学习后，可以进一步学习以下高级主题：

1. **内存依赖预测**：XiangShan如何预测和处理内存依赖
2. **违例恢复机制**：当发生RAW或RAR违例时的恢复流程
3. **非对齐访存处理**：处理非对齐访存的机制和优化
4. **向量访存支持**：LSQ如何支持向量访存指令
