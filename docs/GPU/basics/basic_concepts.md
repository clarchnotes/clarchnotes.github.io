# GPU基本概念：从零开始理解GPU并行计算

## 图形处理器(GPU)简介

GPU最初设计用于处理图形渲染，但现在广泛应用于各种并行计算任务。与CPU相比，GPU采用了根本不同的设计理念：CPU优化了串行代码的执行延迟，而GPU优化了大规模并行任务的吞吐量。

### GPU与CPU对比
| 特性 | CPU | GPU |
|------|-----|-----|
| 核心数量 | 少量（通常4-64个） | 大量（数百到数千个） |
| 核心设计 | 复杂，支持乱序执行 | 简单，更多计算单元 |
| 缓存大小 | 大（MB级别） | 小（KB级别） |
| 优化目标 | 低延迟 | 高吞吐量 |
| 分支预测 | 先进 | 有限 |
| 指令流 | 多样化 | 统一（SIMT模型） |

这种设计差异使GPU特别适合于大量数据的并行处理任务，如矩阵运算、图像处理和深度学习。

## 基本硬件组件

### CUDA核心(CUDA Core)
CUDA核心是NVIDIA GPU的基本计算单元，主要负责执行标量算术指令。

**详细特性**：
- 执行标量算术指令（整数和浮点数运算）
- 每个CUDA核心包含算术逻辑单元(ALU)和浮点单元(FPU)
- 不同GPU架构的CUDA核心可能有不同组合的32位整数单元、32位和64位浮点单元
- 与CPU核心不同，CUDA核心不是独立调度的，而是以线程束为单位被调度
- H100 GPU的每个SM包含128个"FP32 CUDA核心"，但仅有64个32位整数或64位浮点单元

**与CPU核心的区别**：
CPU核心是复杂的独立执行单元，包含分支预测、乱序执行等高级功能；而CUDA核心更像是简单的"管道"，专注于高吞吐量的计算。

### 张量核心(Tensor Core)
张量核心是NVIDIA在Volta架构中引入的专用硬件单元，专为加速深度学习等应用中的矩阵运算而设计。

**详细特性**：
- 执行矩阵乘加运算：D = A × B + C
- 一次运算可处理4×4矩阵
- 与CUDA核心相比，数量较少但处理能力更强
- 最新架构支持多种精度：FP16、BF16、FP32、FP64以及INT8和INT4
- Hopper架构的张量核心每秒可执行高达1000万亿次FP8运算

**应用场景**：
- 深度学习训练和推理
- 科学计算中的大规模矩阵运算
- 计算机视觉和自然语言处理

### 特殊功能单元(SFU - Special Function Unit)
特殊功能单元执行复杂的数学运算，如三角函数、指数和对数。

**功能**：
- 计算sin、cos、exp、log等超越函数
- 每个SM包含多个SFU
- 相比基本算术运算，这些函数执行时间较长

### 加载/存储单元(LSU - Load/Store Unit)
负责从全局内存加载数据到寄存器或从寄存器存储数据到内存。

**特性**：
- 处理内存访问请求
- 支持合并内存访问
- 对内存访问模式高度敏感

### 流多处理器(SM - Streaming Multiprocessor)
SM是NVIDIA GPU的主要计算单元，包含多种执行资源。

**详细组成**：
- 多个CUDA核心
- 张量核心
- 特殊功能单元(SFU)
- 加载/存储单元(LSU)
- 线程束调度器
- 寄存器文件
- L1缓存/共享内存
- 纹理单元

**资源分配**：
- SM是资源分配的基本单位
- 线程块被分配到单个SM执行
- 每个SM可以同时处理多个线程块
- 资源限制（寄存器、共享内存等）决定了SM可同时执行的线程块数量

**执行模型**：
- SM采用SIMT执行模型
- 以线程束为单位进行调度
- 使用零开销线程切换实现延迟隐藏

### GPU架构版本
NVIDIA GPU架构随时间不断演进，每代架构都引入新功能和性能改进。

