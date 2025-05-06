# RISC-V 向量算术与逻辑运算指令概述

## 基本概念

向量算术与逻辑指令是 RISC-V 向量扩展(RVV)的核心功能，用于对向量寄存器中的元素执行并行计算操作。这些指令支持多种操作数组合：向量-向量(vv)、向量-标量(vx/vf)和向量-立即数(vi)。

### 指令命名规则

RISC-V 向量指令遵循一致的命名规则：

- `v{op}.{vv|vx|vi}` - 整数/逻辑操作
- `vf{op}.{vv|vf}` - 浮点操作
- 后缀表示操作数类型：
  - `vv` - 向量-向量
  - `vx` - 向量-整数寄存器(x)
  - `vf` - 向量-浮点寄存器(f)
  - `vi` - 向量-立即数

## 指令分类与功能

### 1. 整数算术指令

| 指令类型     | 示例指令   | 功能描述            | 操作                                          |
| ------------ | ---------- | ------------------- | --------------------------------------------- |
| 加法         | `vadd.vv`  | 向量-向量加法       | $v_d[i] = v_{s1}[i] + v_{s2}[i]$              |
| 减法         | `vsub.vv`  | 向量-向量减法       | $v_d[i] = v_{s1}[i] - v_{s2}[i]$              |
| 乘法         | `vmul.vv`  | 向量-向量乘法       | $v_d[i] = v_{s1}[i] \times v_{s2}[i]$         |
| 除法         | `vdiv.vv`  | 向量-向量除法       | $v_d[i] = v_{s1}[i] \div v_{s2}[i]$           |
| 除法(无符号) | `vdivu.vv` | 无符号向量-向量除法 | $v_d[i] = v_{s1}[i] \div v_{s2}[i]$ (无符号)  |
| 取余         | `vrem.vv`  | 向量-向量取余       | $v_d[i] = v_{s1}[i] \bmod v_{s2}[i]$          |
| 取余(无符号) | `vremu.vv` | 无符号向量-向量取余 | $v_d[i] = v_{s1}[i] \bmod v_{s2}[i]$ (无符号) |

### 2. 饱和定点算术指令

| 指令类型         | 示例指令    | 功能描述       | 操作                                           |
| ---------------- | ----------- | -------------- | ---------------------------------------------- |
| 饱和加法         | `vsadd.vv`  | 有符号饱和加法 | $v_d[i] = \text{sat}(v_{s1}[i] + v_{s2}[i])$   |
| 饱和加法(无符号) | `vsaddu.vv` | 无符号饱和加法 | $v_d[i] = \text{sat}_u(v_{s1}[i] + v_{s2}[i])$ |
| 饱和减法         | `vssub.vv`  | 有符号饱和减法 | $v_d[i] = \text{sat}(v_{s1}[i] - v_{s2}[i])$   |
| 饱和减法(无符号) | `vssubu.vv` | 无符号饱和减法 | $v_d[i] = \text{sat}_u(v_{s1}[i] - v_{s2}[i])$ |

### 3. 逻辑运算指令

| 指令类型 | 示例指令  | 功能描述          | 操作                                  |
| -------- | --------- | ----------------- | ------------------------------------- |
| 按位与   | `vand.vv` | 向量-向量按位与   | $v_d[i] = v_{s1}[i] \land v_{s2}[i]$  |
| 按位或   | `vor.vv`  | 向量-向量按位或   | $v_d[i] = v_{s1}[i] \lor v_{s2}[i]$   |
| 按位异或 | `vxor.vv` | 向量-向量按位异或 | $v_d[i] = v_{s1}[i] \oplus v_{s2}[i]$ |

### 4. 位移指令

| 指令类型 | 示例指令  | 功能描述          | 操作                                 |
| -------- | --------- | ----------------- | ------------------------------------ |
| 逻辑左移 | `vsll.vv` | 向量-向量逻辑左移 | $v_d[i] = v_{s1}[i] \ll v_{s2}[i]$   |
| 逻辑右移 | `vsrl.vv` | 向量-向量逻辑右移 | $v_d[i] = v_{s1}[i] \gg_l v_{s2}[i]$ |
| 算术右移 | `vsra.vv` | 向量-向量算术右移 | $v_d[i] = v_{s1}[i] \gg_a v_{s2}[i]$ |

