# 数值计算 (Numerical Computing)

本部分涵盖数值计算领域的核心算法、实现技术与优化方法。

## 📚 内容概览

### 🔢 超越函数实现

-  **[Power 函数库实现深度解析](power_function_implementation.md)**   
  从软件工程视角深入剖析 `pow(base, exponent)` 函数的内部实现机制，包括整数快速幂算法、浮点数对数-指数转换、以及完整的边界条件处理。

-  **[SLEEF RVV 指数函数实现解析](sleef_rvv_exp_implementation.md)**   
  详细分析 SLEEF 库在 RISC-V Vector 扩展上的 `exp` 函数实现，涵盖参数归约、多项式逼近、结果重构全流程，并提供完整的代码注释与计算示例。

### 📐 多项式逼近技术

-  **[多项式逼近与求值方法论](polynomial_approximation_methods.md)**   
  系统讲解数值计算中的多项式逼近理论与实践，重点关注 Horner 与 Estrin 两种求值算法，深入分析 FMA（融合乘加）指令在 RISC-V Vector 架构下的优化策略。

## 🎯 核心主题

### 算法设计

- 快速幂算法（Exponentiation by Squaring）
- 参数归约技术（Argument Reduction）
- 多项式逼近（Chebyshev、Remez）

### 硬件优化

- RISC-V Vector 扩展（RVV）
- FMA 指令与延迟优化
- 并行度分析与依赖链管理

### 工程实践

- IEEE 754 浮点标准处理
- 边界条件与特殊值
- 数值精度与误差控制

## 🔗 相关资源

-  **硬件实现**  ：参考 [GPU/SFU 硬件设计](../GPU/SFU/sfu_design_and_implementation.md) 了解专用函数单元的微架构
-  **向量扩展**  ：参考 [RISCV/RVV](../RISCV/RVV/index.md) 了解 RISC-V 向量指令集详细规范
