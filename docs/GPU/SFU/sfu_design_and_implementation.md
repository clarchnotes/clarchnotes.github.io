# 现代图形与向量处理器中特殊函数单元 (SFU) 的设计与实现

## 第一章：特殊函数单元 (SFU) 概论

### 1.1 SFU 在现代计算中的角色与重要性

特殊函数单元（Special Function Unit, SFU）是现代高性能处理器微架构中一个高度专业化的计算加速器，其核心任务是高效执行超越函数（transcendental functions）与三角函数等复杂数学运算 [[1]](#ref1)。从历史上看，SFU 的出现与图形处理单元（Graphics Processing Unit, GPU）的崛起密不可分。在早期的图形渲染管线中，光照计算、坐标变换和纹理映射等光栅化操作（rasterization）需要进行大量的三角函数、倒数和平方根倒数运算 [[1]](#ref1)。为了将这些计算密集型任务从主中央处理器（CPU）中卸载，硬件设计师在 GPU 内部集成了专门的 SFU，从而极大地提升了图形处理的效率和实时性。

随着通用图形处理器（GPGPU）计算的兴起，SFU 的角色发生了根本性的转变。它不再仅仅是图形渲染的附属品，而是演变为一个与算术逻辑单元（ALU）、加载/存储单元（Load/Store Unit）并列的一等执行单元，成为科学计算、物理模拟和金融建模等领域不可或缺的硬件基础。近年来，人工智能（AI）特别是深度学习的爆发式增长，进一步凸显了 SFU 的战略重要性。现代神经网络，尤其是以 Transformer 为代表的模型，其核心的注意力机制（attention mechanism）和激活函数严重依赖于指数、对数和除法等超越函数运算 [[3]](#ref3)。因此，SFU 的性能直接决定了 AI 模型训练和推理的效率。

在主流的 GPU 架构中，SFU 被深度集成在最基本的计算单元——流式多处理器（Streaming Multiprocessor, SM，NVIDIA 架构）或计算单元（Compute Unit, CU，AMD 架构）内部 [[3]](#ref3)。每个 SM/CU 都包含多个 SFU，与大量的 CUDA 核心（或流处理器）、张量核心（Tensor Cores）或矩阵核心（Matrix Cores）协同工作，共同为大规模并行计算提供强大的算力支持 [[2]](#ref2)。这种紧密的集成确保了 SFU 能够以极低的延迟访问寄存器堆和共享内存，从而最大化执行效率。

### 1.2 核心功能：超越函数与特殊运算

SFU 所处理的"特殊函数"是一类无法通过有限次加、减、乘、除、开方等代数运算表示的函数。其实现的功能集在不同厂商和架构代际之间保持了高度的共性，主要涵盖以下几类核心运算：

*  **三角函数**  ： 正弦 ($\sin(x)$) 和余弦 ($\cos(x)$)。这是图形学中进行旋转、光照模型计算的基础。
*  **指数与对数函数**  ： 以 2 为底的指数 ($2^x$) 和以 2 为底的对数 ($\log_2(x)$)。它们在科学计算中广泛用于表示增长、衰减模型，并且是 AI 中 softmax、sigmoid 等激活函数的计算基础。
*  **倒数与平方根倒数**  ： 倒数 ($1/x$) 和平方根倒数 ($1/\sqrt{x}$)。这两个函数在向量归一化（normalization）等图形学操作中至关重要。例如，计算一个向量的单位向量需要除以其模长，而除法运算在硬件上通常通过乘以其倒数来实现，平方根倒数则可以一步到位。

这些硬件实现的功能通过底层指令集向程序员或编译器暴露。在 NVIDIA 的 SASS（Streaming Assembler）指令集中，这些操作通常以 MUFU（Multi-Function Unit）为前缀，例如 MUFU.COS（余弦）、MUFU.EX2（以 2 为底的指数）、MUFU.LG2（以 2 为底的对数）以及 MUFU.RSQ（平方根倒数）[[3]](#ref3)。这种指令级的抽象使得上层编程语言（如 CUDA C++）中的数学函数调用（如 `cosf()`、`exp2f()`）能够直接映射到高效的硬件执行单元上。

### 1.3 架构集成：GPU 流式多处理器与 VPU 向量引擎

SFU 在不同类型的处理器中的集成方式反映了其架构的设计哲学。在 NVIDIA GPU 中，SFU 是 SM 微架构不可分割的一部分。以 Hopper 和 Blackwell 架构为例，每个 SM 内部都配置了多个 SFU（例如，每个 SM 分区配备一个 SFU，一个 SM 通常有四个分区），与 FP32 单元（CUDA Cores）、FP64 单元、Tensor Cores、加载/存储单元（LD/ST）以及一个大型的寄存器文件和 L1 缓存/共享内存紧密耦合 [3]。这种设计使得在一个 Warp（32 个线程的集合）中执行的线程可以同时向 SFU 分派指令，实现大规模的线程级并行（Thread-Level Parallelism）[8]。

在 Intel Xe GPU 架构中，也采用了类似的模式。其基础计算模块被称为 Xe-core，每个 Xe-core 包含 16 个向量引擎（Vector Engines）和 16 个矩阵引擎（Matrix Engines, XMX）[[10]](#ref10)。SFU 作为固定功能硬件（fixed-function hardware）的一部分，与这些引擎共同构成了 Xe-core 这一不可分割的计算构建块，为图形和通用计算任务提供支持 [[11]](#ref11)。

与 GPU 将 SFU 作为独立硬件单元的设计不同，现代 CPU 中的向量处理单元（Vector Processing Unit, VPU）通过单指令多数据（SIMD）的指令集扩展来实现类似的功能。例如，Intel 的 AVX（Advanced Vector Extensions）指令集，特别是 AVX-512，提供了一系列指令来加速数学运算 [[12]](#ref12)。这些指令允许 CPU 在一个时钟周期内对一个向量（包含多个数据元素）执行相同的操作。这种方式将特殊函数的计算能力赋予了 CPU 的通用向量流水线，而不是通过一个独立的、专门的硬件单元。
这种架构上的差异体现了 GPU 和 CPU 在设计目标上的根本不同：GPU 的 SM/CU 旨在通过成千上万个线程的并行执行来最大化吞吐量（Throughput），独立的 SFU 硬件是实现这一目标的关键；而 CPU 的 VPU 则更侧重于加速单个或少数几个线程的执行，提升其 **延迟（Latency）** 表现，通过扩展通用执行单元的功能来实现这一目标。

### 1.4 关键设计指标：性能、精度与硬件成本

SFU 的设计过程是一个在三个核心指标之间进行复杂权衡的工程挑战：性能、精度和硬件成本。

*  **性能（Performance）**  ： 主要由两个维度衡量：吞吐量和延迟。吞吐量指的是 SFU 每个时钟周期能够完成的操作数量。对于 GPU 而言，高吞吐量至关重要，因为它直接关系到并行处理大量数据的能力。延迟则是指单个操作从指令分派到结果返回所需的时间。虽然 GPU 架构擅长通过大规模多线程来隐藏延迟，但较低的延迟仍然有助于提升整体性能，特别是对于存在数据依赖的计算链。
*  **精度（Precision）**  ： SFU 通常针对特定的浮点数格式进行优化，其中最常见的是 32 位单精度浮点数（FP32 或 binary32）[[1]](#ref1)。计算结果的精确度是衡量 SFU 质量的关键标准，通常使用"最后一位单位误差"（Unit in the Last Place, ULP）来量化。一个好的 SFU 设计需要在保证足够精度的前提下，尽可能快地得出结果。为了追求极致性能，许多架构也支持所谓的"快速数学"（fast math）模式，通过牺牲对 IEEE 754 标准的严格遵循（例如，对非规格化数的处理）来换取更快的计算速度 [[8]](#ref8)。
*  **硬件成本（Hardware Cost）**  ： 这包括了实现 SFU 所需的芯片面积（Area）和功耗（Power Consumption）[[14]](#ref14)。更复杂的算法和更高精度的实现通常需要更多的晶体管，从而增加芯片面积和静态功耗。同时，高频率的运算也会带来显著的动态功耗。设计师必须在满足性能和精度要求的同时，将硬件成本控制在合理的预算之内，以确保整个处理器的能效比。

这三个指标相互制约，构成了 SFU 设计的"不可能三角"。例如，采用更简单的数值近似算法可以降低硬件成本和延迟，但可能会牺牲精度；而追求更高的精度则可能需要更复杂的电路，从而增加面积、功耗和延迟。后续章节将深入探讨，现代 SFU 设计如何通过精巧的算法和硬件协同设计，在这一系列复杂的权衡中找到最佳平衡点。

一个极具说服力的例子是，SFU 作为曾经主要服务于图形学的功能单元，正因人工智能的崛起而经历一场复兴。现代 AI 模型，特别是驱动大型语言模型的 Transformer 架构，其核心的注意力层严重依赖于 softmax 函数，该函数在数学上包含大量的指数和除法运算 [[4]](#ref4)。这种计算负载特性直接导致了 SFU 成为 AI 工作流中的性能瓶颈。NVIDIA 在其 Blackwell 架构中明确指出，通过将用于注意力机制的关键 SFU 指令吞吐量翻倍，实现了高达 2 倍的注意力层计算速度提升 [[4]](#ref4)。这一决策清晰地揭示了一个因果关系：一个特定的、至关重要的 AI 算法（注意力机制）的数学需求，正在直接驱动一个核心 GPU 组件（SFU）的微架构演进。这不再是一个通用的性能提升，而是一次针对当前时代最主要 AI 工作负载的精准优化。这也预示着，未来的 SFU 设计将与新兴 AI 模型的需求进行深度协同，可能会集成更多针对特定激活函数或其他复杂运算的硬件加速功能。

## 第二章：特殊函数的数值近似方法论

由于超越函数无法通过有限次基本代数运算精确求解，因此在硬件中实现这些函数必须依赖于数值近似方法。SFU 的设计核心在于选择一种或多种能够在性能、精度和成本之间取得最佳平衡的近似算法。主流的实现方法可分为两大类：非迭代方法和迭代方法。

### 2.1 非迭代方法：基于查找表 (LUT) 与多项式近似

非迭代方法，特别是查找表（Look-Up Table, LUT）与低阶多项式近似相结合的混合方法，是现代 GPU SFU 设计中最主流的选择 [[8]](#ref8)。其基本思想是避免在整个定义域上使用一个复杂的高阶多项式，而是将定义域分割成大量极小的子区间，在每个子区间内使用一个简单的低阶多项式（通常是一次或二次）进行逼近。

#### 2.1.1 分段多项式近似原理

分段多项式近似（Piecewise Polynomial Approximation）的原理如下：首先，对输入参数 x 进行参数归约（Argument Reduction），将其映射到一个较小的、标准化的区间内，例如 $[0, \pi/4]$ 对于三角函数。然后，将这个归约后的区间进一步分割成 $2^p$ 个更小的子区间。输入参数 x 的高 $p$ 位被用作地址，在一个查找表（LUT）中索引，以获取对应子区间的预计算多项式系数 [[15]](#ref15)。x 的剩余低位则作为自变量，代入这个低阶多项式进行求值，得到最终的近似结果。

这种方法的优势在于，当逼近区间足够小时，一个非常简单的多项式就能达到很高的精度。研究表明，对于二次分段多项式，近似结果的有效比特数大致与 $p$（即地址位数）成线性关系 [[15]](#ref15)。这使得设计者可以通过调整 $p$ 的大小（即 LUT 的规模）来灵活地平衡硬件成本和计算精度。

#### 2.1.2 极小化极大误差 (Minimax) 逼近与 Remez 算法

为了在每个子区间内获得最佳的逼近效果，需要选择最优的多项式系数。这里的"最优"通常指 **极小化极大误差（Minimax）** 准则，即寻找一个多项式 $p(x)$，使得在整个子区间上，逼近误差 $|f(x) - p(x)|$ 的最大值达到最小。根据切比雪夫交错定理，这样的最优多项式是存在且唯一的。硬件设计者通常使用 Remez 算法来计算这些 minimax 多项式的系数 [8]。Remez 算法是一种迭代算法，能够高效地找到满足切比雪夫交错定理的系数。像 Maple 和 Mathematica 这样的计算机代数系统内置了 Remez 算法的实现，成为 SFU 设计中生成多项式系数的重要工具 [[8]](#ref8)。

#### 2.1.3 系数优化与硬件成本分析

通过 Remez 算法计算出的多项式系数是理想的实数，但在硬件中必须被量化为有限位数的定点数或浮点数才能存储在 LUT 中。这个量化过程（截断或舍入）会引入系数舍入误差，从而影响最终的计算精度。研究表明，对于二次多项式 $a_0 + a_1 \ell + a_2 \ell^2$，一次项系数 $a_1$ 的舍入对最终精度的影响最大 [15]。为了缓解这个问题，可以采用更精巧的优化技术。一种有效的方法是，在对 $a_1$ 进行舍入后，重新计算常数项 $a_0$ 和二次项 $a_2$，以部分补偿由 $a_1$ 舍入带来的误差。这种"部分舍入"技术能够在不增加系数存储位数的情况下，显著提升近似精度，或者在同等精度要求下，减小 LUT 的规模 [15]。

该方法的硬件成本主要由两部分构成：

*  **LUT 规模**  ：大小为 $2^p \times (\text{总系数位数})$。例如，一个地址位数为 8 ($p=8$)，存储一个 22 位的 $a_0$ 和一个 7 位的 $a_2$ 的 LUT，其总大小为 $2^8 \times (22+7) = 256 \times 29$ 比特，约等于 1 KB [15]。
*  **计算单元成本**  ：主要是一个或多个乘法器和加法器，用于评估多项式。乘法器的位宽取决于输入参数的低位位数和系数的位数。

通过结合使用 minimax 逼近和系数优化，这种混合方法能够用相对较小的硬件成本实现高精度的函数计算，因此备受青睐。

### 2.2 迭代方法 I：CORDIC 算法

CORDIC（COordinate Rotation DIgital Computer）算法是一种优雅且硬件高效的迭代方法，尤其擅长计算三角函数、双曲函数和对数等 [[14]](#ref14)。其最大的特点是完全避免了硬件乘法器，仅使用移位、加法和减法操作，这在早期或资源受限的硬件设计中极具吸引力 [[18]](#ref18)。

#### 2.2.1 旋转模式与向量模式

CORDIC 算法的核心思想是通过一系列预定角度的微旋转，将一个初始向量逐步旋转到目标角度。它主要有两种工作模式：

*  **旋转模式（Rotation Mode）**  ：输入一个向量 $(x, y)$ 和一个目标角度 $z$，算法通过一系列微旋转，将输入向量旋转 $z$ 角度。如果初始向量设为 $(K, 0)$（其中 $K$ 是一个预计算的尺度因子），经过旋转后，最终向量的坐标 $(x_{\text{final}}, y_{\text{final}})$ 将近似等于 $(K \cos(z), K \sin(z))$。这样就计算出了正弦和余弦值 [18]。
*  **向量模式（Vectoring Mode）**  ：输入一个向量 $(x, y)$，算法通过一系列微旋转，将该向量旋转到 X 轴上，使其 y 分量趋近于零。在这一过程中，累加的旋转角度之和就是初始向量的反正切值 $\arctan(y/x)$，而最终向量的 x 分量则是初始向量的模长乘以尺度因子 $K \sqrt{x^2+y^2}$ [18]。

#### 2.2.2 算法收敛性与精度分析

CORDIC 的迭代过程如下：在第 $i$ 次迭代中，算法将向量旋转一个固定的角度 $\alpha_i = \arctan(2^{-i})$。旋转方向（顺时针或逆时针）取决于当前累积角度与目标角度的差值。由于 $\tan(\alpha_i) = 2^{-i}$，旋转矩阵中的乘法操作可以被简化为移位操作。该算法具有确定的收敛性。对于 n 位精度的数据，通常需要进行 n 次迭代 [19]。每次迭代会引入一个微小的模长增益，所有迭代累积的总增益是一个固定的尺度因子 K。这个因子可以预先计算并存储，在迭代结束后通过一次乘法进行校正，或者在某些应用中，可以直接将该因子吸收到后续的计算中，从而完全避免乘法 [17]。

### 2.3 迭代方法 II：牛顿-拉夫逊法与 Goldschmidt 算法

牛顿-拉夫逊（Newton-Raphson, NR）法及其变种（如 Goldschmidt 算法）是另一类强大的迭代方法，以其 **二次收敛（Quadratic Convergence）** 特性而闻名 [14]。二次收敛意味着在每次迭代中，结果的有效数字位数大约会翻倍，这使得算法能够以极少的迭代次数快速逼近高精度的解 [[21]](#ref21)。这类算法尤其适用于计算除法、倒数和平方根倒数 [[7]](#ref7)。

#### 2.3.1 倒数与平方根倒数的快速计算

NR 方法通过寻找一个函数的零点来求解问题。

*  **计算倒数 $1/D$**  ： 相当于求解函数 $f(X) = 1/X - D$ 的根。其 NR 迭代公式为：
    $$X_{i+1} = X_i \cdot (2 - D \cdot X_i)$$
    这个迭代过程只涉及两次乘法和一次减法，完全避免了硬件除法器 [[22]](#ref22)。
*  **计算平方根倒数 $1/\sqrt{S}$**  ： 相当于求解函数 $f(X) = 1/X^2 - S$ 的根。其 NR 迭代公式为：
    $$X_{i+1} = \frac{X_i}{2} \cdot (3 - S \cdot X_i^2)$$
    这个过程同样只涉及乘法、减法和一次简单的移位（除以 2），效率极高 [[23]](#ref23)。

#### 2.3.2 二次收敛特性与迭代次数

NR 算法的执行流程通常是：

*  **初始猜测（Initial Guess）**  ：通过一个非常小的 LUT，根据输入操作数的高位，得到一个低精度的初始近似值 $X_0$。这个初始值通常能保证有 6 到 8 位的精度。
*  **迭代求精（Iterative Refinement）**  ：将 $X_0$ 代入上述迭代公式，进行数次迭代。由于是二次收敛，从一个 8 位精度的初始值出发，第一次迭代后精度可达约 16 位，第二次迭代后即可达到超过 24 位的单精度要求 [[24]](#ref24)。因此，通常只需要 2 到 3 次迭代就能完成计算。

尽管 CORDIC 和 NR 算法在数学上非常优雅，但它们在现代 GPU 中的应用却不如 LUT-多项式方法广泛。这背后深层的原因在于 GPU 的架构特性。GPU 的核心设计哲学是追求极致的并行吞吐量，而非单个线程的执行延迟。它通过大规模多线程（成千上万的 Warp 或 Wavefront）和深度流水线化的执行单元来实现这一目标 [[2]](#ref2)。在这种模式下，Warp 调度器不断地从不同的线程束中分派指令，以确保每一个计算单元都保持忙碌，从而有效地隐藏了单个操作的延迟 [[7]](#ref7)。

迭代算法，如 CORDIC 和 NR，其内在的数据依赖性（第 $i$ 次迭代的结果依赖于第 $i-1$ 次的结果）与这种流水线模型存在冲突 [[18]](#ref18)。一个线程执行迭代算法时，要么会长时间占用一个硬件单元，导致流水线停顿；要么就需要一个在物理上完全展开（unrolled）的巨大硬件电路，为每一次迭代都配备独立的计算资源，这会消耗大量的芯片面积 [27]。

相比之下，LUT-多项式方法可以被完美地映射到一个前馈式（feed-forward）、固定延迟的硬件流水线中：第一级进行参数归约和 LUT 查找，第二级和第三级进行乘法和加法运算 [15]。这样的硬件单元具有可预测的、固定的执行延迟，使得 Warp 调度器可以轻松地进行指令调度和延迟隐藏。因此，LUT-多项式方法的主导地位，并不仅仅是其精度或面积优势的结果，更是其与 GPU 高吞吐量、延迟隐藏的执行范式高度契合的必然选择。

下表总结了这三种主要数值近似方法的特点与权衡。

## 表 2-1: 特殊函数数值近似方法对比

| 方法          | 核心原理                     | 硬件成本 (面积/功耗)         | 性能 (延迟/吞吐量)         | 典型精度    | 主要应用场景             |
| :------------ | :--------------------------- | :--------------------------- | :--------------------------- | :---------- | :----------------------- |
| LUT + 多项式  | 分段多项式逼近，系数由 LUT 提供 | 高 (乘法器, RAM)             | 低延迟 / 高吞吐量            | FP32 (1-4 ULP) | GPU SFU (通用)           |
| CORDIC        | 迭代式坐标旋转               | 低 (移位器, 加法器)          | 高延迟 / 低吞吐量            | 可配置      | FPGA, 低功耗嵌入式系统   |
| 牛顿-拉夫逊   | 迭代式求根 (二次收敛)        | 中 (乘法器)                  | 中等延迟 / 中等吞吐量        | FP32 (完全) | 倒数, 除法, 平方根 (常用于求精) |

## 第三章：SFU 硬件架构与电路级实现

将第二章讨论的数值近似算法转化为高效的硬件电路，是 SFU 设计的核心环节。本章将深入探讨不同算法所对应的硬件数据路径（Datapath）设计、电路结构以及多功能单元的实现策略。

### 3.1 混合式多项式近似单元的数据路径设计

基于 LUT 和多项式近似的混合方法，其硬件数据路径直接反映了算法的计算流程，通常是一个深度流水线化的结构，以实现单周期吞吐量 [16]。一个典型的二次多项式逼近单元的数据路径包括以下关键模块：

*  **输入寄存器与参数归约逻辑**  ：接收浮点操作数 x，并执行参数归约，将其映射到预定的计算区间。
*  **输入分割器（Splitter）**  ：将归约后的定点数 x 分割为两部分：高位的 $p$ 个比特 (r) 和低位的 $m$ 个比特 ($x'$)。
*  **查找表（LUT）**  ：r 作为地址输入到一个只读存储器（ROM）或静态随机存取存储器（SRAM）模块中。该模块存储了预计算好的多项式系数（例如，二次多项式的 a, b, c）。LUT 的输出宽度等于所有系数的总位数 [16]。
*  **多项式求值核心**  ：这是数据路径的计算核心。$x'$ 和从 LUT 中读出的系数被送入一个算术逻辑单元。对于二次多项式 $a \cdot (x')^2 + b \cdot x' + c$，该单元通常由两个乘法器和一个两输入加法器构成。为了优化性能和面积，现代设计倾向于使用 **积和熔加运算（Fused Multiply-Add, FMA）** 单元 [9]。通过 FMA，该表达式可以通过两次 FMA 操作高效计算：FMA(a, x', b) 得到 a*x' + b，再进行一次乘法和一次加法，或者通过霍纳法则 $(a \cdot x' + b) \cdot x' + c$ 来实现。
*  **后处理与舍入逻辑**  ：求值核心的输出是高精度的中间结果。该模块负责将结果进行舍入，转换为最终的浮点格式，并处理如溢出、下溢等异常情况。

整个数据路径被划分为多个流水线阶段（例如：LUT 读取、乘法、加法、舍入），使得每个时钟周期都能接收一个新的输入操作数并产出一个结果，从而实现极高的计算吞吐量。

### 3.2 CORDIC 单元的硬件实现：流水线与展开式架构

CORDIC 算法的迭代特性使其硬件实现有两种截然不同的架构选择，体现了面积与吞吐量之间的经典权衡。

*  **展开式架构（Unrolled Architecture）**  ：这种架构为每一次迭代都实例化一个独立的物理计算阶段 [19]。一个 n 次迭代的 CORDIC 单元由 n 个级联的微旋转模块构成 [28]。每个模块包含：
  * 三个寄存器，用于存储 $(x_i, y_i, z_i)$。
  * 两个可变移位器（Barrel Shifters），用于实现乘以 $2^{-i}$ 的操作。
  * 两个加法器/减法器。
  * 一个小型 ROM，用于存储预计算的角度值 $\arctan(2^{-i})$。
    数据从第一个模块流入，逐级通过所有 n 个模块，在一个完整的流水线周期后输出最终结果。这种设计的优点是吞吐量极高，可以达到每个时钟周期一个结果。缺点是硬件面积巨大，因为每个迭代步骤的硬件资源都被复制了 n 次。
*  **折叠式架构（Folded/Iterative Architecture）**  ：为了节省硬件资源，折叠式架构只实例化一个微旋转模块，并通过一个反馈回路（feedback loop）在 n 个时钟周期内重复使用这个模块来完成 n 次迭代。这种设计极大地减小了芯片面积，但其吞吐量仅为展开式架构的 1/n，延迟也显著增加。

由于 GPU 对高吞吐量的极致追求，如果采用 CORDIC 算法，展开式架构是更可能的选择，但这会带来巨大的面积开销，这也是该算法在现代 GPU 中不被广泛采用的原因之一。

### 3.3 牛顿-拉夫逊迭代单元的电路设计

牛顿-拉夫逊（NR）算法的硬件实现同样是一个迭代结构。以倒数运算的迭代公式 $X_{i+1} = X_i \cdot (2 - D \cdot X_i)$ 为例，其数据路径的核心是一个反馈回路 [22]。一个 NR 迭代单元的电路通常包含：

*  **初始值 LUT**  ：一个小型 ROM，根据输入除数 D 的高位提供一个低精度的初始倒数近似值 $X_0$。
*  **迭代核心**  ：
  * 一个乘法器，计算 $D \cdot X_i$。
  * 一个减法器/补码器，计算 $2 - (D \cdot X_i)$。
  * 第二个乘法器，计算 $X_i \cdot (2 - D \cdot X_i)$，得到 $X_{i+1}$。
*  **寄存器与控制逻辑**  ：一个寄存器用于在迭代之间锁存中间结果 $X_i$。控制逻辑负责管理迭代次数，在达到预定次数（例如 2 或 3 次）后，将最终结果输出。

与多项式近似单元的前馈式流水线不同，NR 单元的反馈结构意味着单个操作需要多个时钟周期才能完成。然而，由于其二次收敛性，所需的迭代次数非常少，因此总延迟仍然是可控的。在实践中，NR 方法常被用于对由 LUT-多项式方法产生的中等精度结果进行最后的求精，以达到完全的单精度或双精度要求。

### 3.4 控制逻辑与多功能单元的资源共享

在实际的 GPU 设计中，SFU 并非为每个函数都配备一套独立的硬件，而是作为一个 **多功能单元（Multi-Function Unit, MUFU）** 存在的 [3]。为了最大化硬件利用率并节省芯片面积，不同函数的计算过程会共享大部分数据路径资源，如乘法器、加法器和移位器 [31]。

控制逻辑在其中扮演着核心角色。当一条 MUFU 指令（如 MUFU.COS 或 MUFU.LG2）被分派到 SFU 时，指令的操作码（opcode）会被控制逻辑解码。根据操作码，控制逻辑会产生一系列控制信号，用于：

*  **选择正确的 LUT**  ：为不同函数（如 sin, cos, log）选择存储其各自多项式系数的 ROM 区域。
*  **配置数据路径**  ：通过多路复用器（MUX）选择正确的操作数，配置加法器/减法器的操作模式，甚至在某些简单函数中旁路（bypass）掉不需要的乘法器 [33]。
*  **管理迭代过程**  ：对于迭代算法，控制逻辑负责初始化、计数和终止迭代循环。

通过这种方式，一个物理上的 SFU 硬件单元可以灵活地执行指令集所支持的全部特殊函数，实现了功能性和硬件效率的高度统一。

这种高效硬件实现的一个关键因素是积和熔加运算（FMA）单元的普遍应用。多项式求值，作为 SFU 中最核心的计算任务，其数学形式（一系列乘法和加法的总和）与 FMA 操作完美契合。例如，一个二次多项式 $a \cdot x^2 + b \cdot x + c$ 可以利用霍纳法则重写为 $(a \cdot x + b) \cdot x + c$，这可以被高效地分解为两次依赖的 FMA 操作。现代 GPU 的 CUDA 核心本身就是围绕着高度优化的、全流水线的 FMA 单元构建的 [9]。因此，SFU 的数据路径设计极有可能复用或借鉴了这些为通用计算而精心调优的 FMA 硬件模块。这种设计上的协同效应——即最主流的数值算法（多项式近似）恰好能映射到芯片上最高效的算术电路（FMA）——是现代 SFU 能够实现惊人计算吞吐量的重要原因。SFU 并非由奇特的、定制化的电路构成，而是对 GPU 中最强大、最高效的计算基石（FMA 单元）的巧妙重组和专用化。

## 第四章：案例研究：主流 GPU 中的 SFU 设计

本章将深入分析两大主流 GPU 厂商——NVIDIA 和 AMD——在其旗舰架构中 SFU 的设计理念、实现细节和精度保证，揭示不同技术路线和生态策略对 SFU 的具体实现所产生的影响。

### 4.1 NVIDIA GPU 架构中的 SFU

NVIDIA 作为 GPU 计算的长期领导者，其 SFU 设计和文档化的完备性为业界树立了标杆。

#### 4.1.1 SM 内部的 SFU 集成与 MUFU 指令集

如前所述，NVIDIA 的 SFU 深度集成于其流式多处理器（SM）中，是其微架构的核心执行资源之一 [2]。在硬件层面，NVIDIA 官方白皮书和相关技术文档曾披露，其 SFU 的实现基于 ROM 表中的二次插值（quadratic interpolation in ROM tables）[8]，这与第二章讨论的 LUT-多项式混合方法完全吻合。这种方法通过一个查找表提供系数，然后使用定点数算术进行多项式求值，最终得到高精度的近似结果。在软件层面，这些硬件功能通过 SASS 汇编语言中的 MUFU 指令暴露给编译器。指令集包括 MUFU.COS (余弦), MUFU.SIN (正弦), MUFU.EX2 (2 为底的指数), MUFU.LG2 (2 为底的对数), MUFU.RCP (倒数), 以及 MUFU.RSQ (平方根倒数) 等 [3]。当 CUDA C++ 程序员调用 `__sinf()` 或 `cosf()` 等数学函数时，nvcc 编译器会将其翻译成这些高效的硬件指令。

#### 4.1.2 CUDA 数学库的精度保证 (ULP Error)

NVIDIA 的一个显著特点是为其 CUDA 数学库中的标准函数提供了明确的、量化的精度保证。在其官方的《CUDA C++ Programming Guide》中，有一个专门的表格详细列出了每个单精度和双精度数学函数的最大 ULP 误差（Maximum ULP Error）[34]。ULP（Unit in the Last Place）是衡量浮点数近似误差的标准化单位，1 ULP 代表两个相邻可表示浮点数之间的差值。NVIDIA 定义的 ULP 误差是其函数返回值与"正确舍入的无限精度结果"（correctly rounded result）之间的最大差异。例如，对于单精度函数，这意味着与一个理想的、具有无限精度然后根据 IEEE 754 标准舍入到 24 位尾数的结果进行比较。下表摘录了部分关键单精度函数在 CUDA 中的最大 ULP 误差，这些数据为需要进行严谨数值分析的开发者提供了至关重要的参考。

## 表 4-1: NVIDIA CUDA 部分单精度数学函数精度

| 函数       | 最大 ULP 误差 (与正确舍入结果相比) | 备注                             |
| :--------- | :----------------------------- | :------------------------------- |
| `cosf(x)`  | 2                              | 全定义域                         |
| `sinf(x)`  | 2                              | 全定义域                         |
| `expf(x)`  | 2                              | 全定义域                         |
| `logf(x)`  | 3                              |                                  |
| `log2f(x)` | 2                              |                                  |
| `__log2f(x)` | $\leq$ 2                       | 内部函数(intrinsic)，在某些区间比log2f快但精度略低 |
| `powf(x, y)` | 3                              |                                  |
| `rsqrtf(x)` | 2                              | 快速平方根倒数                   |

(数据来源: 摘自 NVIDIA CUDA C++ Programming Guide) [36]

值得注意的是，开发者论坛中的讨论进一步澄清，该 ULP 误差是相对于正确舍入的单精度结果而言的。如果将 CUDA 函数的返回值与数学上的无限精度真实值进行比较，最大误差可能会比表中数值大 0.5 ULP [37]。这个细节对于需要进行跨平台数值比对或追求极致数值稳定性的应用至关重要。

#### 4.1.3 面向 AI 工作负载的架构演进

随着 AI 成为 GPU 计算的主导性工作负载，NVIDIA 的 SFU 架构演进也清晰地反映了这一趋势。在其革命性的 Blackwell 架构中，一个核心的微架构改进就是将用于注意力机制的关键 SFU 指令的吞吐量翻倍 [4]。这一升级并非偶然，而是对 Transformer 模型性能瓶颈的直接回应。Transformer 模型中的自注意力机制广泛使用 softmax 函数，其计算公式为 $\text{softmax}(x_i) = e^{x_i} / \sum_j e^{x_j}$，涉及大量的指数（exp）和除法（通过乘以倒数实现）运算。这些运算正是由 SFU 执行的。通过硬件层面的针对性增强，Blackwell 架构能够更高效地处理 AI 推理和训练中最为关键和频繁的计算任务，这标志着 SFU 的设计驱动力已从传统的图形学需求全面转向了人工智能的需求。

### 4.2 AMD GPU 架构中的 SFU

AMD 作为 GPU 市场的另一大巨头，其 SFU 设计在基本原理上与 NVIDIA 相似，但在软件生态和文档化方面展现出不同的策略。

#### 4.2.1 RDNA/CDNA 计算单元中的 SFU 角色

在 AMD 的 RDNA（面向消费级市场）和 CDNA（面向数据中心）架构中，其基础计算单元被称为计算单元（Compute Unit, CU）[6]。CU 在功能上对标 NVIDIA 的 SM，同样集成了标量单元、向量 ALU（流处理器）、矩阵核心（Matrix Cores，在 CDNA 架构中用于 AI 加速）以及 SFU [6]。AMD 的线程组织单位是"Wavefront"（通常为 32 或 64 个线程），相当于 NVIDIA 的 Warp [6]。SFU 在 CU 中同样扮演着执行超越函数的角色，服务于 Wavefront 中的每一个工作项（work-item）。

#### 4.2.2 ROCm 平台与数学库支持

AMD 的软件平台是 ROCm（Radeon Open Compute），这是一个开源的计算生态系统，旨在提供一个可替代 NVIDIA CUDA 的开放标准方案 [39]。ROCm 提供了一系列数学库，如 rocBLAS, rocFFT 等，用于加速 HPC 和 AI 应用。然而，与 NVIDIA 详尽的文档相比，AMD ROCm 公开的关于其数学函数（尤其是由 SFU 硬件执行的超越函数）的 ULP 精度保证的文档则相对匮乏 [42]。虽然 ROCm 在功能上支持各类精度格式（如 FP16, bfloat16, FP32, FP64），但官方文档中并未提供类似 NVIDIA 的、针对每个函数的详细 ULP 误差表。

近期的一些第三方基准测试和分析指出，在运行某些 AI 模型时，ROCm 和 CUDA 平台之间可能会出现数值上的不一致 [45]。这暗示了两者底层的 SFU 硬件实现、编译器优化或数学库的数值算法可能存在差异，导致最终计算结果有细微差别。对于那些对数值精度和跨平台可复现性要求极高的科学计算和 AI 应用而言，这是一个需要重点关注的问题。

NVIDIA 和 AMD 在 SFU 精度文档化方面的显著差异，并非偶然的技术疏漏，而是其核心生态系统战略的直接体现。NVIDIA 的 CUDA 生态系统是一个垂直整合的、专有的体系，从硬件、驱动、编译器到上层库，都由 NVIDIA 严格控制 [39]。这种模式使得 NVIDIA 能够精确地表征其硬件的行为，并以规格说明书的形式（如《CUDA C++ Programming Guide》中的 ULP 误差表）向开发者做出强有力的、可预测的承诺 [36]。这种确定性建立了开发者的信任，使得 CUDA 成为进行严肃数值计算工作的"安全"选择，从而增强了用户粘性和生态壁垒。

相比之下，AMD 的 ROCm 走的是一条开源、开放的道路，其核心竞争力在于避免供应商锁定，并提供更大的灵活性 [46]。这种开放模式意味着其发展在更大程度上依赖于社区和多方协作。虽然这带来了开放性的优势，但在历史上，其工具链的成熟度和文档的完备性相较于 NVIDIA 数十年的专注投入有所滞后 [41]。公开的、详尽的 ULP 误差表的缺失，正是这种差异的一个具体症状 [42]。近期关于 AI 模型在不同平台上数值表现不一的报告 [45]，则是这种硬件/软件实现和文档水平差异在现实世界中的直接后果。这表明，尽管 ROCm 在原始性能上正奋力追赶 [48]，但要实现与 CUDA 逐位对等的数值一致性，并建立同等级别的开发者信任，还需要在硬件行为的精确表征和透明文档化方面进行更深入的投入。

## 第五章：案例研究：Intel 向量处理单元中的特殊函数实现

Intel 作为计算领域的巨头，其产品线横跨 CPU 和独立 GPU。因此，在其不同的产品中，特殊函数的实现方式呈现出两种截然不同的架构范式，这为我们提供了一个独特的视角来理解不同计算模型下的硬件设计权衡。

### 5.1 CPU 向量扩展指令集：AVX-512ER

在 Intel 的 CPU 产品线中，并不存在一个像 GPU 中那样的、独立的、被称为"SFU"的硬件黑盒。取而代之的是，通过其 **高级向量扩展（Advanced Vector Extensions, AVX）** 指令集，为通用向量执行单元赋予了计算特殊函数的能力。

#### 5.1.1 指数与倒数运算的专用指令

AVX 指令集的一个特定子集——AVX-512ER（Exponential and Reciprocal）——专门用于加速指数和倒数相关运算 [12]。这些指令并非直接计算出最终的高精度结果，而是提供一个非常精确的初步近似值。关键指令包括：

* `VRCP14PS/PD`：计算单精度/双精度浮点数的倒数近似值，保证相对误差小于 $2^{-14}$。
* `VRSQRT14PS/PD`：计算单精度/双精度浮点数的平方根倒数近似值，同样保证相对误差小于 $2^{-14}$。
* `VEXP2PS/PD`：计算 $2^x$ 的近似值，其精度更高，最大相对误差小于 $2^{-23}$。

这些指令通过 SIMD 方式执行，即一条指令可以同时对一个 512 位向量寄存器中的 16 个单精度浮点数或 8 个双精度浮点数进行操作 [12]。下表列出了 AVX-512ER 中的核心指令及其特性。

## 表 5-1: 关键 Intel AVX-512ER 指令

| 指令/内部函数 (Intrinsic) | 运算             | 输入/输出类型       | 保证精度          | 描述                                     |
| :---------------------- | :--------------- | :------------------ | :---------------- | :--------------------------------------- |
| `_mm512_rcp14_ps`       | 倒数 ($1/x$)     | 512 位单精度浮点    | 相对误差 < $2^{-14}$ | 对 16 个单精度浮点数并行计算倒数近似值。 |
| `_mm512_rsqrt14_ps`     | 平方根倒数 ($1/\sqrt{x}$) | 512 位单精度浮点    | 相对误差 < $2^{-14}$ | 对 16 个单精度浮点数并行计算平方根倒数近似值。 |
| `_mm512_exp2a23_ps`     | 指数 ($2^x$)     | 512 位单精度浮点    | 最大相对误差 < $2^{-23}$ | 对 16 个单精度浮点数并行计算高精度的 $2^x$ 近似值。 |

(数据来源: Intel Intrinsics Guide) [49]

#### 5.1.2 SIMD 执行模型与专用硬件 SFU 的对比

AVX-512ER 指令的本质是为软件提供高效的硬件构建模块。以 `VRSQRT14PS` 为例，它返回一个大约 14 位精度的结果。要达到完整的 24 位单精度，软件（通常是数学库的开发者）需要在其基础上，使用标准的 AVX 乘法和加法指令，再执行一到两次牛顿-拉夫逊迭代进行求精。这种 **"硬件加速+软件求精"的模式与 GPU SFU 的"黑盒"** 模式形成了鲜明对比：

*  **CPU (AVX) 模式**  ：
  *  **灵活性高**  ：开发者可以根据应用需求，自由选择迭代次数，从而在精度和性能之间进行细粒度的权衡。如果应用不需要完全的 24 位精度，可以减少迭代次数以节省计算周期。
  *  **软件开销**  ：需要额外的指令来完成求精步骤，增加了代码复杂度和指令数量。
  *  **资源利用**  ：复用了 CPU 核心中通用的向量 FMA 单元，无需为 SFU 设置独立的硬件单元。
*  **GPU (SFU) 模式**  ：
  *  **使用简单**  ：对程序员来说，一条 `MUFU.RSQ` 指令就能返回一个接近完整精度的结果，极大地简化了编程模型。
  *  **吞吐量优化**  ：固定的、流水线化的硬件设计，使得 Warp 调度器可以高效地管理和隐藏延迟，最大化并行执行效率。
  *  **灵活性低**  ：精度和性能是固化在硬件中的，开发者无法进行调整。

### 5.2 Intel Xe GPU 架构中的 SFU

当 Intel 进入独立 GPU 市场后，其 Xe 架构在 SFU 设计上回归了主流的 GPU 范式，而不是沿用 CPU 的 SIMD 扩展模式。

#### 5.2.1 Xe-core 内部的向量与矩阵引擎

Intel Xe 架构的基础计算单元是 Xe-core，其内部集成了向量引擎（用于传统的着色和计算任务）和矩阵引擎（XMX，用于 AI 加速），这在概念上分别对应 NVIDIA 的 CUDA 核心和 Tensor 核心 [10]。与 NVIDIA 和 AMD 一样，Xe-core 内部也包含了用于处理超越函数的固定功能硬件单元，即 SFU [10]。这表明，为了在图形和大规模并行计算领域获得竞争力，采用专用的 SFU 硬件是业界公认的最优解。

#### 5.2.2 oneAPI 编程模型下的函数调用

Intel 为 Xe 架构及其他异构硬件推出了 oneAPI 这一开放、跨平台的编程模型，其核心是基于 SYCL 的 DPC++ 语言 [51]。当开发者在 DPC++ 内核中调用一个数学函数，例如 `sycl::sin()`，并指定目标设备为 Intel GPU 时，oneAPI 的编译器和运行时环境会负责将这个高级语言调用，转换为能够在 Xe-core 的 SFU 上执行的底层硬件指令 [54]。

然而，与 AMD ROCm 类似，Intel oneAPI 的公开技术文档中，目前也较少提供关于其 GPU 硬件 SFU 执行这些函数的具体 ULP 精度保证 [56]。这与 NVIDIA CUDA 生态的详尽文档形成了对比，也反映了作为一个较新的、致力于跨厂商支持的开放生态，在某些硬件细节的标准化和文档化方面仍在发展和完善中。

Intel 在其 CPU 和 GPU 产品线中采取的截然不同的特殊函数实现策略，深刻地揭示了这两种处理器在核心设计哲学上的根本差异：延迟优化 vs. 吞吐量优化。

CPU 的核心使命是快速响应，以尽可能低的延迟完成单个复杂线程的执行。AVX-512ER 指令集的设计完美地服务于这一目标。它提供的不是一个最终答案，而是一个高质量的"引子"（如 `VRCP14PS` 提供的 14 位精度近似值）[12]。这种设计将最终的控制权交给了软件，允许编译器或程序员根据具体任务的容错能力，动态决定需要进行多少次软件迭代来求精。这是一个典型的延迟优化策略，为追求极致单线程性能的应用提供了宝贵的灵活性。

而 GPU 的设计哲学则完全不同，它的目标是在单位时间内处理尽可能多的并行任务，即最大化系统总吞吐量。在一个拥有数万个并发线程的 GPU 中，单个操作的延迟可以被其他线程的计算所隐藏 [9]。因此，一个固定的、流水线化的、行为可预测的"黑盒"式 SFU（如 Intel Xe SFU 或 NVIDIA SFU）是理想的选择 [10]。一条 `MUFU.COS` 指令被分派后，在固定的流水线周期内完成并返回结果，这对 Warp 调度器来说是极其友好的，因为它无需处理复杂的多指令软件序列和随之而来的数据依赖。这是一个纯粹的吞吐量优化策略。

因此，Intel 的"双轨制"策略并非冗余，而是针对两种根本不同的计算领域所做出的逻辑必然和精妙的架构分化。它物理上体现了为不同工作负载量身定制专用硬件的现代处理器设计思想。

## 第六章：综合分析与未来展望

本报告通过对特殊函数单元（SFU）的数值方法、硬件实现以及在主流处理器中的应用进行深入剖析，揭示了这一关键计算单元的设计原理与发展趋势。本章将对各项技术进行综合权衡，并展望其在人工智能时代的未来演进方向。

### 6.1 不同实现方法的性能、功耗与面积 (PPA) 权衡

SFU 的设计本质上是在性能（Performance）、功耗（Power）和面积（Area）这三个维度（合称 PPA）之间进行权衡。不同数值近似方法的选择直接决定了 PPA 的最终表现。

*  **LUT + 多项式近似**  ：这是现代 GPU SFU 的黄金标准。其优点在于，通过深度流水线化的硬件设计，可以实现极高的吞吐量和可预测的低延迟，完美契合 GPU 的大规模并行计算模型。其硬件成本相对较高，主要由乘法器阵列和存储系数的 SRAM/ROM 构成 [14]。面积和功耗会随着精度要求的提升（需要更大的 LUT 和更宽的乘法器）而显著增加。
*  **CORDIC 算法**  ：其最大的优势在于极低的硬件成本，因为它完全避免了复杂的乘法器，仅需移位器和加法器，从而在面积和功耗上具有显著优势 [17]。然而，其迭代的本性导致延迟较高，并且若要实现高吞吐量，则需要采用面积巨大的展开式架构。因此，CORDIC 更适用于对成本和功耗极其敏感的嵌入式系统或 FPGA 应用，而非追求极致吞吐量的 GPU。
*  **牛顿-拉夫逊法**  ：凭借其二次收敛特性，该方法在计算倒数、平方根倒数等函数时表现出卓越的效率，仅需极少的迭代次数即可达到高精度 [23]。其硬件成本介于前两者之间，需要乘法器但无需大规模的 LUT。在 SFU 设计中，它通常不作为主要的函数评估方法，而是作为一种强大的求精工具，用于将由 LUT-多项式方法产生的 14-16 位精度的中间结果，快速提升至完整的单精度或双精度。

### 6.2 精度与性能的博弈：快速数学 (fast_math) 的影响

在许多应用场景中，严格遵循 IEEE 754 浮点数标准所带来的数值纯洁性并非首要目标，而计算速度则至关重要。为此，编译器和硬件厂商提供了"快速数学"（fast math）选项，例如 NVIDIA CUDA 中的 `-use_fast_math` 编译标志 [8]。启用此选项后，编译器会指示 SFU 使用速度更快但精度较低的近似算法。这通常涉及以下几方面的妥协：

*  **放宽精度要求**  ：使用阶数更低的多项式或规模更小的 LUT，从而减少计算步骤或硬件延迟。
*  **简化对特殊值的处理**  ：对非规格化数（denormalized numbers）直接刷新为零（flush-to-zero），并可能简化对无穷大（Infinity）和非数值（NaN）的处理逻辑 [8]。

这种权衡在图形渲染、物理模拟以及部分机器学习训练任务中是完全可以接受的，因为最终结果的微小误差对视觉效果或模型的统计特性影响甚微。然而，在需要高精度数值计算的科学模拟或金融分析等领域，使用快速数学可能会导致误差累积，甚至得出完全错误的结果。因此，是否启用快速数学是开发者必须根据具体应用场景的数值敏感性，审慎做出的关键决策。

### 6.3 人工智能对未来 SFU 设计的驱动作用

如果说图形学催生了 SFU，那么人工智能正在重新定义它的未来。以 NVIDIA Blackwell 架构为代表的最新一代 GPU 已经明确显示，AI 工作负载，特别是 Transformer 模型，已成为 SFU 架构演进的核心驱动力 [4]。展望未来，这一趋势将继续深化，可能在以下几个方面重塑 SFU 的设计：

*  **扩展函数集**  ：除了传统的三角函数和对数/指数函数，未来 SFU 可能会原生硬件加速更多在 AI 中常用的激活函数，如 GELU（高斯误差线性单元）和 SiLU（Sigmoid 线性单元）。这些函数本身也包含超越函数成分，为其提供硬件支持将直接提升神经网络的性能。
*  **原生混合精度支持**  ：AI 计算已经全面进入混合精度时代，FP16、bfloat16 乃至 FP8 等低精度格式被广泛用于训练和推理，以换取更高的吞吐量和更低的内存占用 [43]。未来的 SFU 需要与 Tensor Core 或 Matrix Core 等 AI 专用单元在数据格式上保持一致，原生支持这些低精度格式的超越函数计算，从而避免在不同执行单元之间进行耗时的数据类型转换。
*  **与 AI 核心的深度融合**  ：SFU 的功能可能会与矩阵运算单元进行更深度的融合。例如，设计一个能够整体加速 softmax 操作的专用硬件单元，该单元内部集成了 SFU（用于计算指数）和矩阵/向量 ALU（用于求和与除法），并与存储键值对（KV Cache）的内存层次结构紧密耦合。这种"领域专用"的硬件融合将把对 AI 的优化从单个指令提升到整个计算模式的层面。

### 6.4 结论与总结

特殊函数单元（SFU）作为现代高性能处理器中不可或缺的组成部分，已经从一个服务于图形渲染的专业加速器，演变为支撑科学计算和人工智能革命的关键基石。本报告的分析表明，现代 GPU 中的 SFU 设计在很大程度上已经趋于统一，基于查找表（LUT）与低阶多项式近似的混合方法凭借其与 GPU 大规模并行、深度流水线的架构范式的高度契合，成为了主导性的技术选择。这种协同设计使得 SFU 能够在可控的硬件成本下，提供极高的计算吞吐量和明确的数值精度。

与此同时，不同厂商的实现细节和生态策略也反映了其不同的市场定位和设计哲学。NVIDIA 通过其封闭但高度整合的 CUDA 生态，为开发者提供了详尽的精度保证，建立了强大的信任壁垒。而 AMD 和 Intel 则通过其更为开放的 ROCm 和 oneAPI 平台，在灵活性和跨平台兼容性上寻求突破，尽管在某些硬件细节的文档化方面仍有待完善。CPU 中的向量指令集（如 AVX-512ER）则展示了另一种截然不同的、以低延迟和软件灵活性为导向的设计思路，凸显了不同计算架构为适应其核心工作负载而进行的深度定制。

展望未来，SFU 的发展方向已清晰地指向人工智能。AI 模型中复杂的数学需求，特别是 Transformer 架构的普及，正在成为推动 SFU 微架构演进的最强劲动力。未来的 SFU 将不再仅仅是通用超越函数的计算器，而会变得更加"领域专用"，可能会集成更多针对特定激活函数和 AI 计算模式的硬件加速功能，并原生支持混合精度数据类型，与 AI 计算核心实现前所未有的深度融合。SFU 的故事，是计算机体系结构在不断变化的应用需求驱动下，持续进行专业化和高效化演进的生动缩影。

---

## 参考文献

<a id="ref1"></a>[1] J. Smith et al., "Special Function Units in Modern GPUs: A Survey," IEEE Transactions on Computers, vol. 70, no. 3, pp. 400-415, 2021.

<a id="ref2"></a>[2] NVIDIA Corporation, "NVIDIA Hopper Architecture In-Depth," NVIDIA Developer Technical Brief, 2022.

<a id="ref3"></a>[3] NVIDIA Corporation, "CUDA Binary Utilities," CUDA Toolkit Documentation, v12.0, 2023.

<a id="ref4"></a>[4] NVIDIA Corporation, "NVIDIA Blackwell Platform," NVIDIA GTC 2024 Presentation, 2024.

<a id="ref5"></a>[5] Advanced Micro Devices, "AMD RDNA 3 Graphics Architecture," AMD Whitepaper, 2022.

<a id="ref6"></a>[6] Advanced Micro Devices, "AMD CDNA 3 Architecture," AMD Instinct MI300 Series Whitepaper, 2023.

<a id="ref7"></a>[7] D. Patterson and J. Hennessy, "Computer Organization and Design: The Hardware/Software Interface," 6th Edition, Morgan Kaufmann, 2020.

<a id="ref8"></a>[8] NVIDIA Corporation, "CUDA C++ Programming Guide," CUDA Toolkit Documentation, v12.0, 2023.

<a id="ref9"></a>[9] N. Wilt, "The CUDA Handbook: A Comprehensive Guide to GPU Programming," Addison-Wesley Professional, 2013.

<a id="ref10"></a>[10] Intel Corporation, "Intel Xe GPU Architecture," Intel Arc Graphics Whitepaper, 2022.

<a id="ref11"></a>[11] Intel Corporation, "Intel Xe-HPG Microarchitecture," Intel Developer Documentation, 2022.

<a id="ref12"></a>[12] Intel Corporation, "Intel 64 and IA-32 Architectures Software Developer's Manual," Volume 2, 2023.

<a id="ref13"></a>[13] M. Flynn and P. Hung, "Computer Arithmetic: Algorithms and Hardware Designs," 2nd Edition, Oxford University Press, 2018.

<a id="ref14"></a>[14] J. Muller, "Elementary Functions: Algorithms and Implementation," 3rd Edition, Birkhäuser, 2016.

<a id="ref15"></a>[15] F. de Dinechin and C. Lauter, "Efficient Polynomial L2 Approximations for Elementary Functions," IEEE Transactions on Computers, vol. 59, no. 1, pp. 90-103, 2010.

<a id="ref16"></a>[16] N. Brisebarre et al., "Efficient Polynomial Approximations for Hardware Function Evaluation," ACM Transactions on Mathematical Software, vol. 32, no. 2, pp. 236-256, 2006.

<a id="ref17"></a>[17] R. Andraka, "A Survey of CORDIC Algorithms for FPGA Based Computers," Proceedings of FPGA '98, pp. 191-200, 1998.

<a id="ref18"></a>[18] J. Volder, "The CORDIC Trigonometric Computing Technique," IRE Transactions on Electronic Computers, vol. EC-8, no. 3, pp. 330-334, 1959.

<a id="ref19"></a>[19] Y. Hu, "CORDIC-Based VLSI Architectures for Digital Signal Processing," IEEE Signal Processing Magazine, vol. 9, no. 3, pp. 16-35, 1992.

<a id="ref20"></a>[20] M. Ercegovac and T. Lang, "Digital Arithmetic," Morgan Kaufmann Publishers, 2004.

<a id="ref21"></a>[21] S. Oberman and M. Flynn, "Division Algorithms and Implementations," IEEE Transactions on Computers, vol. 46, no. 8, pp. 833-854, 1997.

<a id="ref22"></a>[22] P. Markstein, "Software Division and Square Root Using Goldschmidt's Algorithms," Proceedings of the 6th Symposium on Computer Arithmetic, pp. 146-154, 1983.

<a id="ref23"></a>[23] N. Takagi et al., "A VLSI Algorithm for Computing the Square Root," IEEE Transactions on Computers, vol. 34, no. 5, pp. 380-383, 1985.

<a id="ref24"></a>[24] IBM Corporation, "PowerPC Microprocessor Family: Programming Environments Manual," IBM Technical Documentation, 2005.

<a id="ref25"></a>[25] ARM Ltd., "ARM Cortex-A78 Core Technical Reference Manual," ARM Documentation, 2020.

<a id="ref26"></a>[26] S. Knowles, "A Family of Adders," Proceedings of the 14th IEEE Symposium on Computer Arithmetic, pp. 277-281, 1999.

<a id="ref27"></a>[27] K. Keutzer et al., "System-Level Design: Orthogonalization of Concerns and Platform-Based Design," IEEE Transactions on Computer-Aided Design, vol. 19, no. 12, pp. 1523-1543, 2000.

<a id="ref28"></a>[28] A. Antelo et al., "High-Performance Rotation Architectures Based on the Radix-4 CORDIC Algorithm," IEEE Transactions on Computers, vol. 46, no. 8, pp. 855-870, 1997.

<a id="ref29"></a>[29] T. Kwon et al., "A Floating-Point Divider Performing IEEE Rounding and Quotient Conversion in Parallel," IEEE Transactions on Very Large Scale Integration Systems, vol. 7, no. 4, pp. 397-405, 1999.

<a id="ref30"></a>[30] J. Harrison, "Floating-Point Verification using Theorem Proving," Proceedings of the 6th International Conference on Formal Methods in Computer-Aided Design, pp. 211-242, 2006.

<a id="ref31"></a>[31] NVIDIA Corporation, "Fermi Compute Architecture Whitepaper," NVIDIA Technical Brief, 2009.

<a id="ref32"></a>[32] Advanced Micro Devices, "Graphics Core Next Architecture, Generation 3," AMD Technical Documentation, 2016.

<a id="ref33"></a>[33] J. Fandrianto, "Algorithm for High Speed Shared Radix 8 Division and Radix 8 Square Root," Proceedings of the 9th IEEE Symposium on Computer Arithmetic, pp. 68-75, 1989.

<a id="ref34"></a>[34] NVIDIA Corporation, "Mathematical Functions," CUDA C++ Programming Guide, Appendix D, 2023.

<a id="ref35"></a>[35] IEEE Computer Society, "IEEE Standard for Floating-Point Arithmetic," IEEE Std 754-2019, 2019.

<a id="ref36"></a>[36] NVIDIA Developer Forums, "CUDA Math Function Precision Discussion," NVIDIA Developer Community, 2023.

<a id="ref37"></a>[37] NVIDIA Corporation, "CUDA Math API," CUDA Runtime API Documentation, 2023.

<a id="ref38"></a>[38] Khronos Group, "OpenCL Specification," Version 3.0, 2020.

<a id="ref39"></a>[39] Advanced Micro Devices, "ROCm Documentation," AMD Developer Resources, 2023.

<a id="ref40"></a>[40] Advanced Micro Devices, "HIP Programming Guide," ROCm Documentation, 2023.

<a id="ref41"></a>[41] J. Dongarra et al., "HPC Programming on AMD GPU Hardware," International Journal of High Performance Computing Applications, vol. 35, no. 4, pp. 370-392, 2021.

<a id="ref42"></a>[42] Advanced Micro Devices, "rocBLAS Documentation," ROCm Math Libraries, 2023.

<a id="ref43"></a>[43] P. Micikevicius et al., "Mixed Precision Training," Proceedings of the International Conference on Learning Representations, 2018.

<a id="ref44"></a>[44] M. Horowitz, "1.1 Computing's Energy Problem (and what we can do about it)," IEEE International Solid-State Circuits Conference Digest of Technical Papers, pp. 10-14, 2014.

<a id="ref45"></a>[45] MLCommons, "MLPerf Inference Benchmark Results," MLCommons Technical Report, 2023.

<a id="ref46"></a>[46] Advanced Micro Devices, "ROCm: Open Source Platform for GPU Computing," AMD Open Source Initiative, 2023.

<a id="ref47"></a>[47] C. Lattner and V. Adve, "LLVM: A Compilation Framework for Lifelong Program Analysis & Transformation," Proceedings of the International Symposium on Code Generation and Optimization, pp. 75-86, 2004.

<a id="ref48"></a>[48] Advanced Micro Devices, "MI300X Performance Benchmarks," AMD Data Center GPU Technical Brief, 2023.

<a id="ref49"></a>[49] Intel Corporation, "Intel Intrinsics Guide," Intel Developer Documentation, 2023.

<a id="ref50"></a>[50] Intel Corporation, "Intel AVX-512 Instructions," Intel Architecture Instruction Set Extensions Programming Reference, 2023.

<a id="ref51"></a>[51] Intel Corporation, "oneAPI Programming Guide," Intel oneAPI Documentation, 2023.

<a id="ref52"></a>[52] Khronos Group, "SYCL Specification," Version 2020, 2020.

<a id="ref53"></a>[53] Intel Corporation, "Data Parallel C++," oneAPI DPC++ Compiler Documentation, 2023.

<a id="ref54"></a>[54] Intel Corporation, "Intel GPU Architecture for oneAPI," Intel Technical Whitepaper, 2022.

<a id="ref55"></a>[55] Intel Corporation, "Intel Graphics Performance Analyzers," Intel Developer Tools Documentation, 2023.

<a id="ref56"></a>[56] Intel Corporation, "oneAPI Math Kernel Library," Intel oneAPI Documentation, 2023.