### 5. 最大/最小值指令

| 指令类型       | 示例指令   | 功能描述              | 操作                                    |
| -------------- | ---------- | --------------------- | --------------------------------------- |
| 最大值         | `vmax.vv`  | 有符号向量-向量最大值 | $v_d[i] = \max(v_{s1}[i], v_{s2}[i])$   |
| 最大值(无符号) | `vmaxu.vv` | 无符号向量-向量最大值 | $v_d[i] = \max_u(v_{s1}[i], v_{s2}[i])$ |
| 最小值         | `vmin.vv`  | 有符号向量-向量最小值 | $v_d[i] = \min(v_{s1}[i], v_{s2}[i])$   |
| 最小值(无符号) | `vminu.vv` | 无符号向量-向量最小值 | $v_d[i] = \min_u(v_{s1}[i], v_{s2}[i])$ |

### 6. 向量带进位/借位算术指令

| 指令类型           | 示例指令   | 功能描述            | 操作                                                            |
| ------------------ | ---------- | ------------------- | --------------------------------------------------------------- |
| 带进位加法         | `vadc.vv`  | 带进位向量-向量加法 | $v_d[i] = v_{s1}[i] + v_{s2}[i] + v0.mask[i]$                   |
| 带进位加法生成进位 | `vmadc.vv` | 加法进位生成        | $v_d.mask[i] = carry\_out(v_{s1}[i] + v_{s2}[i] + v0.mask[i])$  |
| 带借位减法         | `vsbc.vv`  | 带借位向量-向量减法 | $v_d[i] = v_{s1}[i] - v_{s2}[i] - v0.mask[i]$                   |
| 带借位减法生成借位 | `vmsbc.vv` | 减法借位生成        | $v_d.mask[i] = borrow\_out(v_{s1}[i] - v_{s2}[i] - v0.mask[i])$ |

### 7. 向量整数扩展指令

| 指令类型 | 示例指令    | 功能描述            | 操作                                           |
| -------- | ----------- | ------------------- | ---------------------------------------------- |
| 零扩展   | `vzext.vf2` | 零扩展到 2 倍宽度   | $v_d[i] = zext(v_s[i])$，宽度扩展到原来的 2 倍 |
| 零扩展   | `vzext.vf4` | 零扩展到 4 倍宽度   | $v_d[i] = zext(v_s[i])$，宽度扩展到原来的 4 倍 |
| 零扩展   | `vzext.vf8` | 零扩展到 8 倍宽度   | $v_d[i] = zext(v_s[i])$，宽度扩展到原来的 8 倍 |
| 符号扩展 | `vsext.vf2` | 符号扩展到 2 倍宽度 | $v_d[i] = sext(v_s[i])$，宽度扩展到原来的 2 倍 |
| 符号扩展 | `vsext.vf4` | 符号扩展到 4 倍宽度 | $v_d[i] = sext(v_s[i])$，宽度扩展到原来的 4 倍 |
| 符号扩展 | `vsext.vf8` | 符号扩展到 8 倍宽度 | $v_d[i] = sext(v_s[i])$，宽度扩展到原来的 8 倍 |

### 8. 向量宽度转换算术指令

