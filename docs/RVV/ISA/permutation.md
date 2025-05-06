# RISC-V 向量置换与移动指令概述

## 基本概念

向量置换(Vector Permutation)和移动(Move)指令用于重排元素顺序和传输数据，是向量处理中数据重组和管理的关键指令集。

### 指令分类

RISC-V 向量置换与移动指令主要分为以下几类：

1. **滑动指令** - 在向量寄存器中上下滑动元素
2. **索引收集指令** - 根据索引向量从源向量收集元素
3. **压缩/扩展指令** - 根据掩码位压缩或扩展向量元素
4. **移动指令** - 在标量和向量寄存器间，或向量寄存器间移动数据
5. **寄存器组指令** - 整组向量寄存器传输

## 指令格式与功能

### 1. 向量滑动指令

#### `vslideup.vx`/`vslideup.vi` - 向量元素向上滑动(固定偏移/立即数)

| 索引范围                                                | 元素处理                                                            |
| ------------------------------------------------------- | ------------------------------------------------------------------- |
| $0 \leq i < \max(\text{vstart}, \text{OFFSET})$         | 元素不变                                                            |
| $\max(\text{vstart}, \text{OFFSET}) \leq i < \text{vl}$ | $\text{vd}[i] = \text{vs2}[i-\text{OFFSET}]$ (仅当 v0.mask[i]=1 时) |
| $\text{vl} \leq i < \text{VLMAX}$                       | 根据尾部策略处理                                                    |

#### `vslidedown.vx`/`vslidedown.vi` - 向量元素向下滑动(固定偏移/立即数)

| 索引范围                           | 元素处理                                                                                        |
| ---------------------------------- | ----------------------------------------------------------------------------------------------- |
| $0 \leq i < \text{vstart}$         | 元素不变                                                                                        |
| $\text{vstart} \leq i < \text{vl}$ | $\text{vd}[i] = \text{vs2}[i+\text{OFFSET}]$ (仅当 v0.mask[i]=1 时，且 i+OFFSET < vl，否则为 0) |
| $\text{vl} \leq i < \text{VLMAX}$  | 根据尾部策略处理                                                                                |

#### `vslide1up.vx` - 向量元素向上滑动 1 并插入标量

| 索引范围                                    | 元素处理                                                |
| ------------------------------------------- | ------------------------------------------------------- |
| $0 \leq i < \text{vstart}$                  | 元素不变                                                |
| $i = \text{vstart} = 0$                     | $\text{vd}[0] = \text{rs1}$ (仅当 v0.mask[0]=1 时)      |
| $\max(1, \text{vstart}) \leq i < \text{vl}$ | $\text{vd}[i] = \text{vs2}[i-1]$ (仅当 v0.mask[i]=1 时) |
| $\text{vl} \leq i < \text{VLMAX}$           | 根据尾部策略处理                                        |

#### `vslide1down.vx` - 向量元素向下滑动 1 并插入标量

| 索引范围                             | 元素处理                                                        |
| ------------------------------------ | --------------------------------------------------------------- |
| $0 \leq i < \text{vstart}$           | 元素不变                                                        |
| $\text{vstart} \leq i < \text{vl}-1$ | $\text{vd}[i] = \text{vs2}[i+1]$ (仅当 v0.mask[i]=1 时)         |
| $i = \text{vl}-1$                    | $\text{vd}[\text{vl}-1] = \text{rs1}$ (仅当 v0.mask[vl-1]=1 时) |
| $\text{vl} \leq i < \text{VLMAX}$    | 根据尾部策略处理                                                |

### 2. 索引收集指令

#### `vrgather.vv` - 使用向量索引进行收集

| 索引范围                           | 元素处理                                                                                            |
| ---------------------------------- | --------------------------------------------------------------------------------------------------- |
| $0 \leq i < \text{vstart}$         | 元素不变                                                                                            |
| $\text{vstart} \leq i < \text{vl}$ | $\text{vd}[i] = (\text{vs1}[i] < \text{vl}) ? \text{vs2}[\text{vs1}[i]] : 0$ (仅当 v0.mask[i]=1 时) |
| $\text{vl} \leq i < \text{VLMAX}$  | 根据尾部策略处理                                                                                    |

