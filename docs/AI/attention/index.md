# 注意力机制

本部分全面介绍注意力原理、实现方法和优化技术。注意力机制是现代深度学习的基石，特别是在自然语言处理和计算机视觉领域。

## 概述

注意力机制让模型能够选择性地关注输入的相关部分，彻底改变了神经网络处理序列和结构化数据的方式。从最初的缩放点积注意力到现代优化方法，这些机制构成了 Transformer 架构的基础。

## 核心概念

### 数学基础

注意力机制基于查询和键的兼容性计算值的加权和：

$$\text{Attention}(Q,K,V) = \text{softmax}\left(\frac{QK^T}{\sqrt{d_k}}\right)V$$

### 关键特性

- **排列不变性**: 与顺序无关的计算，需要显式的位置编码
- **并行化能力**: 与 RNN 不同，注意力支持序列位置间的并行计算
- **长距离依赖**: 序列中远距离位置间的直接连接

## 文档列表

### 基础概念

- [Attention 基础](attention_basic.md) - 核心概念与数学原理

### 内存优化

- [Flash Attention](flash_attention.md) - 内存高效的注意力计算
  - GPU 内存层次的分块策略
  - 在线 softmax 计算
  - 显著的加速和内存减少

- [Paged Attention](paged_attention.md) - 基于虚拟内存分页的KV缓存管理
  - 动态内存分配与页面管理
  - 消除内存碎片化问题
  - 支持序列间内存共享

- [KV Cache](kv_cache.md) - 自回归生成的核心加速技术
  - 避免重复计算的缓存机制
  - 从O(n²)到O(n)的复杂度优化
  - 详细实现示例与性能分析

- [RVV Flash Attention](rvv_flash_attention.md) - RISC-V Vector优化实现
  - 完整的RVV intrinsics实现
  - Gem5仿真环境配置与运行
  - 向量化优化策略与性能分析

### 核心架构

- [Transformer](transformer.md) - 革命性的神经网络架构
  - 完全基于注意力机制的设计
  - 编码器-解码器架构详解
  - 多头注意力与位置编码
  - 完整实现与训练技巧

### 位置编码

- [RoPE 旋转位置编码](rope.md) - 旋转位置编码的全面分析
  - **数学优雅性**: 为什么旋转操作特别适合相对位置编码
  - **多尺度设计**: 不同旋转频率如何捕捉各种尺度的依赖关系
  - **理论保证**: 相对位置不变性的数学证明
  - **实际实现**: 详细的计算示例和验证

## 主要优势

- **灵活性**: 基于输入内容的自适应注意力权重
- **可解释性**: 注意力权重提供模型关注点的洞察
- **可扩展性**: 高效实现支持长序列处理
- **通用性**: 在多个领域成功应用（NLP、视觉、多模态）

## 参考资料

- [Attention Is All You Need](https://arxiv.org/abs/1706.03762) - Transformer 开创性论文
- [RoFormer: Enhanced Transformer with Rotary Position Embedding](https://arxiv.org/abs/2104.09864) - RoPE 原始论文
- [FlashAttention: Fast and Memory-Efficient Exact Attention](https://arxiv.org/abs/2205.14135) - Flash Attention 论文