| 指令类型         | 示例指令    | 功能描述                | 操作                                                                 |
| ---------------- | ----------- | ----------------------- | -------------------------------------------------------------------- |
| 宽化加法         | `vwadd.vv`  | 宽化向量-向量加法       | $v_d[i] = sext(v_{s1}[i]) + sext(v_{s2}[i])$，结果是两倍 SEW 宽度    |
| 宽化无符号加法   | `vwaddu.vv` | 宽化无符号向量-向量加法 | $v_d[i] = zext(v_{s1}[i]) + zext(v_{s2}[i])$，结果是两倍 SEW 宽度    |
| 宽化减法         | `vwsub.vv`  | 宽化向量-向量减法       | $v_d[i] = sext(v_{s1}[i]) - sext(v_{s2}[i])$，结果是两倍 SEW 宽度    |
| 宽化无符号减法   | `vwsubu.vv` | 宽化无符号向量-向量减法 | $v_d[i] = zext(v_{s1}[i]) - zext(v_{s2}[i])$，结果是两倍 SEW 宽度    |
| 宽化乘法         | `vwmul.vv`  | 宽化向量-向量乘法       | $v_d[i] = v_{s1}[i] \times v_{s2}[i]$，结果是两倍 SEW 宽度           |
| 宽化无符号乘法   | `vwmulu.vv` | 宽化无符号向量-向量乘法 | $v_d[i] = v_{s1}[i] \times v_{s2}[i]$ (无符号)，结果是两倍 SEW 宽度  |
| 已宽化操作数加法 | `vwadd.wv`  | 已宽化-向量加法         | $v_d[i] = v_{s1}[i] + sext(v_{s2}[i])$，$v_{s1}[i]$已是两倍 SEW 宽度 |
| 已宽化操作数减法 | `vwsub.wv`  | 已宽化-向量减法         | $v_d[i] = v_{s1}[i] - sext(v_{s2}[i])$，$v_{s1}[i]$已是两倍 SEW 宽度 |

### 9. 向量整数缩窄指令

| 指令类型         | 示例指令     | 功能描述       | 操作                                                                                     |
| ---------------- | ------------ | -------------- | ---------------------------------------------------------------------------------------- |
| 缩窄逻辑右移     | `vnsrl.wv`   | 缩窄逻辑右移   | $v_d[i] = (v_{s1}[i] \gg v_{s2}[i])[SEW-1:0]$，将 2\*SEW 宽度的源操作数缩窄到 SEW 宽度   |
| 缩窄算术右移     | `vnsra.wv`   | 缩窄算术右移   | $v_d[i] = (v_{s1}[i] \gg_a v_{s2}[i])[SEW-1:0]$，将 2\*SEW 宽度的源操作数缩窄到 SEW 宽度 |
| 缩窄裁剪         | `vnclip.wv`  | 有符号缩窄裁剪 | $v_d[i] = clip(round((v_{s1}[i] \gg v_{s2}[i])[SEW-1:0]))$                               |
| 缩窄裁剪(无符号) | `vnclipu.wv` | 无符号缩窄裁剪 | $v_d[i] = clip_u(round((v_{s1}[i] \gg v_{s2}[i])[SEW-1:0]))$                             |

### 10. 向量整数乘加指令

| 指令类型         | 示例指令     | 功能描述                | 操作                                                                              |
| ---------------- | ------------ | ----------------------- | --------------------------------------------------------------------------------- |
| 乘加             | `vmacc.vv`   | 向量-向量乘加           | $v_d[i] = v_d[i] + (v_{s1}[i] \times v_{s2}[i])$                                  |
| 乘加(宽化)       | `vwmacc.vv`  | 宽化向量-向量乘加       | $v_d[i] = v_d[i] + (sext(v_{s1}[i]) \times sext(v_{s2}[i]))$，结果是两倍 SEW 宽度 |
| 乘加(无符号宽化) | `vwmaccu.vv` | 无符号宽化向量-向量乘加 | $v_d[i] = v_d[i] + (zext(v_{s1}[i]) \times zext(v_{s2}[i]))$，结果是两倍 SEW 宽度 |
| 乘加源           | `vmadd.vv`   | 向量-向量乘加源         | $v_d[i] = v_{s1}[i] + (v_d[i] \times v_{s2}[i])$                                  |
| 乘减             | `vnmsac.vv`  | 向量-向量乘减           | $v_d[i] = v_d[i] - (v_{s1}[i] \times v_{s2}[i])$                                  |
| 乘减源           | `vnmsub.vv`  | 向量-向量乘减源         | $v_d[i] = v_{s1}[i] - (v_d[i] \times v_{s2}[i])$                                  |

## 指令格式与元素处理详解

### 通用指令格式

所有向量算术和逻辑指令遵循相似的元素处理规则：

| 索引范围                           | 元素处理                  |
| ---------------------------------- | ------------------------- |
| $0 \leq i < \text{vstart}$         | 元素不变                  |
| $\text{vstart} \leq i < \text{vl}$ | 执行指定操作 (受掩码控制) |
| $\text{vl} \leq i < \text{VLMAX}$  | 根据尾部策略处理          |