**主要架构世代**：
1. **Tesla** (2006-2010)：首个统一着色器架构
2. **Fermi** (2010)：首个支持CUDA的架构，引入了真正的L1/L2缓存层次
3. **Kepler** (2012)：动态并行性，Hyper-Q技术
4. **Maxwell** (2014)：更高能效，改进的调度器
5. **Pascal** (2016)：HBM2内存，支持半精度(FP16)
6. **Volta** (2017)：引入张量核心，独立线程调度
7. **Turing** (2018)：增加了RT核心用于光线追踪
8. **Ampere** (2020)：第三代张量核心，更大的L2缓存
9. **Hopper** (2022)：第四代张量核心，Transformer引擎
10. **Ada Lovelace** (2022)：改进的光线追踪，DLSS 3.0

**计算能力(Compute Capability)**：
- 用数字标识GPU架构特性的版本系统
- 由主版本号和次版本号组成（如7.5, 8.6）
- 决定了GPU支持的CUDA功能
- 主版本号通常对应架构系列，但也有例外（如Ada使用8.9，与Ampere共享主版本号8）

## CUDA编程模型详解

![](attachments/Pasted%20image%2020250510231257.png)
### 线程(Thread)
线程是CUDA编程模型中的基本执行单元，类似于传统CPU编程中的线程概念，但更轻量级。

**详细特性**：
- 执行单个指令序列
- 每个线程有唯一的线程ID，可用于确定其处理的数据
- 拥有私有寄存器状态
- 线程执行SASS（Streaming ASSembler）或PTX（Parallel Thread eXecution）代码
- 相比CPU线程，GPU线程更轻量，切换开销极低
- 可以有独立的指令指针/程序计数器，但出于性能考虑，通常线程束内的线程共享同一指令指针

**线程标识**：
在CUDA编程中，线程有三维索引：
```cuda
// 在核函数中获取线程索引
int x = threadIdx.x;
int y = threadIdx.y;
int z = threadIdx.z;
```

**线程私有内存**：
- 寄存器：直接分配给线程的快速存储
- 局部内存：当寄存器不足时，会将变量溢出到局部内存（实际位于全局内存，访问较慢）

### 线程束(Warp)
线程束是GPU执行的实际单位，由32个线程组成（在所有当前NVIDIA GPU上）。

**详细特性**：
- 32个线程作为一组执行相同的指令
- 线程束内的线程在物理上并行执行
- 线程束调度是硬件层面的实现细节，对CUDA编程者来说通常是透明的
- 当线程束中不同线程需要执行不同指令路径时发生"线程分化"(thread divergence)
- 线程分化导致某些线程被掩码禁用，降低执行效率

**线程分化示例**：
```cuda
if (threadIdx.x % 2 == 0) {
    // 偶数线程执行的代码
    result = a + b;
} else {
    // 奇数线程执行的代码
    result = a * b;
}
```
在这个例子中，线程束中的线程会分成两组执行不同指令，实际执行时间接近于两组指令时间之和。

**线程束同步**：
- 线程束内线程具有隐式同步性
- 特殊的线程束级别原语可用于线程束内通信：
  ```cuda
  // 线程束内的整数相加规约
  sum = __reduce_add_sync(0xffffffff, value);
  
  // 线程束内广播
  data = __shfl_sync(0xffffffff, value, sourceThreadIdx);
  ```

**线程束执行模式**：
1. **锁步执行**：线程束中所有线程执行相同指令
2. **独立线程调度**：在Volta架构及更新的GPU上，线程可以在某些情况下独立执行

### 线程块(Block)/协作线程阵列(CTA)
线程块是一组协作线程，可以同步并通过共享内存进行通信。在硬件实现上，线程块也被称为协作线程阵列(CTA)。

**详细特性**：
- 包含多个线程（最多1024个线程，根据计算能力可能有所不同）
- 同一块内的线程被调度到同一个SM上执行
- 块内线程可以通过共享内存和同步原语进行协作
- 块大小通常是线程束大小(32)的倍数，以避免部分填充的线程束
- 块可以是一维、二维或三维组织的

**线程块标识**：
```cuda
// 线程块内的线程标识
int tid = threadIdx.x + blockDim.x * threadIdx.y + blockDim.x * blockDim.y * threadIdx.z;

// 线程块在网格中的位置
int bid = blockIdx.x + gridDim.x * blockIdx.y + gridDim.x * gridDim.y * blockIdx.z;
```

**同步操作**：
```cuda
// 块内所有线程同步
__syncthreads();

// 块内线程同步并等待谓词为真
__syncthreads_and(predicate);

// 块内线程同步并计算谓词逻辑或
__syncthreads_or(predicate);
```