#### `vrgather.vx` - 使用标量索引进行收集

| 索引范围                           | 元素处理                                                                                      |
| ---------------------------------- | --------------------------------------------------------------------------------------------- |
| $0 \leq i < \text{vstart}$         | 元素不变                                                                                      |
| $\text{vstart} \leq i < \text{vl}$ | $\text{vd}[i] = (\text{rs1} < \text{vl}) ? \text{vs2}[\text{rs1}] : 0$ (仅当 v0.mask[i]=1 时) |
| $\text{vl} \leq i < \text{VLMAX}$  | 根据尾部策略处理                                                                              |

#### `vrgather.vi` - 使用立即数索引进行收集

| 索引范围                           | 元素处理                                                                                      |
| ---------------------------------- | --------------------------------------------------------------------------------------------- |
| $0 \leq i < \text{vstart}$         | 元素不变                                                                                      |
| $\text{vstart} \leq i < \text{vl}$ | $\text{vd}[i] = (\text{imm} < \text{vl}) ? \text{vs2}[\text{imm}] : 0$ (仅当 v0.mask[i]=1 时) |
| $\text{vl} \leq i < \text{VLMAX}$  | 根据尾部策略处理                                                                              |

#### `vrgatherei16.vv` - 使用 16 位向量索引收集

| 索引范围                           | 元素处理                                                                                            |
| ---------------------------------- | --------------------------------------------------------------------------------------------------- |
| $0 \leq i < \text{vstart}$         | 元素不变                                                                                            |
| $\text{vstart} \leq i < \text{vl}$ | $\text{vd}[i] = (\text{vs1}[i] < \text{vl}) ? \text{vs2}[\text{vs1}[i]] : 0$ (仅当 v0.mask[i]=1 时) |
| $\text{vl} \leq i < \text{VLMAX}$  | 根据尾部策略处理                                                                                    |

### 3. 压缩/扩展指令

#### `vcompress.vm` - 向量掩码压缩

| 索引范围                           | 元素处理                                                                       |
| ---------------------------------- | ------------------------------------------------------------------------------ |
| $0 \leq i < \text{vstart}$         | 源元素不参与压缩                                                               |
| $\text{vstart} \leq i < \text{vl}$ | 对于每个$\text{vs1}[i]=1$，执行$\text{vd}[j++] = \text{vs2}[i]$（j 从 0 开始） |
| 剩余目标位置 $j$ 到 $\text{vl}-1$  | 元素不变（这些是未被写入的目标位置）                                           |
| $\text{vl} \leq j < \text{VLMAX}$  | 根据尾部策略处理                                                               |

**注意**：与其他向量指令不同，`vcompress.vm`直接使用 vs1 作为压缩掩码，不使用 v0.mask 进行条件执行。

### 4. 向量-标量移动指令

#### `vmv.s.x` - 标量整数写入向量元素

| 索引范围                  | 元素处理                    |
| ------------------------- | --------------------------- |
| $i = 0$                   | $\text{vd}[0] = \text{rs1}$ |
| $1 \leq i < \text{VLMAX}$ | 元素不变                    |

#### `vmv.x.s` - 向量元素读入标量整数寄存器

| 操作     | 元素处理                                        |
| -------- | ----------------------------------------------- |
| 读取操作 | $\text{rd} = \text{vs2}[0]$ (有符号扩展到 XLEN) |

#### `vfmv.s.f` - 标量浮点数写入向量元素

| 索引范围                  | 元素处理                    |
| ------------------------- | --------------------------- |
| $i = 0$                   | $\text{vd}[0] = \text{fs1}$ |
| $1 \leq i < \text{VLMAX}$ | 元素不变                    |

#### `vfmv.f.s` - 向量元素读入标量浮点寄存器

| 操作     | 元素处理                    |
| -------- | --------------------------- |
| 读取操作 | $\text{fd} = \text{vs2}[0]$ |

### 5. 向量整组移动指令

#### `vmv1r.v`/`vmv2r.v`/`vmv4r.v`/`vmv8r.v` - 复制向量寄存器组

| 寄存器范围   | 元素处理                                     |
| ------------ | -------------------------------------------- |
| 整个寄存器组 | 将源寄存器组的所有位按字节复制到目标寄存器组 |