### 掩码处理规则

掩码位($v0.\text{mask}[i]$)控制对应位置的操作是否执行：

- 当$\text{mask}[i]=1$或未指定掩码时，执行操作
- 当$\text{mask}[i]=0$时，根据掩码策略处理：
  - $v_d[i] = v_{s1}[i]$ (掩码未开启值)
  - $v_d[i]$不变 (掩码不扰动)

## SPIKE 模拟器实现与指令详解

### 1. 向量-向量整数加法 (vadd.vv)

**指令格式**: `vadd.vv vd, vs2, vs1, vm`

**功能**: 将 vs1 和 vs2 的对应元素相加，结果存入 vd 中。

**SPIKE 实现**:

```cpp
// 在riscv-isa-sim/riscv/insns/vadd_vv.h
VI_VV_LOOP
({
  vd = vs1 + vs2;
})
```

**宏展开分析**:  
`VI_VV_LOOP`宏展开后，`vadd.vv`的实际执行流程如下：

```cpp
// 1. 检查向量操作条件
require(P.VU.vsew >= e8 && P.VU.vsew <= e64);
require_vector(true);
require_align(insn.rd(), P.VU.vflmul);
require_align(insn.rs1(), P.VU.vflmul);
require_align(insn.rs2(), P.VU.vflmul);

// 2. 获取基本参数
reg_t vl = P.VU.vl->read();
reg_t rd_num = insn.rd();
reg_t rs1_num = insn.rs1();
reg_t rs2_num = insn.rs2();

// 3. 根据元素宽度(SEW)处理不同的数据类型
switch (P.VU.vsew) {
  case e8: {
    // 处理8位元素
    VI_VV_LOOP_BODY(int8_t, 1)
    break;
  }
  case e16: {
    // 处理16位元素
    VI_VV_LOOP_BODY(int16_t, 2)
    break;
  }
  case e32: {
    // 处理32位元素
    VI_VV_LOOP_BODY(int32_t, 4)
    break;
  }
  default: {
    // 处理64位元素
    VI_VV_LOOP_BODY(int64_t, 8)
    break;
  }
}

// VI_VV_LOOP_BODY展开(以32位为例)
for (reg_t i = P.VU.vstart->read(); i < vl; ++i) {
  // 掩码处理 - 检查是否需要执行该元素
  bool do_op = P.VU.get_vm()->read() || (P.VU.get_mask(i) & 0x1);

  if (do_op) {
    // 获取操作数
    int32_t vs1 = P.VU.elt<int32_t>(rs1_num, i);
    int32_t vs2 = P.VU.elt<int32_t>(rs2_num, i);

    // 执行核心操作
    int32_t vd = vs1 + vs2;

    // 存储结果
    P.VU.elt<int32_t>(rd_num, i) = vd;
  }
}

// 重置vstart = 0
P.VU.vstart->write(0);
```

### 2. 向量-标量整数加法 (vadd.vx)

**指令格式**: `vadd.vx vd, vs2, rs1, vm`

**功能**: 将向量 vs2 的每个元素与标量寄存器 rs1 的值相加，结果存入 vd 中。

**SPIKE 实现**:

```cpp
// 在riscv-isa-sim/riscv/insns/vadd_vx.h
VI_VX_LOOP
({
  vd = rs1 + vs2;
})
```

**宏展开分析**:  
`VI_VX_LOOP`宏类似于`VI_VV_LOOP`，主要区别在于一个操作数是标量而非向量。它从通用寄存器获取 rs1 值，并将其用于每个向量元素的操作。

```cpp
// 核心实现区别
reg_t rs1 = RS1; // 从通用寄存器获取标量值

// 在循环中
for (reg_t i = P.VU.vstart->read(); i < vl; ++i) {
  // ...
  int32_t vs2 = P.VU.elt<int32_t>(rs2_num, i);

  // 执行核心操作 - 注意rs1是标量
  int32_t vd = rs1 + vs2;

  // ...
}
```

### 3. 饱和加法 (vsadd.vv)

**指令格式**: `vsadd.vv vd, vs2, vs1, vm`