**块大小考虑因素**：
- SM的最大线程数限制
- 寄存器使用量
- 共享内存需求
- 线程束大小（通常为32的倍数以避免线程束部分填充）
- 工作量分配平衡

### 网格(Grid)

![](attachments/Pasted%20image%2020250510231736.png)
网格是线程块的集合，组成一个完整的并行任务。

**详细特性**：
- 可以包含数百万个线程（通过多个线程块）
- 网格通常对应一个内核函数调用
- 可以是一维、二维或三维组织
- 网格尺寸通常基于输入数据大小决定

**网格配置示例**：
```cuda
// 定义线程块和网格维度
dim3 blockDim(16, 16);  // 每个块包含16×16=256个线程
dim3 gridDim((width + blockDim.x - 1) / blockDim.x, 
            (height + blockDim.y - 1) / blockDim.y);

// 启动内核
myKernel<<<gridDim, blockDim>>>(args...);
```

**网格跨步循环**：
处理超出网格大小的数据：
```cuda
// 处理比网格大的数据集
int idx = blockIdx.x * blockDim.x + threadIdx.x;
int stride = blockDim.x * gridDim.x;
for (int i = idx; i < dataSize; i += stride) {
    // 处理数据[i]
}
```

### 内核函数(Kernel)
内核函数是在GPU上执行的并行函数，由成千上万个线程并行执行。

**特性**：
- 用`__global__`关键字声明
- 通过`<<<网格大小, 块大小>>>`语法启动
- 返回值必须是void
- 可以访问多种内存空间

**内核函数示例**：
```cuda
// 向量加法内核
__global__ void vectorAdd(float* A, float* B, float* C, int N) {
    int i = blockDim.x * blockIdx.x + threadIdx.x;
    if (i < N) {
        C[i] = A[i] + B[i];
    }
}

// 调用内核
int threadsPerBlock = 256;
int blocksPerGrid = (N + threadsPerBlock - 1) / threadsPerBlock;
vectorAdd<<<blocksPerGrid, threadsPerBlock>>>(A, B, C, N);
```

## 调度与执行详解

### 线程束调度器(Warp Scheduler)
线程束调度器负责选择就绪的线程束并发出指令执行。

**详细功能**：
- 每个SM有多个线程束调度器（现代GPU通常每个SM有4个）
- 在可用线程束中选择一个发射指令
- 实现"零开销线程切换"，隐藏指令和内存延迟
- 使用记分板(scoreboarding)跟踪寄存器依赖关系
- 根据操作数就绪情况选择可发射的线程束

**延迟隐藏机制**：
1. 当一个线程束等待内存访问或长延迟指令完成时
2. 调度器切换到另一个就绪的线程束
3. 由于线程束数量多，通常总有线程束可执行
4. 这种机制使GPU能够隐藏长延迟操作的影响

**指令吞吐量**：
不同指令的执行速度不同：
- 整数和单精度浮点运算：~1个周期
- 双精度浮点运算：~2个周期
- 特殊函数(sin, exp等)：~20-30个周期
- 全局内存访问：~200-400个周期

### SIMT执行模型
单指令多线程(SIMT)是GPU的基本执行模型，类似于SIMD但更灵活。

**详细特性**：
- 线程束中的32个线程同时执行相同指令
- 每个线程处理不同的数据元素
- 通过"执行掩码"(execution mask)控制哪些线程参与当前指令执行
- 允许线程有条件地执行不同路径，但会导致性能下降

**与SIMD对比**：
- SIMD(单指令多数据)：所有通道必须执行相同指令
- SIMT：允许线程条件性地执行，使编程更灵活

**分支效率**：
```cuda
// 高效代码：线程束内执行路径一致
if (data[i] > threshold) {
    result[i] = process(data[i]);
}

// 低效代码：引起线程分化
if (threadIdx.x % 3 == 0) {
    // 只有部分线程执行
}
```

**指令流水线**：
- 指令解码
- 操作数读取
- 执行
- 写回结果
- 流水线深度随GPU架构而异

## 内存层次结构详解

GPU具有复杂的内存层次结构，了解各类内存的特性对优化GPU程序至关重要。

### 寄存器(Registers)
寄存器是每个线程的私有存储，访问速度最快。

