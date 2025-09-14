# RISC-V 向量归约指令概述

## 基本概念

向量归约(Vector Reduction)指令将向量元素通过特定操作(如求和、求最大值等)归约为单个标量结果。

### 指令格式

所有向量归约指令使用统一格式:

`v[f]red<op>.vs vd, vs2, vs1, vm`

其中:

- `vd`: 目标向量寄存器(仅使用第一个元素)
- `vs2`: 输入向量
- `vs1`: 初始累积值(仅使用第一个元素)
- `vm`: 掩码位

## 指令分类与功能

### 整数归约指令

| 指令          | 功能描述             | 操作                                           |
| ------------- | -------------------- | ---------------------------------------------- |
| `vredsum.vs`  | 整数求和归约         | $vd[0]=vs1[0]+\sum_{i=0}^{vl-1}vs2[i]$         |
| `vredmax.vs`  | 有符号整数最大值归约 | $vd[0]=\max(vs1[0],\max_{i=0}^{vl-1}vs2[i])$   |
| `vredmaxu.vs` | 无符号整数最大值归约 | $vd[0]=\max_u(vs1[0],\max_{i=0}^{vl-1}vs2[i])$ |
| `vredmin.vs`  | 有符号整数最小值归约 | $vd[0]=\min(vs1[0],\min_{i=0}^{vl-1}vs2[i])$   |
| `vredminu.vs` | 无符号整数最小值归约 | $vd[0]=\min_u(vs1[0],\min_{i=0}^{vl-1}vs2[i])$ |

### 浮点归约指令

| 指令           | 功能描述           | 操作                                         |
| -------------- | ------------------ | -------------------------------------------- |
| `vfredosum.vs` | 有序浮点求和归约   | $vd[0]=vs1[0]+\sum_{i=0}^{vl-1}vs2[i]$       |
| `vfredusum.vs` | 非有序浮点求和归约 | $vd[0]=vs1[0]+\sum_{i=0}^{vl-1}vs2[i]$       |
| `vfredmax.vs`  | 浮点最大值归约     | $vd[0]=\max(vs1[0],\max_{i=0}^{vl-1}vs2[i])$ |
| `vfredmin.vs`  | 浮点最小值归约     | $vd[0]=\min(vs1[0],\min_{i=0}^{vl-1}vs2[i])$ |

### 逻辑归约指令

| 指令         | 功能描述     | 操作                                               |
| ------------ | ------------ | -------------------------------------------------- |
| `vredand.vs` | 按位与归约   | $vd[0]=vs1[0] \& \bigwedge_{i=0}^{vl-1}vs2[i]$     |
| `vredor.vs`  | 按位或归约   | $vd[0]=vs1[0] \| \bigvee_{i=0}^{vl-1}vs2[i]$       |
| `vredxor.vs` | 按位异或归约 | $vd[0]=vs1[0] \oplus \bigoplus_{i=0}^{vl-1}vs2[i]$ |

## SPIKE 模拟器实现与指令详解

归约指令在 SPIKE 模拟器中通过专门的宏来实现，包括`VI_VV_LOOP_REDUCTION`(整数归约)、`VI_VFP_LOOP_REDUCTION`(浮点归约)和`VI_VV_ULOOP_REDUCTION`(无符号归约)。

归约指令的基本工作原理是：

1. 从`vs1`的第一个元素获取初始累积值
2. 遍历`vs2`向量中的每个活跃元素
3. 根据具体操作对每个元素进行累积计算
4. 将最终结果存储在`vd`的第一个元素中

### 1. 整数归约指令

#### vredsum.vs - 向量-标量整数求和归约

**指令格式**: `vredsum.vs vd, vs2, vs1, vm`

**功能**: 将 vs2 中的所有活跃元素加到 vs1 的第一个元素上，结果放在 vd 的第一个元素中。

**SPIKE 实现**:

```cpp
// 在 riscv-isa-sim/riscv/insns/vredsum_vs.h
VI_VV_LOOP_REDUCTION
({
  vd_0 = vs1_0 + vs2;
}, {
  vd_0 = vs1_0;
})
```

**宏展开分析**:  
`VI_VV_LOOP_REDUCTION`宏展开后，`vredsum.vs`的实际执行流程如下：

```cpp
// 1. 检查归约操作条件
require(insn.rd() != insn.rs1() && insn.rd() != insn.rs2());
require_vector_vs1_overlap_vm(insn);

// 2. 获取基本参数
reg_t vstart = P.VU.vstart->read();
reg_t vl = P.VU.vl->read();
reg_t LMUL = P.VU.get_lmul();
reg_t VLMAX = P.VU.get_vlen() / P.VU.get_elen();

// 3. 根据元素宽度(SEW)处理不同的数据类型
if (sew == e8) {
    // 3.1 定义数据类型(8位整数)
    typedef int8_t VV_S;
    const int sew = 8;

    // 3.2 获取vs1的第一个元素作为初始值
    VV_S vs1_0 = P.VU.elt<VV_S>(insn.rs1(), 0);
    // 3.3 设置初始累积值
    VV_S vd_0 = vs1_0;

    // 3.4 遍历向量元素
    for (reg_t i = vstart; i < vl; ++i) {
        // 3.4.1 掩码处理
        int midx = i / 64;
        int mpos = i % 64;
        bool use_first = (P.VU.vmlen < VLMAX) && (LMUL < 1);
        bool skip = (!P.VU.get_vm()->read() &&
                    !((P.VU.get_mask(midx, use_first) >> mpos) & 0x1));

        // 3.4.2 如果被掩码过滤，应用第二个代码块
        if (skip) {
            // 对于非活跃元素: vd_0 = vs1_0;
            // 在vredsum.vs中，这个操作实际上不改变vd_0，所以是空操作
            continue;
        }

        // 3.4.3 获取当前元素值
        VV_S vs2 = P.VU.elt<VV_S>(insn.rs2(), i);

        // 3.4.4 执行求和操作(第一个代码块)
        vd_0 = vs1_0 + vs2;  // 这里的关键操作是把vs1_0+vs2赋给vd_0
    }

    // 3.5 将最终累积结果写回
    P.VU.elt<VV_S>(insn.rd(), 0) = vd_0;
}
else if (sew == e16) {
    // 16位整数处理，逻辑相同，使用int16_t类型
    // ...
}
else if (sew == e32) {
    // 32位整数处理，逻辑相同，使用int32_t类型
    // ...
}
else if (sew == e64) {
    // 64位整数处理，逻辑相同，使用int64_t类型
    // ...
}

// 设置vstart = 0，表示指令执行完毕
P.VU.vstart->write(0);
```

**注意**：宏展开分析表明 SPIKE 模拟器在这个指令的实现上可能存在 bug。真正的归约求和应该是将所有元素累加，而不是只保留最后一次加法的结果。正确的实现应该是：`vd_0 = vd_0 + vs2;`

#### vredmaxu.vs - 向量-标量无符号整数最大值归约

**指令格式**: `vredmaxu.vs vd, vs2, vs1, vm`

**功能**: 找出 vs2 中所有活跃元素和 vs1 第一个元素的无符号最大值，结果放在 vd 的第一个元素中。

**SPIKE 实现**:

```cpp
// 在 riscv-isa-sim/riscv/insns/vredmaxu_vs.h
VI_VV_ULOOP_REDUCTION
({
  vd_0 = max(vd_0, vs2);
}, {
  ;
})
```

**宏展开分析**:  
`VI_VV_ULOOP_REDUCTION`宏展开后，与`VI_VV_LOOP_REDUCTION`类似，但使用无符号整数类型。关键操作是在每次迭代中使用`max(vd_0, vs2)`比较当前累积的最大值(`vd_0`)和当前元素(`vs2`)，保留较大的值。对于非活跃元素，不做任何操作，保持当前的最大值不变。

