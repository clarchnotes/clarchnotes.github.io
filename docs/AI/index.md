# AI & Machine Learning

本部分涵盖现代人工智能的基础概念、架构设计和优化技术。

## 概述

本部分专注于现代 AI 系统的核心技术，特别强调注意力机制、Transformer 架构及其数学基础。

## 主要内容

### 注意力机制
现代 AI 的突破在于注意力机制，它让模型能够选择性地关注相关信息。

- [Attention 基础](attention/attention_basic.md) - 核心概念与数学原理
- [Flash Attention](attention/flash_attention.md) - 内存高效的注意力计算
- [RoPE 旋转位置编码](attention/rope.md) - 旋转位置编码的深度数学分析

### Transformer 架构
现代语言模型和多模态 AI 系统的骨干架构。

- Transformer 相关文档（待补充）

## 核心概念

### 数学基础
- **注意力计算**: Query-Key-Value 机制与缩放点积注意力
- **位置编码**: 绝对位置 vs 相对位置信息
- **多头注意力**: 不同表示子空间的并行注意力计算

### 优化技术
- **内存效率**: Flash Attention 等内存优化实现
- **训练稳定性**: 层归一化、残差连接、梯度流动
- **计算效率**: 线性注意力变体和稀疏注意力模式
