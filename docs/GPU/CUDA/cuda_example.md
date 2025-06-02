# CUDA并行计算模式与优化策略

## 1. 经典并行计算模式实现

### 1.1 向量加法 (Vector Addition)

**问题描述**：给定两个向量A和B，计算它们的和C，即 $C_i=A_i+B_i$。

**并行策略（映射模式）**：

这是一个典型的"易并行"问题。每个元素的计算都是独立的。我们可以让每个CUDA线程负责计算结果向量C中的一个元素。

**CUDA实现**：

```cpp
__global__ void vectorAdd(const float* A, const float* B, float* C, int N) {
    // 计算当前线程应该处理的元素的全局索引
    // blockIdx.x: 当前线程块在网格中的一维索引
    // blockDim.x: 每个线程块中的线程数量 (一维)
    // threadIdx.x: 当前线程在线程块中的一维索引
    int i = blockIdx.x * blockDim.x + threadIdx.x;

    // 确保线程索引在向量的有效范围内
    // (因为启动的线程总数可能略大于N，以满足块大小的倍数)
    if (i < N) {
        C[i] = A[i] + B[i];
    }
}

// 主机端调用示例:
// int N = 1000000; // 向量大小
// float *h_A, *h_B, *h_C; // 主机端向量
// float *d_A, *d_B, *d_C; // 设备端向量

// ... (主机端分配内存，初始化A和B, 分配设备端内存 d_A, d_B, d_C) ...
// ... (cudaMemcpy h_A to d_A, h_B to d_B) ...

// int threadsPerBlock = 256;
// int blocksPerGrid = (N + threadsPerBlock - 1) / threadsPerBlock; // 向上取整，确保所有元素都被处理

// vectorAdd<<<blocksPerGrid, threadsPerBlock>>>(d_A, d_B, d_C, N);

// ... (cudaMemcpy d_C to h_C, 释放内存等) ...
```

**关键概念应用**：

- **线程**：每个线程执行相同的加法操作，但处理不同索引 `i` 的数据。
- **线程块与网格**：通过 `blockDim` 和 `gridDim` (隐式地通过 `blocksPerGrid` 和 `threadsPerBlock` 计算) 定义了足够的线程来覆盖整个向量。
- **全局线程ID计算**：`int i = blockIdx.x * blockDim.x + threadIdx.x;` 是将块索引和块内线程索引映射到全局数据索引的标准方法。
- **边界检查**：`if (i < N)` 是必要的，因为启动的线程总数 (`blocksPerGrid * threadsPerBlock`) 可能大于实际数据大小 `N`。
- **内存访问**：访问 `A[i]`, `B[i]`, `C[i]` 应该是合并的，因为相邻线程（在同一Warp内）访问的是相邻的内存地址。

**性能考虑**：

- 对于向量加法这类内存带宽敏感型内核（计算量相对于访存量很小），确保合并内存访问至关重要。
- 选择合适的 `threadsPerBlock`（如128, 256）有助于实现较好的占用率。

### 1.2 矩阵乘法 (Matrix Multiplication)

**问题描述**：给定矩阵A (M x K) 和矩阵B (K x N)，计算它们的乘积矩阵C (M x N)，即 $C_{ij}=\sum_{p=0}^{K-1}A_{ip} \times B_{pj}$。

**并行策略**：

1. **朴素实现**：每个线程计算结果矩阵C中的一个元素 C_ij。为此，该线程需要访问A的第i行和B的第j列，并进行K次乘加操作。
    
    - **缺点**：对A和B的访问存在大量重复读取（多个线程读取A的同一行，多个线程读取B的同一列），且全局内存访问模式可能不佳。