```cpp
// 核心实现不同点
typedef uint8_t VV_U;  // 无符号类型
// ...
vd_0 = max(vd_0, vs2);  // 保留较大的值
```

#### vredmax.vs - 向量-标量有符号整数最大值归约

**指令格式**: `vredmax.vs vd, vs2, vs1, vm`

**功能**: 找出 vs2 中所有活跃元素和 vs1 第一个元素的有符号最大值，结果放在 vd 的第一个元素中。

**SPIKE 实现**:

```cpp
// 在 riscv-isa-sim/riscv/insns/vredmax_vs.h
VI_VV_LOOP_REDUCTION
({
  vd_0 = max(vd_0, vs2);
}, {
  ;
})
```

`vredmax.vs`的宏展开与`vredmaxu.vs`非常相似，主要区别在于数据类型：`vredmax.vs`使用有符号整数类型(`int8_t`等)，而`vredmaxu.vs`使用无符号整数类型(`uint8_t`等)。这会影响最大值比较的结果，因为有符号整数和无符号整数的大小比较规则不同。例如，对于 8 位整数，-1(0xFF)在有符号比较中小于 1(0x01)，但在无符号比较中大于 1。

#### vredminu.vs - 向量-标量无符号整数最小值归约

**指令格式**: `vredminu.vs vd, vs2, vs1, vm`

**功能**: 找出 vs2 中所有活跃元素和 vs1 第一个元素的无符号最小值，结果放在 vd 的第一个元素中。

**SPIKE 实现**:

```cpp
// 在 riscv-isa-sim/riscv/insns/vredminu_vs.h
VI_VV_ULOOP_REDUCTION
({
  vd_0 = min(vd_0, vs2);
}, {
  ;
})
```

这个指令是`vredmaxu.vs`的对应版本，寻找无符号最小值而不是最大值。关键操作是使用`min(vd_0, vs2)`而非`max(vd_0, vs2)`。

#### vredmin.vs - 向量-标量有符号整数最小值归约

**指令格式**: `vredmin.vs vd, vs2, vs1, vm`

**功能**: 找出 vs2 中所有活跃元素和 vs1 第一个元素的有符号最小值，结果放在 vd 的第一个元素中。

**SPIKE 实现**:

```cpp
// 在 riscv-isa-sim/riscv/insns/vredmin_vs.h
VI_VV_LOOP_REDUCTION
({
  vd_0 = min(vd_0, vs2);
}, {
  ;
})
```

`vredmin.vs`的宏展开与`vredminu.vs`类似，但数据类型为有符号整数，这会影响最小值比较的结果。例如，当比较-128 和 127 时，在有符号比较中-128 更小，而在无符号比较中，如果将-128 视为无符号数 0x80，它比 127 大。

### 2. 逻辑归约指令

#### vredand.vs - 向量-标量按位与归约

**指令格式**: `vredand.vs vd, vs2, vs1, vm`

**功能**: 计算 vs2 中所有活跃元素和 vs1 第一个元素的按位与，结果放在 vd 的第一个元素中。

**SPIKE 实现**:

```cpp
// 在 riscv-isa-sim/riscv/insns/vredand_vs.h
VI_VV_LOOP_REDUCTION
({
  vd_0 &= vs2;
}, {
  ;
})
```

**宏展开分析**:  
使用按位与操作符`&=`进行累积，这是一个复合赋值操作，确保每个元素都参与按位与计算。与前面的`vredsum.vs`的宏展开类似，只是操作从加法变为按位与。

#### vredor.vs - 向量-标量按位或归约

**指令格式**: `vredor.vs vd, vs2, vs1, vm`

**功能**: 计算 vs2 中所有活跃元素和 vs1 第一个元素的按位或，结果放在 vd 的第一个元素中。

**SPIKE 实现**:

```cpp
// 在 riscv-isa-sim/riscv/insns/vredor_vs.h
VI_VV_LOOP_REDUCTION
({
  vd_0 |= vs2;
}, {
  ;
})
```

与`vredand.vs`类似，但使用按位或操作符`|=`进行累积。

#### vredxor.vs - 向量-标量按位异或归约

**指令格式**: `vredxor.vs vd, vs2, vs1, vm`

**功能**: 计算 vs2 中所有活跃元素和 vs1 第一个元素的按位异或，结果放在 vd 的第一个元素中。

**SPIKE 实现**:

```cpp
// 在 riscv-isa-sim/riscv/insns/vredxor_vs.h
VI_VV_LOOP_REDUCTION
({
  vd_0 ^= vs2;
}, {
  ;
})
```

与前两个逻辑归约指令类似，但使用按位异或操作符`^=`进行累积。

### 3. 浮点数归约指令

#### vfredosum.vs - 向量-标量浮点有序求和归约

**指令格式**: `vfredosum.vs vd, vs2, vs1, vm`

**功能**: 以确定性顺序将 vs2 中的所有活跃浮点元素加到 vs1 的第一个元素上，结果放在 vd 的第一个元素中。

**SPIKE 实现**:

```cpp
// 在 riscv-isa-sim/riscv/insns/vfredosum_vs.h
VI_VFP_LOOP_REDUCTION
({
  vd_0 = f32_add(vd_0, vs2);
}, {
  ;
})
```

**宏展开分析**:  
`VI_VFP_LOOP_REDUCTION`宏展开后，与整数归约类似，但针对浮点数处理：

```cpp
// 1. 检查归约操作条件
require(insn.rd() != insn.rs1() && insn.rd() != insn.rs2());
require_vector_vs1_overlap_vm(insn);
require_fp;  // 确认浮点单元可用

// 2. 根据浮点数精度处理不同情况
if (sew == e32) {  // 单精度浮点
    typedef float32_t VFP_VV_S;
    const int sew = 32;

    // 设置浮点舍入模式
    softfloat_roundingMode = STATE.frm->read();

    // 获取初始值
    VFP_VV_S vs1_0 = P.VU.elt<VFP_VV_S>(insn.rs1(), 0);
    VFP_VV_S vd_0 = vs1_0;

    // 遍历向量元素
    for (reg_t i = vstart; i < vl; ++i) {
        // 掩码处理略...

        // 获取当前向量元素
        VFP_VV_S vs2 = P.VU.elt<VFP_VV_S>(insn.rs2(), i);

        // 执行浮点加法
        vd_0 = f32_add(vd_0, vs2);
    }

    // 将结果写回
    P.VU.elt<VFP_VV_S>(insn.rd(), 0) = vd_0;
}
// 处理半精度（e16）和双精度（e64）浮点...
```

对于浮点操作，SPIKE 使用软件浮点库实现（如`f32_add`），并根据当前浮点舍入模式进行计算。

#### vfredusum.vs - 向量-标量浮点不保证顺序求和归约

**指令格式**: `vfredusum.vs vd, vs2, vs1, vm`

**功能**: 不保证顺序将 vs2 中的所有活跃浮点元素加到 vs1 的第一个元素上，结果放在 vd 的第一个元素中。

**SPIKE 实现**:

```cpp
// 在 riscv-isa-sim/riscv/insns/vfredusum_vs.h
VI_VFP_LOOP_REDUCTION
({
  vd_0 = f32_add(vd_0, vs2);
}, {
  ;
})
```

在 SPIKE 实现中，`vfredusum.vs`和`vfredosum.vs`的实现相同，但在实际硬件上可能会有不同的优化。无序实现可以允许硬件进行并行化或使用树形归约等技术提高性能。

#### vfredmax.vs - 向量-标量浮点最大值归约

**指令格式**: `vfredmax.vs vd, vs2, vs1, vm`