**详细特性**：
- 每个线程最多可以使用255个32位寄存器（依架构而异）
- 访问延迟：约0-1个时钟周期
- 没有真正的"寄存器溢出"，而是编译器将超出限制的变量放入局部内存
- 通过`-maxrregcount=N`编译选项限制每线程寄存器使用量
- 寄存器分配在线程块级别进行，影响SM可同时执行的线程块数量

**寄存器压力**：
- 当内核使用过多寄存器时会限制SM的占用率
- 高寄存器使用量减少可并发执行的线程数
- 需要在寄存器使用和重计算之间权衡

### 共享内存(Shared Memory)
共享内存允许同一线程块中的线程进行快速通信和数据共享。

**详细特性**：
- 位于芯片上，访问速度接近寄存器
- 延迟：约20-30个时钟周期（无bank冲突时）
- 每个SM有限量共享内存（48KB-164KB，依架构而异）
- 需要手动管理：分配、加载、存储和同步
- 组织为多个bank（通常32个）以支持并行访问
- 发生bank冲突时性能会下降

**共享内存声明和使用**：
```cuda
__global__ void sharedMemExample(float* input, float* output, int n) {
    // 声明共享内存数组
    __shared__ float sharedData[256];
    
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    
    // 从全局内存加载到共享内存
    if (idx < n) {
        sharedData[threadIdx.x] = input[idx];
    }
    
    // 确保所有数据都已加载到共享内存
    __syncthreads();
    
    // 使用共享内存中的数据
    if (idx < n) {
        float result = 0;
        // 访问线程块内其他线程加载的数据
        for (int i = 0; i < blockDim.x; i++) {
            result += sharedData[i];
        }
        output[idx] = result;
    }
}
```

**常见用途**：
- 数据重用：加载一次，多次使用
- 线程协作：线程间共享中间结果
- 减少全局内存访问：预先加载输入数据
- 实现规约(reduction)、扫描(scan)等并行算法

**性能优化**：
- 避免bank冲突
- 合理划分共享内存大小
- 控制共享内存使用量以维持足够的线程块并发度

### L1/L2缓存
现代GPU具有多级缓存系统，帮助减少全局内存访问延迟。

**L1缓存**：
- 每个SM私有
- 与共享内存共享物理空间
- 可配置L1缓存和共享内存的比例（架构相关）
- 用于缓存局部和全局内存访问
- 延迟：30-50个时钟周期

**L2缓存**：
- 所有SM共享
- 缓存全局内存访问
- 大小：几MB（取决于GPU型号）
- 延迟：约200个时钟周期

**缓存行为**：
- 通过`__ldg()`函数提示数据只读，优先使用缓存
- 原子操作和写入通常会绕过L1缓存
- 缓存命中率对性能影响显著

### 全局内存(Global Memory)
全局内存是GPU上最大的内存空间，可被所有线程访问，但也是访问延迟最高的。

**详细特性**：
- 容量：几GB到几十GB（取决于GPU型号）
- 带宽：数百GB/s（高端GPU可达1-2TB/s）
- 延迟：400-800个时钟周期
- 持久存在于整个应用程序生命周期
- 主机(CPU)和设备(GPU)都可以访问(通过CUDA API)

**全局内存声明**：
```cuda
// 主机代码
float* d_data;
cudaMalloc(&d_data, size);
cudaMemcpy(d_data, h_data, size, cudaMemcpyHostToDevice);

// 内核访问
__global__ void kernel(float* data) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    float value = data[idx];  // 全局内存读取
    data[idx] = value * 2;    // 全局内存写入
}
```

**合并访问**：
- 当线程束中的线程访问连续内存位置时，会合并为更少的内存事务
- 理想情况：32个线程访问128字节连续区域，只需1个事务
- 最坏情况：32个线程访问32个随机位置，需要32个事务

**优化策略**：
- 确保对齐和合并访问
- 使用向量类型（float4、int2等）
- 使用纹理和表面内存访问特殊数据
- 通过共享内存缓冲减少随机访问

### 常量内存(Constant Memory)
常量内存是专用的只读缓存，对所有线程可见。

**特性**：
- 总大小64KB
- 具有专用缓存
- 适合所有线程读取相同位置的数据
- 声明：`__constant__ float params[64];`