**SPIKE 实现** (以 `vmv1r.v` 为例):

```cpp
require_vector(true);
require_align(insn.rd(), 1);
require_align(insn.rs2(), 1);

reg_t vl = 0;
const reg_t rd_num = insn.rd();
const reg_t rs2_num = insn.rs2();

for (reg_t i=0; i<P.VU.vlenb; ++i) {
  P.VU.elt<uint8_t>(rd_num, 0, i) = P.VU.elt<uint8_t>(rs2_num, 0, i);
}
```

**特点**:

1. 这些指令直接操作原始寄存器位，不考虑元素边界
2. 复制是按字节进行的，高效快速
3. 不使用掩码，不受 vstart 或 vl 影响
4. 寄存器需要按照要移动的组大小对齐(1/2/4/8)

**使用场景**:

- 寄存器备份与恢复
- 向量寄存器上下文切换
- 向量数据的整块传输

#### vmv.x.s - 向量元素读入标量整数寄存器

**指令格式**: `vmv.x.s rd, vs2`

**功能**: 将向量寄存器 vs2 的第一个元素读入通用寄存器 rd。

**SPIKE 实现**:

```cpp
require(P.VU.vsew >= e8 && P.VU.vsew <= e64);
require_vector(true);

reg_t sew = P.VU.vsew;

reg_t v;
if (sew == e8)
  v = P.VU.elt<int8_t>(insn.rs2(), 0);
else if (sew == e16)
  v = P.VU.elt<int16_t>(insn.rs2(), 0);
else if (sew == e32)
  v = P.VU.elt<int32_t>(insn.rs2(), 0);
else
  v = P.VU.elt<int64_t>(insn.rs2(), 0);

// 完成符号扩展并写入目标寄存器
WRITE_RD(sext_xlen(v));
```

**注意**:

- 自动对小于 XLEN 的数据进行符号扩展
- 不受 vstart、vl 或掩码的影响
- 只读取第一个元素

### 6. 向量索引生成指令

#### vid.v - 生成向量索引

**指令格式**: `vid.v vd, vm`

**功能**: 生成从 0 开始递增的连续索引值，结果放在 vd 的每个元素中。

**SPIKE 实现**:

```cpp
VI_VD_LOOP_BASE
if (!is_skip(i)) {
  switch(sew) {
  case e8:
    P.VU.elt<uint8_t>(rd_num, i) = i;
    break;
  case e16:
    P.VU.elt<uint16_t>(rd_num, i) = i;
    break;
  case e32:
    P.VU.elt<uint32_t>(rd_num, i) = i;
    break;
  default:
    P.VU.elt<uint64_t>(rd_num, i) = i;
    break;
  }
}
VI_VD_LOOP_END
```

**注意**: 在 SPIKE 中，`VI_VD_LOOP_BASE`和`VI_VD_LOOP_END`是宏，它们展开后包含了验证向量单元状态、设置向量长度、处理掩码等通用代码。核心操作是根据元素宽度，将当前索引值存储到相应位置。

vid.v 指令在向量计算中非常有用，它可以用于生成索引向量，与其他向量指令结合使用实现复杂的数据重组和处理。例如，一个常见的用法是结合 vid.v 和 vrgather.vv 实现矩阵转置。

#### viota.m - 生成前缀和索引表

**指令格式**: `viota.m vd, vs2, vm`

**功能**: 对 vs2 向量中的掩码位进行递增计数，结果放在 vd 中。

**SPIKE 实现**:

```cpp
VI_CHECK_MSS(false);

reg_t vl = P.VU.vl->read();
reg_t rd_num = insn.rd();
reg_t rs1_num = insn.rs1();
reg_t rs2_num = insn.rs2();
reg_t vmask = P.VU.vmask;

require(P.VU.vflmul >= P.VU.vlmul);
require_align(rd_num, P.VU.vflmul);
require_align(rs2_num, P.VU.vlmul);

// 初始化累积计数器
reg_t sum = 0;
for (reg_t i = P.VU.vstart->read(); i < vl; ++i) {
  // 寄存器元素访问
  VI_LOOP_ELEMENT_SKIP();

  // 判断源向量中当前位置的值是否为1
  bool vs2_lsb = (P.VU.elt<uint64_t>(rs2_num, midx) >> mpos) & 0x1;

  // 写入当前累积值并可能更新累积器
  VI_LOOP_ELEMENT_EDIT({
    P.VU.elt<uint64_t>(rd_num, i) = sum;
    if (vs2_lsb)
      ++sum;
  })
}

P.VU.vstart->write(0);
```