**功能**: 找出 vs2 中所有活跃浮点元素和 vs1 第一个元素的最大值，结果放在 vd 的第一个元素中。

**SPIKE 实现**:

```cpp
// 在 riscv-isa-sim/riscv/insns/vfredmax_vs.h
VI_VFP_LOOP_REDUCTION
({
  vd_0 = f32_max(vd_0, vs2);
}, {
  ;
})
```

与浮点求和类似，但使用`f32_max`函数代替`f32_add`函数。浮点最大值比较会考虑特殊浮点值如 NaN、+/-Infinity 等。

#### vfredmin.vs - 向量-标量浮点最小值归约

**指令格式**: `vfredmin.vs vd, vs2, vs1, vm`

**功能**: 找出 vs2 中所有活跃浮点元素和 vs1 第一个元素的最小值，结果放在 vd 的第一个元素中。

**SPIKE 实现**:

```cpp
// 在 riscv-isa-sim/riscv/insns/vfredmin_vs.h
VI_VFP_LOOP_REDUCTION
({
  vd_0 = f32_min(vd_0, vs2);
}, {
  ;
})
```

与`vfredmax.vs`类似，但使用`f32_min`函数代替`f32_max`函数。

## 归约操作掩码处理机制

向量指令中掩码处理是一项关键功能，它控制哪些元素参与操作。在归约指令中，掩码处理的代码如下：

```cpp
// 掩码处理代码详解
int midx = i / 64;           // 掩码字索引（每个机器字有64位）
int mpos = i % 64;           // 掩码字内的位索引
bool use_first = (P.VU.vmlen < VLMAX) && (LMUL < 1);  // 是否使用第一个掩码字
bool skip = (!P.VU.get_vm()->read() &&                // vm=0表示使用掩码
            !((P.VU.get_mask(midx, use_first) >> mpos) & 0x1)); // 检查掩码位

if (skip) {
    continue;  // 如果掩码位为0，跳过此元素
}
```

归约操作是顺序执行的，从索引`vstart`开始到当前向量长度`vl`结束，确保结果的确定性。由于是顺序处理，归约操作不能像普通向量指令那样并行化，这也是为什么归约指令通常性能较低的原因。

## 向量归约指令应用示例

下面通过几个完整的程序示例，展示向量归约指令的实际应用。

### 1. 整数求和示例

计算数组中所有元素的和：

```assembly
# 数组求和程序
.global _start
.section .text

_start:
    # 假设a0包含数组地址，a1包含数组长度
    li t0, 0          # 初始化循环计数器

    # 初始化累积向量寄存器v0为0
    vsetvli t1, a1, e32, m2  # 设置向量长度，32位元素，LMUL=2
    vmv.v.i v0, 0            # v0 = 0

    # 载入向量
load_loop:
    vsetvli t1, a1, e32, m2  # 可能会根据剩余元素调整vl
    sub a1, a1, t1           # 更新剩余元素数
    vle32.v v2, (a0)         # 加载向量数据到v2
    slli t2, t1, 2           # t2 = t1 * 4 (每个元素4字节)
    add a0, a0, t2           # 更新数组指针

    # 计算当前块的和
    vredsum.vs v4, v2, v0    # v4[0] = sum(v2) + v0[0]
    vmv.x.s t3, v4           # 将结果移到通用寄存器
    add t0, t0, t3           # 累加到总和

    # 检查是否完成
    bnez a1, load_loop

    # t0现在包含数组所有元素的和
```

这个例子中，我们逐块处理数组，对每块使用`vredsum.vs`计算部分和，然后累加到标量寄存器。

### 2. 查找数组最大值示例

查找数组中的最大值：