**功能**: 执行有符号饱和加法，确保结果在元素类型的有效范围内。

**SPIKE 实现**:

```cpp
// 在riscv-isa-sim/riscv/insns/vsadd_vv.h
VI_VV_LOOP
({
  vd = sat_add<int8_t>(vs1, vs2, 1);
})
```

**宏展开分析**:  
饱和运算确保结果不会溢出，如果计算结果超出数据类型范围，将截断为该类型能表示的最大/最小值。

```cpp
// sat_add实现
template<typename T>
inline T sat_add(T x, T y, bool sign) {
  // 使用更大位宽类型避免溢出检测
  typedef typename std::make_signed<typename double_width<T>::type>::type S;
  S s = S(x) + S(y);

  // 有符号检查
  if (sign) {
    S min = S(std::numeric_limits<T>::min());
    S max = S(std::numeric_limits<T>::max());
    return s < min ? min : (s > max ? max : s);
  }
  // 无符号检查
  else {
    typename double_width<T>::type U =
      typename double_width<T>::type(x) +
      typename double_width<T>::type(y);
    typename double_width<T>::type max =
      typename double_width<T>::type(std::numeric_limits<T>::max());
    return U > max ? max : U;
  }
}
```

### 4. 位操作指令 (vand.vv)

**指令格式**: `vand.vv vd, vs2, vs1, vm`

**功能**: 执行向量元素间的按位与操作。

**SPIKE 实现**:

```cpp
// 在riscv-isa-sim/riscv/insns/vand_vv.h
VI_VV_LOOP
({
  vd = vs1 & vs2;
})
```

位操作指令实现简单直接，直接使用 C++的位操作符对元素进行操作。

### 5. 最大/最小值指令 (vmax.vv)

**指令格式**: `vmax.vv vd, vs2, vs1, vm`

**功能**: 选择 vs1 和 vs2 对应元素中的最大值。

**SPIKE 实现**:

```cpp
// 在riscv-isa-sim/riscv/insns/vmax_vv.h
VI_VV_LOOP
({
  vd = std::max(vs1, vs2);
})
```

对于有符号和无符号的差异，在数据类型上反映：有符号操作使用有符号类型(`int8_t`等)，无符号操作使用无符号类型(`uint8_t`等)。

### 6. 整数宽化指令 (vwadd.vv)

**指令格式**: `vwadd.vv vd, vs2, vs1, vm`

**功能**: 将 vs1 和 vs2 的元素宽化为两倍 SEW 后相加，结果存储在 vd 中。

**SPIKE 实现**:

```cpp
// 在riscv-isa-sim/riscv/insns/vwadd_vv.h
VI_VV_LOOP_WIDE
({
  vd = (type_sew_t<2*SEW>::type)vs1 + (type_sew_t<2*SEW>::type)vs2;
})
```

**宏展开分析**:  
宽化操作将输入操作数扩展到更大的位宽度，执行操作后结果也使用更大的位宽度存储。这通常需要更多的寄存器空间来存储结果。

## 向量算术与逻辑指令应用示例

### 1. 向量元素乘 2 加 1 操作

```assembly
# 对数组每个元素执行 2*x + 1 运算
.global _start
.section .text

_start:
    # 假设a0包含数组地址，a1包含数组长度，a2包含目标地址

    # 设置向量环境
    vsetvli t0, a1, e32, m4       # 设置向量长度，32位元素

    # 载入向量数据
    vle32.v v4, (a0)              # 加载源数组到v4

    # 执行2*x + 1操作
    li t1, 2                      # 加载乘数2到t1
    vmul.vx v8, v4, t1            # v8 = v4 * 2
    li t1, 1                      # 加载加数1到t1
    vadd.vx v8, v8, t1            # v8 = v8 + 1

    # 存储结果
    vse32.v v8, (a2)              # 保存结果到目标地址
```

### 2. 向量条件最大值计算