**注意**: 在 SPIKE 实现中，使用了许多宏来简化代码，但核心逻辑是遍历向量，记录之前遇到的有效位数量，并将这个累积值写入目标向量的相应位置。

## SPIKE 模拟器实现与指令详解

### 1. 向量滑动指令

#### vslide1up.vx - 向量元素向上滑动 1 并插入标量

**指令格式**: `vslide1up.vx vd, vs2, rs1, vm`

**功能**: 将 vs2 中的元素向上滑动 1 个位置，并在位置 0 插入 rs1 中的标量值。

**SPIKE 宏展开分析**:  
`vslide1up.vx`的实现可以展开为:

```cpp
// 核心操作步骤
// 1. 验证操作条件
require(P.VU.vsew >= e8 && P.VU.vsew <= e64);
require_vector(true);
require_align(insn.rd(), P.VU.vflmul);
require_align(insn.rs2(), P.VU.vflmul);

// 2. 获取向量长度和操作数
reg_t vl = P.VU.vl->read();
reg_t rd_num = insn.rd();
reg_t rs1_num = insn.rs1();
reg_t rs2_num = insn.rs2();
reg_t xrm = 0;
reg_t scalar_val = RS1;  // 获取标量值

// 3. 遍历处理每个元素
for (reg_t i = P.VU.vstart->read(); i < vl; ++i) {
  // 3.1 掩码检查
  bool use_result = true;
  if (!P.VU.get_vm()->read()) {
    // 检查掩码位
    const int mpos = i / 8;
    const int moff = i % 8;
    use_result = (P.VU.get_mask(mpos) >> moff) & 0x1;
  }

  // 3.2 元素处理
  if (use_result) {
    if (i == 0) {
      // 第一个元素使用标量rs1的值
      P.VU.set_elt<uint32_t>(rd_num, 0, scalar_val);  // 示例使用32位元素
    } else {
      // 其他元素从vs2的i-1位置获取
      uint32_t val = P.VU.elt<uint32_t>(rs2_num, i-1);
      P.VU.set_elt<uint32_t>(rd_num, i, val);
    }
  }
}

// 4. 重置vstart寄存器
P.VU.vstart->write(0);
```

在这个指令中，关键操作是将向量元素"向上滑动"一个位置，同时在第一个位置插入标量值。对于掩码处理，如果某个位置的掩码位为 0，则该位置的值保持不变（对应操作被跳过）。

#### vslidedown.vx - 向量元素向下滑动指令

**指令格式**: `vslidedown.vx vd, vs2, rs1, vm`

**功能**: 将 vs2 中的元素向下滑动 rs1 个位置。

**SPIKE 宏展开分析**:

```cpp
// 核心实现
// 1. 验证操作条件
require(P.VU.vsew >= e8 && P.VU.vsew <= e64);
require_vector(true);
require_align(insn.rd(), P.VU.vflmul);
require_align(insn.rs2(), P.VU.vflmul);

// 2. 获取向量长度和操作数
reg_t vl = P.VU.vl->read();
reg_t rd_num = insn.rd();
reg_t rs1_num = insn.rs1();
reg_t rs2_num = insn.rs2();
reg_t offset = RS1;  // 从寄存器获取滑动偏移量

// 3. 遍历每个目标元素
for (reg_t i = P.VU.vstart->read(); i < vl; ++i) {
  // 3.1 掩码检查
  bool use_result = true;
  if (!P.VU.get_vm()->read()) {
    // 检查掩码位
    const int mpos = i / 8;
    const int moff = i % 8;
    use_result = (P.VU.get_mask(mpos) >> moff) & 0x1;
  }

  // 3.2 元素处理
  if (use_result) {
    const reg_t src_idx = i + offset;  // 计算源索引
    if (src_idx >= vl) {
      // 超出范围的元素设为0
      P.VU.set_elt<uint32_t>(rd_num, i, 0);
    } else {
      // 从源位置获取元素
      uint32_t val = P.VU.elt<uint32_t>(rs2_num, src_idx);
      P.VU.set_elt<uint32_t>(rd_num, i, val);
    }
  }
}

// 4. 重置vstart寄存器
P.VU.vstart->write(0);
```