### 纹理内存(Texture Memory)
纹理内存是专门为图形应用优化的内存空间，具有特殊的缓存和寻址模式。

**特性**：
- 二维局部性优化
- 内置插值和边界处理
- 适合处理图像数据
- 缓存针对2D空间局部性优化

## 资源限制与占用率

GPU执行效率受到各种资源限制和占用率的影响。

### 资源限制
**每个SM的资源限制**：
- 最大线程数：每个SM 1024-2048个（架构相关）
- 最大线程块数：每个SM 16-32个
- 寄存器文件大小：SM共享，每个SM 64K-256K个寄存器
- 共享内存：每个SM 48KB-164KB（架构相关）
- 线程束槽位：每个SM最多可分配给64个活跃线程束

**如何计算最大线程块数**：
最大线程块数取决于多种限制因素：
1. 基于寄存器使用量：`总寄存器数 ÷ (每线程寄存器数 × 每块线程数)`
2. 基于共享内存：`总共享内存 ÷ 每块共享内存使用量`
3. 基于线程数：`SM最大线程数 ÷ 每块线程数`
4. 基于线程块限制：SM支持的最大线程块数
5. 这些限制因素中的最小值决定了实际可执行的线程块数

### 占用率优化
**占用率定义**：
- SM占用率：活跃线程数与最大线程数的比值
- 影响SM隐藏延迟的能力
- 100%占用率不一定是最佳性能

**增加占用率的方法**：
- 减少每线程寄存器使用量
- 减少共享内存使用量
- 调整线程块大小
- 使用`__launch_bounds__`提示编译器最大线程数

**占用率计算**：
```
占用率 = 活跃线程数 / SM最大线程数
活跃线程数 = 每块线程数 × 活跃块数
```

**使用占用率计算器**：
NVIDIA提供占用率计算器工具，帮助开发者预估不同配置下的占用率。

## 并行计算模式与优化

### 常见并行计算模式

#### 映射(Map)
每个线程独立处理一个数据元素，无需通信。

**示例：向量加法**
```cuda
__global__ void vectorAdd(float* A, float* B, float* C, int N) {
    int i = blockDim.x * blockIdx.x + threadIdx.x;
    if (i < N) {
        C[i] = A[i] + B[i];
    }
}
```

#### 规约(Reduction)
将大量数据合并为单一结果（如求和、最大值、最小值）。

**共享内存规约示例**：
```cuda
__global__ void reduce(float* input, float* output, int N) {
    __shared__ float sdata[256];
    
    int tid = threadIdx.x;
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    
    // 加载数据到共享内存
    sdata[tid] = (i < N) ? input[i] : 0;
    __syncthreads();
    
    // 规约
    for (int s=blockDim.x/2; s>0; s>>=1) {
        if (tid < s) {
            sdata[tid] += sdata[tid + s];
        }
        __syncthreads();
    }
    
    // 写回结果
    if (tid == 0) output[blockIdx.x] = sdata[0];
}
```

#### 扫描(Scan)
计算前缀和或其他累积操作。

#### 随机访问
根据数据依赖关系访问内存中的任意位置。

#### 直方图
计算数据分布的频率统计。

### 性能优化策略

#### 内存访问优化
- 合并全局内存访问
- 使用共享内存缓存频繁访问的数据
- 避免全局内存上的原子操作
- 预取数据减少等待时间

#### 指令优化
- 避免线程分化
- 减少特殊函数使用
- 利用内置函数和内联PTX
- 合适的精度选择

#### 资源利用优化
- 平衡寄存器使用与占用率
- 调整线程块大小
- 隐藏延迟的策略
- 交错多个内核执行

## 并行计算示例详解

### 矩阵加法
矩阵加法是最简单的并行运算之一，每个元素的计算完全独立。

**核心思想**：
- 每个线程处理结果矩阵中的一个元素
- 二维线程布局对应矩阵的行和列
- 不需要线程间通信

**CUDA实现**：
```cuda
__global__ void matrixAdd(float* A, float* B, float* C, int width, int height) {
    // 计算线程对应的矩阵元素位置
    int col = blockIdx.x * blockDim.x + threadIdx.x;
    int row = blockIdx.y * blockDim.y + threadIdx.y;
    
    // 确保在矩阵范围内
    if (col < width && row < height) {
        // 计算线性内存索引
        int index = row * width + col;
        // 执行加法运算
        C[index] = A[index] + B[index];
    }
}

// 主机代码调用
dim3 blockSize(16, 16);
dim3 gridSize((width + blockSize.x - 1) / blockSize.x, 
              (height + blockSize.y - 1) / blockSize.y);
matrixAdd<<<gridSize, blockSize>>>(d_A, d_B, d_C, width, height);
```