```assembly
# 查找数组最大值程序
.global _start
.section .text

_start:
    # 假设a0包含数组地址，a1包含数组长度

    # 初始化最大值向量寄存器v0为最小可能值
    vsetvli t0, a1, e32, m1   # 设置向量长度，32位元素
    vmv.v.i v0, 0x80000000    # v0[0] = INT_MIN (0x80000000)

    # 加载第一个向量块并计算最大值
max_loop:
    vsetvli t0, a1, e32, m1   # 可能会根据剩余元素调整vl
    sub a1, a1, t0            # 更新剩余元素数
    vle32.v v1, (a0)          # 加载向量数据
    slli t1, t0, 2            # t1 = t0 * 4 (每个元素4字节)
    add a0, a0, t1            # 更新数组指针

    # 查找当前块的最大值
    vredmax.vs v0, v1, v0     # v0[0] = max(v1[*], v0[0])

    # 检查是否完成
    bnez a1, max_loop

    # v0[0]现在包含整个数组的最大值
    vmv.x.s a0, v0            # 将最大值移到返回寄存器
```

这个例子中，我们初始化累积值为 INT_MIN，逐块处理数组，对每块使用`vredmax.vs`更新最大值。

### 3. 带掩码的浮点求和示例

计算数组中所有偶数索引位置元素的浮点和：

```assembly
# 计算偶数位置元素的浮点和
.global _start
.section .text

_start:
    # 假设a0包含浮点数组地址，a1包含数组长度

    # 初始化累积值为0.0
    vsetvli t0, a1, e32, m2    # 设置向量长度，32位浮点
    vfmv.v.f v0, ft0           # v0 = 0.0 (假设ft0已设为0.0)

    # 创建掩码标记偶数位置
    vid.v v3                    # 生成索引向量 [0,1,2,3...]
    vand.vi v3, v3, 1           # 取最低位
    vmseq.vi v0, v3, 0          # 设置掩码，偶数索引=1

mask_loop:
    vsetvli t0, a1, e32, m2     # 设置向量长度
    sub a1, a1, t0              # 更新剩余元素数
    vle32.v v2, (a0), v0.t      # 加载向量，只加载偶数位置
    slli t1, t0, 2              # t1 = t0 * 4 (每个元素4字节)
    add a0, a0, t1              # 更新数组指针

    # 计算当前块符合条件元素的和
    vfredosum.vs v4, v2, v0, v0.t  # v4[0] = sum(v2[偶数位置]) + v0[0]
    vmv.f.s ft1, v4                # 将结果移到浮点寄存器
    fadd.s ft0, ft0, ft1           # 累加到总和

    # 检查是否完成
    bnez a1, mask_loop

    # ft0现在包含所有偶数位置元素的和
```

这个例子中，我们创建一个掩码向量，只标记偶数索引位置，然后使用`vfredosum.vs`计算这些元素的浮点和。

### 4. 向量按位归约操作示例

检查向量中是否存在任何非零位：

```assembly
# 检查向量中是否有任何非零位
.global _start
.section .text

_start:
    # 假设a0包含位图地址，a1包含位图长度(字节)

    # 初始化结果为0
    vsetvli t0, a1, e8, m4     # 设置向量长度，8位元素，LMUL=4
    vmv.v.i v0, 0              # v0 = 0

    # 处理位图
check_loop:
    vsetvli t0, a1, e8, m4     # 设置向量长度
    sub a1, a1, t0             # 更新剩余字节数
    vle8.v v4, (a0)            # 加载向量数据
    add a0, a0, t0             # 更新位图指针

    # 执行按位或归约，看是否有任何非零位
    vredor.vs v0, v4, v0       # v0[0] = v0[0] | v4[0] | v4[1] | ...

    # 检查是否完成
    bnez a1, check_loop

    # v0[0]现在包含结果，如果非零，表示存在非零位
    vmv.x.s a0, v0             # 将结果移到返回寄存器
```

这个例子中，我们使用`vredor.vs`指令来执行按位或归约，如果位图中有任何位为 1，最终结果将非零。这种技术可用于快速检查位图或掩码中是否存在某些标记位。