滑动指令的核心原理是计算目标索引和源索引之间的映射关系。在`vslidedown`中，索引映射为`vd[i] = vs2[i+offset]`，而在`vslideup`中，映射为`vd[i+offset] = vs2[i]`。

### 2. 索引收集指令

#### vrgather.vv - 使用向量索引进行收集

**指令格式**: `vrgather.vv vd, vs2, vs1, vm`

**功能**: 根据向量 vs1 中的索引值，从 vs2 中收集元素到 vd。

**SPIKE 宏展开分析**:

```cpp
// 核心实现
// 1. 验证操作条件
require(P.VU.vsew >= e8 && P.VU.vsew <= e64);
require_vector(true);
require_align(insn.rd(), P.VU.vflmul);
require_align(insn.rs2(), P.VU.vflmul);

// 2. 获取向量长度和操作数
reg_t vl = P.VU.vl->read();
reg_t rd_num = insn.rd();
reg_t rs1_num = insn.rs1();
reg_t rs2_num = insn.rs2();

// 3. 遍历处理每个元素
for (reg_t i = P.VU.vstart->read(); i < vl; ++i) {
  // 3.1 掩码检查
  bool use_result = true;
  if (!P.VU.get_vm()->read()) {
    // 检查掩码位
    const int mpos = i / 8;
    const int moff = i % 8;
    use_result = (P.VU.get_mask(mpos) >> moff) & 0x1;
  }

  // 3.2 元素处理
  if (use_result) {
    // 获取索引向量的值
    const uint64_t idx = P.VU.elt<uint64_t>(rs1_num, i);

    // 验证索引范围
    if (idx >= vl) {
      // 超出范围的索引结果为0
      P.VU.set_elt<uint32_t>(rd_num, i, 0);
    } else {
      // 从源位置获取元素
      uint32_t val = P.VU.elt<uint32_t>(rs2_num, idx);
      P.VU.set_elt<uint32_t>(rd_num, i, val);
    }
  }
}

// 4. 重置vstart寄存器
P.VU.vstart->write(0);
```

`vrgather`指令系列实现了一种间接寻址的方式，允许通过索引向量来打乱或重组原始向量的元素。这相当于实现了一个查找表功能，允许灵活的数据重组。

### 3. 向量-标量移动指令

#### vmv.s.x - 标量整数写入向量元素

**指令格式**: `vmv.s.x vd, rs1`

**功能**: 将通用寄存器 rs1 中的整数值写入向量寄存器 vd 的第一个元素。

**SPIKE 实现**:

```cpp
// 1. 验证向量扩展状态
require(P.VU.vsew >= e8 && P.VU.vsew <= e64);
require_vector(true);

// 2. 获取源寄存器值并写入向量寄存器第一个元素
reg_t sew = P.VU.vsew;

if (sew == e8)
  P.VU.elt<uint8_t>(insn.rd(), 0) = RS1;
else if (sew == e16)
  P.VU.elt<uint16_t>(insn.rd(), 0) = RS1;
else if (sew == e32)
  P.VU.elt<uint32_t>(insn.rd(), 0) = RS1;
else
  P.VU.elt<uint64_t>(insn.rd(), 0) = RS1;
```

**注意**:

- 这条指令不受 vstart、vl 或掩码的影响
- 只修改第一个元素，其他元素保持不变
- 支持不同的元素宽度(8/16/32/64 位)
- 这是一个专门的指令，不属于常规向量指令集

#### vmv.x.s - 向量元素读入标量整数寄存器

**指令格式**: `vmv.x.s rd, vs2`

**功能**: 将向量寄存器 vs2 的第一个元素读入通用寄存器 rd。

**SPIKE 宏展开分析**:

```cpp
// 核心实现
// 1. 验证向量扩展状态
require(P.VU.vsew >= e8 && P.VU.vsew <= e64);
require_vector(true);

// 2. 读取向量元素并进行符号扩展
reg_t v = 0;
switch (P.VU.vsew) {
  case e8:
    v = sign_extend(P.VU.elt<int8_t>(insn.rs2(), 0), 8);
    break;
  case e16:
    v = sign_extend(P.VU.elt<int16_t>(insn.rs2(), 0), 16);
    break;
  case e32:
    v = sign_extend(P.VU.elt<int32_t>(insn.rs2(), 0), 32);
    break;
  case e64:
    v = P.VU.elt<int64_t>(insn.rs2(), 0);
    break;
}

// 3. 写入目标寄存器
WRITE_RD(v);
```

**注意**:

- 自动对小于 XLEN 的数据进行符号扩展
- 不受 vstart、vl 或掩码的影响
- 只读取第一个元素

### 4. 向量整组移动指令

向量整组移动指令(`vmvNr.v`)是一组快速复制多个向量寄存器内容的指令，通常用于向量寄存器的上下文保存和恢复。

**通用原理**:
所有`vmvNr.v`指令遵循相同的模式 - 将源向量寄存器组的完整内容复制到目标向量寄存器组。指令中的 N(1,2,4,8)表示一次复制的向量寄存器数量。

**SPIKE 宏展开分析**:

```cpp
// vmvNr.v共同实现模式
// 以vmv4r.v为例

// 1. 验证向量扩展状态和寄存器对齐
require_vector(true);
require_align(insn.rd(), 4);  // 需要4个寄存器对齐
require_align(insn.rs2(), 4);

// 2. 获取寄存器信息
const reg_t rd_num = insn.rd();
const reg_t rs2_num = insn.rs2();
const reg_t size = 4 * P.VU.vlenb;  // 4个向量寄存器的总字节数

// 3. 按字节复制寄存器内容
for (reg_t i = 0; i < size; ++i) {
  const uint8_t val = P.VU.elt<uint8_t>(rs2_num, 0, i);
  P.VU.elt<uint8_t>(rd_num, 0, i) = val;
}
```

对于`vmv1r.v`、`vmv2r.v`和`vmv8r.v`，实现方式相同，只是 size 的计算和对齐要求不同。这些指令直接以字节为单位操作，忽略元素边界，实现对向量寄存器内容的位级别完整复制。

### 5. 压缩/扩展指令

#### vcompress.vm - 向量掩码压缩

**指令格式**: `vcompress.vm vd, vs2, vs1`

**功能**: 根据掩码向量 vs1，将 vs2 中掩码为 1 的元素按顺序压缩到 vd 中。

**SPIKE 宏展开分析**:

```cpp
// 核心实现
// 1. 验证寄存器不重叠且正确对齐
require(insn.rd() != insn.rs1() && insn.rd() != insn.rs2());
require_vector(true);
require_align(insn.rd(), P.VU.vflmul);
require_align(insn.rs2(), P.VU.vflmul);

// 2. 获取基本参数和位置计数器
reg_t vl = P.VU.vl->read();
reg_t rd_num = insn.rd();
reg_t rs1_num = insn.rs1();
reg_t rs2_num = insn.rs2();
reg_t pos = 0;  // 目标写入位置，从0开始

// 3. 遍历源向量元素
for (reg_t i = P.VU.vstart->read(); i < vl; ++i) {
  // 3.1 获取掩码位
  const int mpos = i / 8;  // 掩码字节索引
  const int moff = i % 8;  // 掩码位索引
  bool mask_bit = (P.VU.elt<uint8_t>(rs1_num, mpos) >> moff) & 0x1;

  // 3.2 根据掩码位决定是否压缩当前元素
  if (mask_bit) {
    // 只有在目标索引小于vl时才写入
    if (pos < vl) {
      // 拷贝数据（以32位元素为例）
      P.VU.elt<uint32_t>(rd_num, pos) = P.VU.elt<uint32_t>(rs2_num, i);
      pos++;  // 递增目标索引
    }
  }
}

// 4. 重置vstart寄存器
P.VU.vstart->write(0);
```

`vcompress.vm`指令的特殊之处在于它直接使用掩码向量 vs1 控制压缩操作，而不像其他向量指令那样使用 v0.mask 作为条件执行掩码。实现逻辑是扫描源向量 vs2，对每个掩码位为 1 的元素，按顺序写入到目标向量 vd 的连续位置。