**性能考虑**：
- 块大小选择：16×16通常是不错的起点
- 内存访问模式：行优先存储确保合并访问
- 边界检查开销：通常较小，但可通过调整网格大小减少

### 矩阵乘法
矩阵乘法是计算密集型操作，需要数据重用和更复杂的优化。

**朴素实现**：
每个线程计算结果矩阵的一个元素，从全局内存多次读取。

**共享内存优化实现**：
```cuda
__global__ void matrixMul(float* A, float* B, float* C, 
                          int widthA, int heightA, int widthB) {
    // 声明共享内存用于存储A和B的子矩阵
    __shared__ float sA[BLOCK_SIZE][BLOCK_SIZE];
    __shared__ float sB[BLOCK_SIZE][BLOCK_SIZE];
    
    int bx = blockIdx.x; int by = blockIdx.y;
    int tx = threadIdx.x; int ty = threadIdx.y;
    
    // 计算当前线程负责的行列位置
    int row = by * BLOCK_SIZE + ty;
    int col = bx * BLOCK_SIZE + tx;
    
    float sum = 0.0f;
    
    // 遍历所有需要的子矩阵
    for (int m = 0; m < (widthA + BLOCK_SIZE - 1) / BLOCK_SIZE; ++m) {
        // 协作加载A和B的子矩阵到共享内存
        if (row < heightA && m*BLOCK_SIZE+tx < widthA)
            sA[ty][tx] = A[row*widthA + m*BLOCK_SIZE+tx];
        else
            sA[ty][tx] = 0.0f;
            
        if (m*BLOCK_SIZE+ty < widthA && col < widthB)
            sB[ty][tx] = B[(m*BLOCK_SIZE+ty)*widthB + col];
        else
            sB[ty][tx] = 0.0f;
            
        __syncthreads();
        
        // 计算当前子矩阵的点积贡献
        for (int k = 0; k < BLOCK_SIZE; ++k) {
            sum += sA[ty][k] * sB[k][tx];
        }
        __syncthreads();
    }
    
    // 写回结果
    if (row < heightA && col < widthB) {
        C[row*widthB + col] = sum;
    }
}
```

**更高级优化**：
- 使用矩阵分块减少全局内存访问
- 二维寄存器阵列缓存重复使用的值
- 使用张量核心加速（适用于新架构）
- 双缓冲技术隐藏内存延迟

### 卷积
卷积是图像处理和深度学习中的关键操作。

**共享内存优化版本**：
```cuda
__global__ void convolution(float* input, float* output, float* kernel,
                           int width, int height, int kernelSize) {
    // 声明共享内存，包括额外的边界元素
    extern __shared__ float sData[];
    
    int radius = kernelSize / 2;
    int tx = threadIdx.x;
    int ty = threadIdx.y;
    int bx = blockIdx.x * blockDim.x;
    int by = blockIdx.y * blockDim.y;
    int x = bx + tx;
    int y = by + ty;
    
    // 计算共享内存中的位置（添加半径偏移）
    int sIdx = (ty+radius) * (blockDim.x+2*radius) + (tx+radius);
    
    // 协作加载输入数据到共享内存，包括边界区域
    // (简化版，实际需要处理边界情况)
    if (x < width && y < height) {
        sData[sIdx] = input[y*width + x];
    }
    
    // 加载边界元素...
    // (此处省略边界处理代码)
    
    __syncthreads();
    
    // 计算卷积
    if (x < width && y < height) {
        float sum = 0.0f;
        for (int ky = -radius; ky <= radius; ky++) {
            for (int kx = -radius; kx <= radius; kx++) {
                int sDataIdx = (ty+radius+ky) * (blockDim.x+2*radius) + (tx+radius+kx);
                int kernelIdx = (ky+radius) * kernelSize + (kx+radius);
                sum += sData[sDataIdx] * kernel[kernelIdx];
            }
        }
        
        // 写回结果
        output[y*width + x] = sum;
    }
}
```