2. **共享内存优化（Tiled Matrix Multiplication）**：
    
    - **核心思想**：将输入矩阵A和B划分成小的子矩阵（tiles 或 blocks）。每个线程块负责计算结果矩阵C的一个子矩阵。为了计算这个子矩阵，线程块会协作地将A和B中对应的子矩阵从全局内存加载到共享内存中。然后，块内线程从共享内存中读取数据进行计算，这远快于从全局内存读取。
    - **步骤**：
        1. 结果矩阵C被划分为多个 `TILE_WIDTH x TILE_WIDTH`大小的子块。每个线程块计算一个这样的子块。
        2. 每个线程在线程块内负责计算其对应子块中的一个元素。
        3. 为了计算C的一个子块，需要A和B的多个子块。这些A和B的子块（通常也是 `TILE_WIDTH x TILE_WIDTH`）被分阶段加载到共享内存中。
        4. 在一个阶段中，线程块内的所有线程协作，将A的一个子块和B的一个子块加载到共享内存的两个区域 `sA` 和 `sB`。使用 `__syncthreads()` 确保加载完成。
        5. 然后，每个线程从 `sA` 和 `sB` 中读取数据，累加到其负责的C元素的局部累加器中。再次使用 `__syncthreads()` 确保所有线程完成当前子块的计算，才能进入下一阶段加载新的A、B子块。
        6. 重复步骤4和5，直到A的所有相关行子块和B的所有相关列子块都被处理完毕。
        7. 最后，每个线程将其计算得到的C元素值写回全局内存。

**CUDA实现 (共享内存优化 - 概念性)**：

```cpp
#define TILE_WIDTH 16

__global__ void matrixMulShared(const float* A, const float* B, float* C, int M, int K, int N) {
    // 共享内存，用于存储A和B的当前tile
    __shared__ float sA[TILE_WIDTH][TILE_WIDTH];
    __shared__ float sB[TILE_WIDTH][TILE_WIDTH];

    // 当前线程在线程块内的二维索引
    int tx = threadIdx.x;
    int ty = threadIdx.y;

    // 当前线程块负责计算的结果矩阵C的子块的起始行列
    int rowC = blockIdx.y * TILE_WIDTH + ty;
    int colC = blockIdx.x * TILE_WIDTH + tx;

    float Cvalue = 0.0f; // 用于累加结果的局部变量 (存储在寄存器中)

    // 遍历A的列（或B的行），每次处理一个TILE_WIDTH宽度的条带
    for (int pTile = 0; pTile < (K + TILE_WIDTH - 1) / TILE_WIDTH; ++pTile) {
        // 协作加载A的tile到sA
        // 当前线程负责加载sA[ty][tx]
        int rowA = blockIdx.y * TILE_WIDTH + ty;
        int colA = pTile * TILE_WIDTH + tx;
        if (rowA < M && colA < K) {
            sA[ty][tx] = A[rowA * K + colA];
        } else {
            sA[ty][tx] = 0.0f; // 处理边界情况，填充0
        }

        // 协作加载B的tile到sB
        // 当前线程负责加载sB[ty][tx]
        int rowB = pTile * TILE_WIDTH + ty;
        int colB = blockIdx.x * TILE_WIDTH + tx;
        if (rowB < K && colB < N) {
            sB[ty][tx] = B[rowB * N + colB];
        } else {
            sB[ty][tx] = 0.0f; // 处理边界情况，填充0
        }

        // 同步，确保所有线程都已将数据加载到共享内存
        __syncthreads();

        // 从共享内存计算当前tile对Cvalue的贡献
        for (int k = 0; k < TILE_WIDTH; ++k) {
            Cvalue += sA[ty][k] * sB[k][tx];
        }

        // 同步，确保所有线程都完成了当前tile的计算，
        // 然后才能进入下一次迭代加载新的tile
        __syncthreads();
    }

    // 将最终结果写回全局内存C
    if (rowC < M && colC < N) {
        C[rowC * N + colC] = Cvalue;
    }
}

// 主机端调用示例:
// dim3 threadsPerBlock(TILE_WIDTH, TILE_WIDTH);
// dim3 blocksPerGrid((N + TILE_WIDTH - 1) / TILE_WIDTH, (M + TILE_WIDTH - 1) / TILE_WIDTH);
// matrixMulShared<<<blocksPerGrid, threadsPerBlock>>>(d_A, d_B, d_C, M, K, N);
```

**关键概念应用**：