### 6. 向量索引生成指令

#### vid.v - 生成向量索引

**指令格式**: `vid.v vd, vm`

**功能**: 生成从 0 开始递增的连续索引值，结果放在 vd 的每个元素中。

**SPIKE 宏展开分析**:

```cpp
// 核心实现
// 1. 验证操作条件
require(P.VU.vsew >= e8 && P.VU.vsew <= e64);
require_vector(true);
require_align(insn.rd(), P.VU.vflmul);

// 2. 获取向量长度和目标寄存器
reg_t vl = P.VU.vl->read();
reg_t rd_num = insn.rd();

// 3. 遍历处理每个元素
for (reg_t i = P.VU.vstart->read(); i < vl; ++i) {
  // 3.1 掩码检查
  bool use_result = true;
  if (!P.VU.get_vm()->read()) {
    // 检查掩码位
    const int mpos = i / 8;
    const int moff = i % 8;
    use_result = (P.VU.get_mask(mpos) >> moff) & 0x1;
  }

  // 3.2 元素处理
  if (use_result) {
    // 为每个元素分配其索引值
    P.VU.set_elt<uint32_t>(rd_num, i, i);
  }
}

// 4. 重置vstart寄存器
P.VU.vstart->write(0);
```

vid.v 指令在向量计算中非常有用，它可以用于生成索引向量，与其他向量指令结合使用实现复杂的数据重组和处理。例如，一个常见的用法是结合 vid.v 和 vrgather.vv 实现矩阵转置。

#### viota.m - 生成前缀和索引表

**指令格式**: `viota.m vd, vs2, vm`

**功能**: 对 vs2 向量中的掩码位进行递增计数，结果放在 vd 中。

**SPIKE 宏展开分析**:

```cpp
// 核心实现
// 1. 验证操作条件
require(P.VU.vsew >= e8 && P.VU.vsew <= e64);
require_vector(true);
require_align(insn.rd(), P.VU.vflmul);
require_align(insn.rs2(), P.VU.vflmul);

// 2. 获取向量长度和寄存器
reg_t vl = P.VU.vl->read();
reg_t rd_num = insn.rd();
reg_t rs2_num = insn.rs2();
reg_t sum = 0;  // 累积计数器

// 3. 遍历处理每个元素
for (reg_t i = P.VU.vstart->read(); i < vl; ++i) {
  // 3.1 掩码检查
  bool use_result = true;
  if (!P.VU.get_vm()->read()) {
    // 检查掩码位
    const int mpos = i / 8;
    const int moff = i % 8;
    use_result = (P.VU.get_mask(mpos) >> moff) & 0x1;
  }

  // 3.2 元素处理
  if (use_result) {
    // 检查源向量的掩码位
    const int mpos = i / 8;
    const int moff = i % 8;
    bool vs2_mask = (P.VU.elt<uint8_t>(rs2_num, mpos) >> moff) & 0x1;

    // 存储当前累积和
    P.VU.set_elt<uint32_t>(rd_num, i, sum);

    // 如果掩码为1，计数增加
    if (vs2_mask) sum++;
  }
}

// 4. 重置vstart寄存器
P.VU.vstart->write(0);
```

`viota.m`指令实现了一个前缀和操作，计算在每个位置之前有多少个掩码位为 1。这在向量压缩操作中很有用，可以计算每个元素在压缩后的目标位置。

## 向量置换与移动指令应用示例

### 1. 使用向量-标量移动指令实现高效初始化

```assembly
# 将向量寄存器中的首元素初始化为常量，其余元素不变
.global _start
.section .text

_start:
    # 假设a0包含数组长度

    # 设置向量环境
    vsetvli t0, a0, e32, m4       # 设置向量长度，32位元素

    # 初始化首元素
    li t1, 0xFF                   # 加载常量到t1
    vmv.s.x v4, t1                # 将常量加载到v4[0]

    # 复制首元素到整个向量
    vrgather.vi v8, v4, 0         # 将v4[0]复制到v8的所有元素
```

### 2. 使用单元素滑动实现高效数组扫描

