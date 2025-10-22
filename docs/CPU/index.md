# CPU 处理器架构

本部分深入探讨现代处理器的微架构设计、流水线技术和性能优化。

## 概述

现代 CPU 是复杂的超标量处理器，采用乱序执行、分支预测、多级缓存等先进技术。本部分从前端到后端，系统性地分析 CPU 微架构的各个组件。

## 主要内容

### 前端 (Frontend)

指令获取和解码阶段，负责将指令流转换为微操作。

-  **解码器 (Decoder)** 
  - [HT Write Decoder](fontend/decoder/ht_write_decoder.md) - 超线程写解码器

### 后端 (Backend)

指令执行和内存访问阶段，是性能的关键决定因素。

-  **加载存储单元 (LSU)** 
  - [LSU 基础](Backend/LSU/basics.md) - 加载存储单元基本概念
  -  **香山处理器 LSU** 
    - [LSU 微架构](Backend/LSU/xiangshan/lsu_microarch.md) - 整体架构设计
    -  **加载存储队列 (LSQ)** 
      - [自由列表管理](Backend/LSU/xiangshan/lsq/freelist.md)
      - [虚拟加载队列](Backend/LSU/xiangshan/lsq/virtual_load_queue.md)
      - [加载队列](Backend/LSU/xiangshan/lsq/load_queue.md)
      - [RAW 冲突处理](Backend/LSU/xiangshan/lsq/load_queue_raw.md)
      - [RAR 优化](Backend/LSU/xiangshan/lsq/load_queue_rar.md)
      - [重放机制](Backend/LSU/xiangshan/lsq/load_queue_replay.md)
      - [非缓存访问](Backend/LSU/xiangshan/lsq/load_queue_uncache.md)
      - [异常处理](Backend/LSU/xiangshan/lsq/load_queue_exception.md)
      - [加载非对齐缓冲](Backend/LSU/xiangshan/lsq/load_misalign_buffer.md)
      - [存储队列](Backend/LSU/xiangshan/lsq/store_queue.md)
      - [存储数据](Backend/LSU/xiangshan/lsq/store_queue_data.md)
      - [存储非对齐缓冲](Backend/LSU/xiangshan/lsq/store_misalign_buffer.md)
  -  **内存依赖预测 (MDP)** 
    - [相关论文](Backend/LSU/MDP/papers.md)

## 核心概念

### 微架构基础

-  **超标量执行**  ： 每个时钟周期执行多条指令
-  **乱序执行**  ： 指令可以不按程序顺序执行以提高性能
-  **推测执行**  ： 基于分支预测进行提前执行

### 内存子系统

-  **缓存层次**  ： L1/L2/L3 缓存的设计和一致性
-  **内存依赖**  ： 加载存储指令间的数据依赖关系
-  **内存排序**  ： 保证内存访问的正确性和性能

### 性能优化

-  **流水线设计**  ： 平衡延迟和吞吐量
-  **资源调度**  ： 执行单元和端口的分配
-  **功耗管理**  ： 动态电压频率调节