```assembly
# 计算两个向量的条件最大值(负数取最大，正数取最小)
.global _start
.section .text

_start:
    # 假设a0包含第一个数组地址，a1包含第二个数组地址
    # a2包含数组长度，a3包含目标地址

    # 设置向量环境
    vsetvli t0, a2, e32, m2       # 设置向量长度，32位元素

    # 载入向量数据
    vle32.v v2, (a0)              # 加载第一个数组到v2
    vle32.v v4, (a1)              # 加载第二个数组到v4

    # 创建掩码 - 标记负数
    vmslt.vx v0, v2, zero         # v0.mask[i] = v2[i] < 0 ? 1 : 0

    # 选择性执行最大或最小值操作
    vmax.vv v6, v2, v4, v0.t      # 对负数: v6 = max(v2, v4)
    vmin.vv v6, v2, v4, !v0.t     # 对正数: v6 = min(v2, v4)

    # 存储结果
    vse32.v v6, (a3)              # 保存结果到目标地址
```

### 3. 饱和加法用于图像处理

```assembly
# 图像增亮处理 - 添加亮度值且防止溢出
.global _start
.section .text

_start:
    # 假设a0包含图像数据地址，a1包含像素数量
    # a2包含亮度增量值，a3包含结果地址

    # 设置向量环境
    vsetvli t0, a1, e8, m4        # 设置向量长度，8位元素(每像素一字节)

    # 载入图像数据
    vle8.v v4, (a0)               # 加载像素数据

    # 执行饱和加法 - 增加亮度且防止溢出
    vsaddu.vx v8, v4, a2          # v8 = sat(v4 + brightness_value)

    # 存储结果
    vse8.v v8, (a3)               # 保存处理后的像素数据
```

### 4. 位操作实现掩码应用

```assembly
# 使用位操作实现数据过滤(例如保留特定位字段)
.global _start
.section .text

_start:
    # 假设a0包含数据地址，a1包含数据数量
    # a2包含位掩码，a3包含结果地址

    # 设置向量环境
    vsetvli t0, a1, e32, m2       # 设置向量长度，32位元素

    # 载入数据
    vle32.v v2, (a0)              # 加载数据

    # 应用位掩码
    vand.vx v4, v2, a2            # 应用AND掩码，保留指定位

    # 存储结果
    vse32.v v4, (a3)              # 保存过滤后的数据
```

### 5. 复合运算与向量链

```assembly
# 实现复杂公式如 y = (a + b) * (a - b)
.global _start
.section .text

_start:
    # 假设a0包含a数组地址，a1包含b数组地址
    # a2包含元素数量，a3包含结果地址

    # 设置向量环境
    vsetvli t0, a2, e32, m2       # 设置向量长度，32位元素

    # 载入输入数据
    vle32.v v2, (a0)              # 加载a数组
    vle32.v v4, (a1)              # 加载b数组

    # 计算(a+b)和(a-b)
    vadd.vv v6, v2, v4            # v6 = a + b
    vsub.vv v8, v2, v4            # v8 = a - b

    # 计算最终结果(a+b)*(a-b)
    vmul.vv v10, v6, v8           # v10 = v6 * v8 = (a+b)*(a-b)

    # 存储结果
    vse32.v v10, (a3)             # 保存计算结果
```

### 6. 向量宽化示例

```assembly
# 使用宽化指令处理低精度数据
.global _start
.section .text

_start:
    # 假设a0包含8位数据地址，a1包含元素数量
    # a2包含结果地址

    # 设置向量环境 - 处理8位数据
    vsetvli t0, a1, e8, m1        # 设置向量长度，8位元素

    # 载入8位数据
    vle8.v v1, (a0)               # 加载8位数据

    # 使用宽化加法 - 结果扩展为16位
    vwaddu.vx v2, v1, zero        # v2 = 零扩展(v1)，16位结果

    # 继续宽化到32位
    vsetvli t0, a1, e16, m2       # 切换到16位元素模式
    vwaddu.vx v4, v2, zero        # v4 = 零扩展(v2)，32位结果

    # 存储32位结果
    vsetvli t0, a1, e32, m4       # 切换到32位元素模式
    vse32.v v4, (a2)              # 保存32位结果
```

这些示例展示了向量算术和逻辑指令在各种数据处理场景中的应用，从简单的元素运算到复杂的条件处理和复合算法。通过组合这些指令，可以高效实现各种向量计算任务。