```assembly
# 使用滑动指令构建三元素滑动窗口
.global _start
.section .text

_start:
    # 假设a0包含数组地址，a1包含数组长度

    # 设置向量环境
    vsetvli t0, a1, e32, m1       # 设置向量长度，32位元素

    # 加载原始数组
    vle32.v v1, (a0)              # 加载向量数据

    # 构建滑动窗口
    vslide1down.vx v2, v1, zero   # v2 = [0, v1[0], v1[1], ...]
    vslide1down.vx v3, v2, zero   # v3 = [0, v2[0], v2[1], ...] = [0, 0, v1[0], ...]

    # 现在v1, v2, v3构成一个三元素滑动窗口，可用于卷积等操作
    # 对于每个位置i，窗口元素为[v3[i], v2[i], v1[i]]
```

### 3. 使用 vcompress 实现条件数据筛选

```assembly
# 筛选出数组中所有正数元素
.global _start
.section .text

_start:
    # 假设a0包含数组地址，a1包含数组长度，a2包含结果地址

    # 设置向量环境
    vsetvli t0, a1, e32, m2       # 设置向量长度，32位元素

    # 加载源数组
    vle32.v v2, (a0)              # 加载向量数据

    # 创建掩码：标记所有正数
    vmslt.vi v0, v2, 0            # 设置掩码：v2[i] < 0 ? 0 : 1
    vmxor.mm v0, v0, v0           # 反转掩码位：现在1表示正数

    # 压缩操作：只保留正数
    vcompress.vm v4, v2, v0       # 使用掩码压缩v2

    # 存储结果
    vse32.v v4, (a2)              # 存储压缩后的向量
```

### 4. 使用整组移动指令实现向量寄存器保存与恢复

```assembly
# 保存和恢复8个向量寄存器
.global _start
.section .text

_start:
    # 假设栈指针已设置，分配空间以保存向量寄存器
    addi sp, sp, -256            # 为8个32字节的向量寄存器分配栈空间

    # 保存向量寄存器v0-v7
    vmv8r.v v16, v0              # 将v0-v7复制到v16-v23

    # 保存到栈
    addi t0, sp, 0
    vs1r.v v16, (t0)             # 保存v16
    addi t0, t0, 32
    vs1r.v v17, (t0)             # 保存v17
    # ... 保存v18-v23 ...

    # 执行计算...

    # 恢复向量寄存器
    addi t0, sp, 0
    vl1r.v v16, (t0)             # 加载v16
    addi t0, t0, 32
    vl1r.v v17, (t0)             # 加载v17
    # ... 加载v18-v23 ...

    vmv8r.v v0, v16              # 将v16-v23复制回v0-v7

    # 释放栈空间
    addi sp, sp, 256
```

### 5. 使用索引指令实现矩阵转置

```assembly
# 4x4矩阵转置
.global _start
.section .text

_start:
    # 假设a0包含源矩阵地址，a1包含目标矩阵地址

    # 设置向量环境
    li t0, 16                    # 总元素数 = 4x4
    vsetvli zero, t0, e32, m4    # 设置向量长度，32位元素

    # 加载整个4x4矩阵
    vle32.v v4, (a0)             # 加载矩阵 v4 = [a0,a1,a2,a3, b0,b1,b2,b3, c0,c1,c2,c3, d0,d1,d2,d3]

    # 创建行主序到列主序的索引向量
    # 索引向量: [0,4,8,12, 1,5,9,13, 2,6,10,14, 3,7,11,15]
    vid.v v0                     # 生成连续索引 [0,1,2,...,15]

    # 计算转置索引
    li t1, 4                     # 矩阵宽度
    vdivu.vx v1, v0, t1          # v1 = v0 / 4 = 行索引
    vrem.vx v2, v0, t1           # v2 = v0 % 4 = 列索引
    vmul.vx v1, v1, t1           # v1 = 行索引 * 4
    vadd.vv v3, v2, v1           # v3 = 列索引 + 行索引*4 = 转置索引

    # 使用计算的索引重排元素
    vrgather.vv v8, v4, v3       # v8 = 转置后的矩阵

    # 存储结果
    vse32.v v8, (a1)             # 存储转置后的矩阵
```

这些示例展示了向量置换和移动指令在各种数据处理场景中的应用，从简单的数据初始化到复杂的矩阵转置操作。通过组合这些指令，可以高效地实现各种向量数据重组和处理任务。
