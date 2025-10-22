# GPU

本部分涵盖 GPU 架构、并行计算模型和 CUDA 编程技术。

## 概述

GPU 是高度并行的处理器，专为大规模数据并行计算而设计。从图形渲染到通用计算，GPU 已成为现代计算的重要组成部分。

## 主要内容

### 基础概念

GPU 架构和并行计算的基本原理。

- [GPU 基础概念](basics/basic_concepts.md) - GPU 架构和计算模型

### CUDA 编程

NVIDIA CUDA 并行计算平台和编程模型。

- [CUDA 示例](CUDA/cuda_example.md) - CUDA 编程入门
- [CUDA 程序效率](CUDA/cuda_prgm_efficiency.md) - 性能优化技术

### TinyGPU

轻量级 GPU 设计和实现。

## 核心概念

### 并行计算模型

-  **SIMT 架构**  ： 单指令多线程执行模型
-  **线程层次**  ： Grid、Block、Thread 的组织结构
-  **内存层次**  ： 全局内存、共享内存、寄存器

### GPU 架构

-  **流多处理器 (SM)**  ： GPU 的基本计算单元
-  **Warp 调度**  ： 32 个线程为一组的执行单位
-  **内存合并**  ： 优化内存访问模式

### 性能优化

-  **占用率优化**  ： 最大化 SM 利用率
-  **内存访问优化**  ： 减少内存延迟和带宽瓶颈
-  **算法并行化**  ： 将串行算法转换为并行实现

## 参考资源

- [zartbot GPU 架构分析](https://mp.weixin.qq.com/s/rxwjGLXUQK-SCAYVcuBemw)
- [Analyzing Modern NVIDIA GPU cores](https://arxiv.org/pdf/2503.20481v1)