- **共享内存**：核心优化手段，显著减少对全局内存的访问次数。
- **线程协作**：块内线程共同加载数据到共享内存。
- **`__syncthreads()`**：在加载共享内存后和使用共享内存计算后进行同步，保证数据一致性和正确的执行顺序。
- **数据分块(Tiling）**：将大问题分解为可在共享内存中处理的小块。
- **寄存器使用**：`Cvalue` 累加器存储在每个线程的寄存器中，访问速度快。
- **边界处理**：在加载共享内存和写回结果时，需要检查是否超出矩阵实际边界。

**更高级优化**：

- 调整 `TILE_WIDTH` 大小以平衡共享内存使用、寄存器压力和并行度。
- 优化共享内存的加载模式以避免bank冲突（例如，加载B的tile时可能需要转置或特殊布局）。
- 使用更多的寄存器来缓存`sA`或`sB`中的元素，以减少共享内存访问次数（寄存器分块）。
- 对于支持的架构，使用张量核心（Tensor Cores）进行矩阵乘法，可以获得数量级的性能提升（需要使用如`wmma`内建函数或cuBLAS/CUTLASS等库）。

### 1.3 卷积 (Convolution)

**问题描述**：卷积是图像处理和深度学习（如卷积神经网络CNN）中的核心操作。它涉及一个输入信号（如图像）和一个小的卷积核（滤波器），通过在输入信号上滑动卷积核并计算加权和来产生输出信号。

对于2D卷积：$Output(i,j)=\sum_{dx}\sum_{dy}Input(i+dx,j+dy) \times Kernel(dx,dy)$

其中 dx, dy 在卷积核的范围内变化。

**并行策略（模板运算与共享内存优化）**：

与矩阵乘法类似，卷积也受益于共享内存的使用，以缓存输入数据中被多个输出点计算所共享的区域。

- **核心思想**：每个线程块负责计算输出图像的一个小区域（tile）。为了计算这个输出tile，线程块需要输入图像中一个稍大的对应区域（包含计算输出tile所需的邻域数据，即"光环"或"幽灵"区域）。这个输入区域被加载到共享内存中。
- **步骤**：
    1. 每个线程负责计算输出图像tile中的一个像素。
    2. 线程块内的线程协作，将计算当前输出tile所需的输入图像区域（包括光环区域）从全局内存加载到共享内存 `sData` 中。
    3. 卷积核通常较小，可以存储在常量内存或每个线程从全局内存加载到寄存器中（如果核在内核执行期间不变）。
    4. 使用 `__syncthreads()` 确保输入数据已完全加载到共享内存。
    5. 每个线程从共享内存 `sData` 中读取其计算所需的邻域像素，并从常量内存/寄存器中读取卷积核权重，执行乘加运算，得到其负责的输出像素值。
    6. 将计算得到的输出像素值写回全局内存。

**CUDA实现 (共享内存优化 - 概念性，2D卷积)**：

```cpp
// 假设卷积核大小为 KERNEL_RADIUS*2+1 x KERNEL_RADIUS*2+1
// BLOCK_DIM 是线程块的维度 (例如 16x16)
// SHARED_MEM_WIDTH = BLOCK_DIM_X + 2 * KERNEL_RADIUS (为了存储光环区域)

__global__ void convolutionShared(const float* input, float* output, const float* kernel,
                                  int imgWidth, int imgHeight, int kernelWidth) {
    // kernel通常较小，可以全部加载到共享内存或常量内存
    // 此处假设kernel已在常量内存或通过参数快速访问

    extern __shared__ float sData[]; // 动态分配共享内存

    int KERNEL_RADIUS = kernelWidth / 2;
    int BLOCK_DIM_X = blockDim.x;
    int BLOCK_DIM_Y = blockDim.y;
    int SHARED_MEM_PITCH = BLOCK_DIM_X + 2 * KERNEL_RADIUS; // 共享内存中一行的宽度

    // 当前线程在线程块内的索引
    int tx = threadIdx.x;
    int ty = threadIdx.y;

    // 当前线程块在网格中的起始位置 (对应输入图像)
    int blockStartX = blockIdx.x * BLOCK_DIM_X - KERNEL_RADIUS;
    int blockStartY = blockIdx.y * BLOCK_DIM_Y - KERNEL_RADIUS;

    // 协作加载输入数据到共享内存 (包括光环区域)
    // 每个线程负责加载共享内存中的一个元素
    // 需要多次加载，或者更复杂的索引来覆盖整个共享内存tile
    // 以下是一个简化的加载逻辑示例，实际中可能更复杂
    for (int y_offset = 0; y_offset < BLOCK_DIM_Y + 2 * KERNEL_RADIUS; y_offset += BLOCK_DIM_Y) {
        for (int x_offset = 0; x_offset < BLOCK_DIM_X + 2 * KERNEL_RADIUS; x_offset += BLOCK_DIM_X) {
            int load_s_y = ty + y_offset;
            int load_s_x = tx + x_offset;
            if (load_s_y < BLOCK_DIM_Y + 2 * KERNEL_RADIUS && load_s_x < BLOCK_DIM_X + 2 * KERNEL_RADIUS) {
                int load_g_y = blockStartY + load_s_y;
                int load_g_x = blockStartX + load_s_x;

                // 边界检查 (对于图像外部的像素)
                if (load_g_x >= 0 && load_g_x < imgWidth && load_g_y >= 0 && load_g_y < imgHeight) {
                    sData[load_s_y * SHARED_MEM_PITCH + load_s_x] = input[load_g_y * imgWidth + load_g_x];
                } else {
                    sData[load_s_y * SHARED_MEM_PITCH + load_s_x] = 0.0f; // 例如，用0填充边界外
                }
            }
        }
    }
    __syncthreads(); // 确保所有数据加载完毕

    // 计算卷积：每个线程计算输出图像中的一个像素
    // 输出像素的位置
    int outX = blockIdx.x * BLOCK_DIM_X + tx;
    int outY = blockIdx.y * BLOCK_DIM_Y + ty;

    if (outX < imgWidth && outY < imgHeight) {
        float sum = 0.0f;
        // 共享内存中对应输出(tx,ty)的输入数据的中心点
        int s_center_y = ty + KERNEL_RADIUS;
        int s_center_x = tx + KERNEL_RADIUS;

        for (int ky = -KERNEL_RADIUS; ky <= KERNEL_RADIUS; ++ky) {
            for (int kx = -KERNEL_RADIUS; kx <= KERNEL_RADIUS; ++kx) {
                float inputValue = sData[(s_center_y + ky) * SHARED_MEM_PITCH + (s_center_x + kx)];
                float kernelValue = kernel[(ky + KERNEL_RADIUS) * kernelWidth + (kx + KERNEL_RADIUS)];
                sum += inputValue * kernelValue;
            }
        }
        output[outY * imgWidth + outX] = sum;
    }
}

// 主机端调用时，需要计算动态共享内存大小:
// int sharedMemSize = (BLOCK_DIM_X + 2 * KERNEL_RADIUS) * (BLOCK_DIM_Y + 2 * KERNEL_RADIUS) * sizeof(float);
// convolutionShared<<<blocksPerGrid, threadsPerBlock, sharedMemSize>>>(...);
```

**关键概念应用**：

- **共享内存**：用于缓存输入图像的tile，减少全局内存访问。
- **数据重用**：共享内存中的每个输入像素可能被多个输出像素的计算所使用。
- **光环区域/幽灵单元（Halo Region / Ghost Cells）**：共享内存需要加载比输出tile对应区域更大的输入区域，以包含计算边界输出像素所需的邻域数据。
- **边界处理**：在从全局内存加载数据到共享内存时，需要正确处理图像边界（例如，填充0、复制边界像素、镜像等）。
- **动态共享内存分配**：如示例所示，可以使用 `extern __shared__ float sData[];` 并在内核启动时指定共享内存大小。
- **常量内存/寄存器**：卷积核通常较小且在计算过程中不变，适合存储在常量内存或由线程加载到寄存器中。

**性能考虑**：

- 共享内存的加载策略需要精心设计，以实现合并访问并覆盖整个tile（包括光环）。
- 共享内存的大小、线程块的维度和卷积核的大小之间需要权衡。
- 对于非常大的卷积核，可能需要多遍处理或更复杂的策略。
- 深度学习框架（如TensorFlow, PyTorch）中的卷积通常使用高度优化的库（如cuDNN），这些库内部实现了比上述示例更复杂的优化技术（如Winograd卷积、FFT卷积等）。

## 2. 总结与实践建议

以上示例展示了如何将CUDA的基本概念（线程、块、网格、共享内存、同步）与并行算法模式相结合，并通过优化内存访问来提升GPU程序的性能。实际的CUDA编程通常是一个迭代的过程：实现、分析性能、识别瓶颈、然后应用优化策略。

在实际开发中，建议采取以下步骤：

1. **先实现简单版本**：开始时实现功能正确的简单版本，不必过早关注优化
2. **使用性能分析工具**：利用Nsight Compute等工具识别性能瓶颈
3. **有针对性地优化**：根据分析结果，选择最合适的优化策略
4. **测试和验证**：每次优化后测试正确性和性能提升
5. **不断迭代**：优化是个持续过程，随着对应用和硬件理解的加深，可以进行更深入的优化
