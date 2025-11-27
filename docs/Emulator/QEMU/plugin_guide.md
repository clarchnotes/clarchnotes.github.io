# QEMU 插件开发完全指南

## QEMU 插件基础

### QEMU 简介

QEMU（Quick Emulator）是一个开源的处理器模拟器，通过**动态二进制翻译（Dynamic Binary Translation, DBT）**技术，可以在一个架构上模拟运行另一个架构的程序。

**工作模式：**

- **系统模式（System Mode）**：模拟完整的计算机系统（包括操作系统、设备）
- **用户模式（User Mode）**：只模拟用户态程序（使用主机操作系统）

**常见应用场景：**

- 跨架构开发：在 x86 机器上开发 ARM/RISC-V 程序
- 性能分析：统计指令执行、内存访问模式
- 安全研究：模糊测试、漏洞分析
- 教学研究：理解程序行为、架构特性

### QEMU 插件机制

QEMU 插件是一个**动态链接库（.so 文件）**，通过 QEMU 的 Plugin API 在程序执行时插入自定义代码，实现对程序行为的监控和分析。

**核心特点：**

| 特性 | 说明 | 优势 |
|------|------|------|
| **零侵入** | 不修改目标程序二进制 | 保证原始行为不变 |
| **确定性** | 相同输入产生相同结果 | 便于调试和复现 |
| **全面观测** | 可见所有指令和内存访问 | 比硬件 PMU 更灵活 |
| **跨平台** | 插件代码与架构无关 | 一次编写，多处使用 |

**技术原理：**

```
┌─────────────────────────────────────────────┐
│  目标程序（如 RISC-V 可执行文件）            │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│  QEMU 前端：解码目标指令                     │
│  • 解析二进制编码                            │
│  • 插件在此插入钩子                          │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│  QEMU 后端：生成主机代码（x86）              │
│  • 优化、寄存器分配                          │
│  • 插件回调被编译进去                        │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│  执行主机代码 + 插件逻辑                     │
└─────────────────────────────────────────────┘
```

### 插件可以做什么？

**1. 指令统计**

- 计数不同类型的指令（浮点、向量、访存等）
- 识别热点代码（最频繁执行的指令）

**2. 性能分析**

- 模拟缓存行为
- 分析分支预测准确率
- 评估向量化效果

**3. 内存追踪**

- 记录所有 load/store 操作
- 检测内存访问模式
- 发现内存泄漏

**4. 覆盖率测试**

- 记录执行过的代码块
- 生成覆盖率报告

**5. 安全分析**

- 检测异常行为（栈溢出、非法访问）
- 污点分析（数据流追踪）

---

## 插件工作原理

### 动态二进制翻译（DBT）

QEMU 使用 **TCG（Tiny Code Generator）** 技术：

**翻译过程：**

```
原始机器码（Guest Architecture）
         ↓
    解码 & 分析
         ↓
  TCG 中间表示（IR）  ← 插件在这里插入回调
         ↓
    优化 & 生成
         ↓
主机机器码（Host Architecture）
```

### 翻译块（Translation Block, TB）

QEMU 以**基本块**为单位翻译代码。

**基本块定义：**

- 单一入口（一个跳转目标）
- 顺序执行（内部无分支）
- 明确出口（以跳转/分支结束）

**示例：C 代码到 TB 的映射**

```c
int sum = 0;
for (int i = 0; i < 10; i++) {
    sum += array[i];
}
```

对应的 TB 结构：

```
TB1: loop_header
    i = load(i_addr)
    if i >= 10: jump TB3
    fall_through TB2

TB2: loop_body
    tmp = load(array + i*4)
    sum = sum + tmp
    i = i + 1
    jump TB1

TB3: loop_exit
    return
```

**TB 缓存机制：**

- 首次执行：翻译 → 缓存
- 后续执行：直接查找缓存（快速路径）
- 缓存满：淘汰旧 TB

### 插件介入时机

插件通过 **回调函数（Callback）** 机制工作：

**两类回调：**

| 回调类型 | 调用时机 | 频率 | 用途 |
|---------|---------|------|------|
| **翻译时回调** | TB 首次翻译时 | 每个 TB 一次 | 分析指令、注册钩子 |
| **执行时回调** | 指令实际执行时 | 每次执行都调用 | 统计、追踪、记录 |

**示例：统计指令数**

```
翻译时：
  vcpu_tb_trans(TB) {
    for each insn in TB:
      register_callback(insn, count_insn)
  }

执行时：
  count_insn() {
    insn_count++;
  }
```

### 插件生命周期

```
┌────────────────────────────────────────┐
│ 1. QEMU 启动                            │
│    qemu-riscv64 -plugin my_plugin.so   │
└──────────────┬─────────────────────────┘
               │
               ▼
┌────────────────────────────────────────┐
│ 2. 加载插件                             │
│    qemu_plugin_install()               │
│    • 解析参数                           │
│    • 初始化数据                         │
│    • 注册回调                           │
└──────────────┬─────────────────────────┘
               │
               ▼
┌────────────────────────────────────────┐
│ 3. 程序执行循环                         │
│  ┌──────────────────────────────────┐  │
│  │ 遇到新代码 → 翻译                 │  │
│  │ vcpu_tb_trans()                  │  │
│  │ • 分析每条指令                    │  │
│  │ • 注册 exec 回调                  │  │
│  └──────────────────────────────────┘  │
│  ┌──────────────────────────────────┐  │
│  │ 执行 TB                           │  │
│  │ vcpu_insn_exec() (反复调用)       │  │
│  │ • 更新统计                        │  │
│  │ • 记录事件                        │  │
│  └──────────────────────────────────┘  │
└──────────────┬─────────────────────────┘
               │
               ▼
┌────────────────────────────────────────┐
│ 4. 程序退出                             │
│    plugin_exit()                       │
│    • 打印报告                           │
│    • 清理资源                           │
└────────────────────────────────────────┘
```

---

## QEMU Plugin API 详解

### 必需的插件函数

#### 1. 插件入口点

```c
#include <qemu-plugin.h>

QEMU_PLUGIN_EXPORT int qemu_plugin_install(
    qemu_plugin_id_t id,        // 插件唯一ID
    const qemu_info_t *info,    // QEMU版本和目标架构信息
    int argc,                   // 命令行参数数量
    char **argv                 // 命令行参数数组
)
{
    // 初始化插件
    // 注册回调
    return 0;  // 成功返回0
}
```

**参数解析示例：**

```c
int qemu_plugin_install(qemu_plugin_id_t id, const qemu_info_t *info,
                        int argc, char **argv)
{
    for (int i = 0; i < argc; i++) {
        g_auto(GStrv) tokens = g_strsplit(argv[i], "=", 2);
        
        if (g_strcmp0(tokens[0], "verbose") == 0) {
            verbose = true;
        }
        else if (g_strcmp0(tokens[0], "output") == 0) {
            output_file = g_strdup(tokens[1]);
        }
        else if (g_strcmp0(tokens[0], "threshold") == 0) {
            threshold = g_ascii_strtoull(tokens[1], NULL, 10);
        }
    }
    
    // 获取 QEMU 信息
    fprintf(stderr, "Target: %s\n", info->target_name);
    
    // 注册回调
    qemu_plugin_register_vcpu_tb_trans_cb(id, vcpu_tb_trans);
    qemu_plugin_register_atexit_cb(id, plugin_exit, NULL);
    
    return 0;
}
```

**命令行使用：**

```bash
qemu-riscv64 -plugin ./my_plugin.so,verbose=1,output=report.txt program
```

### TB（翻译块）相关 API

#### 注册 TB 翻译回调

```c
void qemu_plugin_register_vcpu_tb_trans_cb(
    qemu_plugin_id_t id,
    qemu_plugin_vcpu_tb_trans_cb_t cb
);

// 回调函数签名
void vcpu_tb_trans(qemu_plugin_id_t id, struct qemu_plugin_tb *tb);
```

#### TB 信息查询

```c
// 获取 TB 中的指令数量
size_t qemu_plugin_tb_n_insns(const struct qemu_plugin_tb *tb);

// 获取第 i 条指令
struct qemu_plugin_insn *qemu_plugin_tb_get_insn(
    const struct qemu_plugin_tb *tb,
    size_t idx
);

// 获取 TB 的虚拟地址
uint64_t qemu_plugin_tb_vaddr(const struct qemu_plugin_tb *tb);
```

**示例：统计每个 TB 的大小**

```c
static void vcpu_tb_trans(qemu_plugin_id_t id, struct qemu_plugin_tb *tb)
{
    size_t n = qemu_plugin_tb_n_insns(tb);
    uint64_t addr = qemu_plugin_tb_vaddr(tb);
    
    printf("TB at 0x%lx: %zu instructions\n", addr, n);
}
```

### 指令相关 API

#### 注册指令执行回调

```c
void qemu_plugin_register_vcpu_insn_exec_cb(
    struct qemu_plugin_insn *insn,
    qemu_plugin_vcpu_udata_cb_t cb,
    enum qemu_plugin_cb_flags flags,
    void *userdata                     // 自定义数据指针
);

// 回调函数签名
void vcpu_insn_exec(unsigned int cpu_index, void *userdata);
```

**flags 选项：**

| Flag | 说明 | 性能影响 |
|------|------|----------|
| `QEMU_PLUGIN_CB_NO_REGS` | 不需要寄存器访问 | 最快 |
| `QEMU_PLUGIN_CB_R_REGS` | 需要读取寄存器 | 较慢 |
| `QEMU_PLUGIN_CB_RW_REGS` | 需要读写寄存器 | 最慢 |

#### 指令信息查询

```c
// 获取指令的二进制编码
size_t qemu_plugin_insn_data(
    const struct qemu_plugin_insn *insn,
    void *dest,
    size_t len
);

// 获取指令虚拟地址
uint64_t qemu_plugin_insn_vaddr(const struct qemu_plugin_insn *insn);

// 获取指令大小（字节）
size_t qemu_plugin_insn_size(const struct qemu_plugin_insn *insn);

// 获取汇编文本（如果支持反汇编）
char *qemu_plugin_insn_disas(const struct qemu_plugin_insn *insn);

// 获取符号信息（函数名等）
const char *qemu_plugin_insn_symbol(const struct qemu_plugin_insn *insn);
```

**示例：打印每条指令**

```c
static void vcpu_tb_trans(qemu_plugin_id_t id, struct qemu_plugin_tb *tb)
{
    size_t n = qemu_plugin_tb_n_insns(tb);
    
    for (size_t i = 0; i < n; i++) {
        struct qemu_plugin_insn *insn = qemu_plugin_tb_get_insn(tb, i);
        uint64_t addr = qemu_plugin_insn_vaddr(insn);
        char *disas = qemu_plugin_insn_disas(insn);
        
        printf("0x%lx: %s\n", addr, disas);
        g_free(disas);
    }
}
```

### 内存访问 API

#### 注册内存访问回调

```c
void qemu_plugin_register_vcpu_mem_cb(
    struct qemu_plugin_insn *insn,
    qemu_plugin_vcpu_mem_cb_t cb,
    enum qemu_plugin_cb_flags flags,
    enum qemu_plugin_mem_rw rw,
    void *userdata
);

// 回调函数签名
void vcpu_mem_cb(
    unsigned int cpu_index,
    qemu_plugin_meminfo_t info,
    uint64_t vaddr,
    void *userdata
);
```

**rw 参数：**

- `QEMU_PLUGIN_MEM_R`：只监控读操作
- `QEMU_PLUGIN_MEM_W`：只监控写操作
- `QEMU_PLUGIN_MEM_RW`：监控读写

**meminfo 查询：**

```c
// 访问是否为存储操作
bool qemu_plugin_mem_is_store(qemu_plugin_meminfo_t info);

// 获取访问大小（字节）
unsigned int qemu_plugin_mem_size_shift(qemu_plugin_meminfo_t info);
// 实际大小 = 1 << shift
```

**示例：追踪内存访问**

```c
static void vcpu_mem_access(unsigned int cpu_index, 
                           qemu_plugin_meminfo_t info,
                           uint64_t vaddr, void *udata)
{
    bool is_store = qemu_plugin_mem_is_store(info);
    unsigned int size = 1 << qemu_plugin_mem_size_shift(info);
    
    printf("%s @ 0x%lx, size=%u\n", 
           is_store ? "STORE" : "LOAD", vaddr, size);
}

static void vcpu_tb_trans(qemu_plugin_id_t id, struct qemu_plugin_tb *tb)
{
    size_t n = qemu_plugin_tb_n_insns(tb);
    
    for (size_t i = 0; i < n; i++) {
        struct qemu_plugin_insn *insn = qemu_plugin_tb_get_insn(tb, i);
        
        qemu_plugin_register_vcpu_mem_cb(insn, vcpu_mem_access,
                                         QEMU_PLUGIN_CB_NO_REGS,
                                         QEMU_PLUGIN_MEM_RW, NULL);
    }
}
```

### 退出回调

```c
void qemu_plugin_register_atexit_cb(
    qemu_plugin_id_t id,
    qemu_plugin_simple_cb_t cb,
    void *userdata
);

// 回调函数签名
void plugin_exit(qemu_plugin_id_t id, void *userdata);
```

**示例：打印统计报告**

```c
static uint64_t insn_count = 0;

static void plugin_exit(qemu_plugin_id_t id, void *p)
{
    printf("Total instructions executed: %lu\n", insn_count);
}
```

### 线程安全工具

插件可能在多核CPU上运行，需要线程安全：

```c
#include <glib.h>

// 互斥锁
GMutex lock;
g_mutex_init(&lock);
g_mutex_lock(&lock);
// ... 临界区 ...
g_mutex_unlock(&lock);

// 哈希表（键值存储）
GHashTable *map = g_hash_table_new(g_direct_hash, g_direct_equal);
g_hash_table_insert(map, GUINT_TO_POINTER(key), GUINT_TO_POINTER(value));
gpointer value = g_hash_table_lookup(map, GUINT_TO_POINTER(key));
```

---

## 指令分析与分类

### 为什么需要指令分类？

不同指令类型反映不同的性能特征：

| 指令类型 | 性能瓶颈 | 优化方向 |
|---------|---------|----------|
| **浮点运算** | FPU 吞吐量 | 指令级并行（ILP）|
| **向量指令** | SIMD 单元 | 向量化、数据对齐 |
| **访存指令** | 内存带宽、缓存 | 数据局部性、预取 |
| **分支指令** | 流水线停顿 | 分支消除、预测优化 |
| **整数运算** | ALU 依赖链 | 指令调度 |

### RISC-V 指令编码基础

RISC-V 使用 7 位 opcode 标识指令类型：

```
标准指令（32-bit）格式：
[31:25] [24:20] [19:15] [14:12] [11:7] [6:0]
funct7   rs2     rs1    funct3   rd    opcode
```

**常见 opcode：**

| Opcode | 值 | 指令类型 | 示例 |
|--------|-----|----------|------|
| LOAD | 0x03 | 加载指令 | `ld`, `lw`, `lh` |
| STORE | 0x23 | 存储指令 | `sd`, `sw`, `sh` |
| BRANCH | 0x63 | 分支指令 | `beq`, `bne`, `blt` |
| JAL | 0x6F | 跳转链接 | `jal` |
| JALR | 0x67 | 间接跳转 | `jalr` |
| OP-IMM | 0x13 | 立即数运算 | `addi`, `slti` |
| OP | 0x33 | 寄存器运算 | `add`, `sub`, `mul` |
| OP-FP | 0x53 | 浮点运算 | `fadd.d`, `fmul.s` |
| MADD | 0x43 | 浮点乘加 | `fmadd.s` |
| VECTOR | 0x57 | 向量指令 | `vadd.vv` |

### 指令分类实现

```c
enum InsnClass {
    CLASS_LOAD_STORE,
    CLASS_BRANCH,
    CLASS_SCALAR_FP,
    CLASS_VECTOR,
    CLASS_DATA_PROC,
    CLASS_OTHER
};

static enum InsnClass classify_riscv_insn(uint32_t insn)
{
    uint32_t opcode = insn & 0x7F;
    
    // 访存指令
    if (opcode == 0x03 || opcode == 0x23 || opcode == 0x07 || opcode == 0x27) {
        return CLASS_LOAD_STORE;
    }
    
    // 分支跳转
    if (opcode == 0x63 || opcode == 0x6F || opcode == 0x67) {
        return CLASS_BRANCH;
    }
    
    // 浮点运算
    if ((opcode >= 0x43 && opcode <= 0x4F && (opcode & 0x3) == 0x3) ||
        opcode == 0x53) {
        return CLASS_SCALAR_FP;
    }
    
    // 向量指令
    if (opcode == 0x57) {
        return CLASS_VECTOR;
    }
    
    // 整数运算
    if (opcode == 0x13 || opcode == 0x33 || opcode == 0x37 ||
        opcode == 0x17 || opcode == 0x1B || opcode == 0x3B) {
        return CLASS_DATA_PROC;
    }
    
    return CLASS_OTHER;
}
```

### 压缩指令（RVC）支持

RISC-V 压缩扩展使用 16-bit 编码：

```
压缩指令格式：
[15:13] [12:10] [9:7] [6:5] [4:2] [1:0]
funct3  ...     ...   ...   ...   op
```

**op（低2位）标识 Quadrant：**

- 00, 01, 10：不同的压缩格式
- 11：32-bit 指令标记

```c
static enum InsnClass classify_compressed_insn(uint16_t c_insn)
{
    uint16_t c_op = c_insn & 0x3;
    uint16_t c_funct3 = (c_insn >> 13) & 0x7;
    
    // Quadrant 0
    if (c_op == 0) {
        if (c_funct3 == 2 || c_funct3 == 3 || c_funct3 == 6 || c_funct3 == 7) {
            return CLASS_LOAD_STORE;  // C.LW, C.LD, C.SW, C.SD
        }
    }
    
    // Quadrant 1
    if (c_op == 1) {
        if (c_funct3 == 5 || c_funct3 == 6 || c_funct3 == 7) {
            return CLASS_BRANCH;  // C.J, C.BEQZ, C.BNEZ
        }
        return CLASS_DATA_PROC;  // C.ADDI, C.LI, etc.
    }
    
    // Quadrant 2
    if (c_op == 2) {
        if (c_funct3 == 2 || c_funct3 == 6) {
            return CLASS_LOAD_STORE;  // C.LWSP, C.SWSP
        }
        return CLASS_DATA_PROC;  // C.MV, C.ADD
    }
    
    return CLASS_OTHER;
}
```

---

## 完整插件实现示例

### 示例 1：简单指令计数器

```c
#include <stdio.h>
#include <stdint.h>
#include <glib.h>
#include <qemu-plugin.h>

QEMU_PLUGIN_EXPORT int qemu_plugin_version = QEMU_PLUGIN_VERSION;

static uint64_t insn_count = 0;
static GMutex lock;

// 指令执行回调
static void vcpu_insn_exec(unsigned int cpu_index, void *udata)
{
    g_mutex_lock(&lock);
    insn_count++;
    g_mutex_unlock(&lock);
}

// TB 翻译回调
static void vcpu_tb_trans(qemu_plugin_id_t id, struct qemu_plugin_tb *tb)
{
    size_t n = qemu_plugin_tb_n_insns(tb);
    
    for (size_t i = 0; i < n; i++) {
        struct qemu_plugin_insn *insn = qemu_plugin_tb_get_insn(tb, i);
        qemu_plugin_register_vcpu_insn_exec_cb(insn, vcpu_insn_exec,
                                               QEMU_PLUGIN_CB_NO_REGS, NULL);
    }
}

// 退出回调
static void plugin_exit(qemu_plugin_id_t id, void *p)
{
    printf("\nTotal instructions: %lu\n", insn_count);
}

// 插件入口
QEMU_PLUGIN_EXPORT int qemu_plugin_install(qemu_plugin_id_t id,
                                          const qemu_info_t *info,
                                          int argc, char **argv)
{
    g_mutex_init(&lock);
    
    qemu_plugin_register_vcpu_tb_trans_cb(id, vcpu_tb_trans);
    qemu_plugin_register_atexit_cb(id, plugin_exit, NULL);
    
    return 0;
}
```

**编译：**

```bash
gcc -shared -fPIC -o insn_counter.so insn_counter.c \
    $(pkg-config --cflags --libs glib-2.0)
```

**运行：**

```bash
qemu-riscv64 -plugin ./insn_counter.so /bin/ls
```

### 示例 2：指令分类统计器

```c
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <glib.h>
#include <qemu-plugin.h>

QEMU_PLUGIN_EXPORT int qemu_plugin_version = QEMU_PLUGIN_VERSION;

enum InsnClass {
    CLASS_LOAD_STORE,
    CLASS_BRANCH,
    CLASS_FP,
    CLASS_VECTOR,
    CLASS_INT,
    CLASS_OTHER,
    NUM_CLASSES
};

static const char *class_names[] = {
    "Load/Store",
    "Branch",
    "Floating-Point",
    "Vector",
    "Integer",
    "Other"
};

typedef struct {
    uint64_t counts[NUM_CLASSES];
    uint64_t total;
} InsnStats;

static InsnStats stats;
static GMutex lock;

// 分类函数
static enum InsnClass classify_insn(const uint8_t *data, size_t len)
{
    if (len == 4) {
        uint32_t insn = data[0] | (data[1] << 8) | 
                       (data[2] << 16) | (data[3] << 24);
        uint32_t opcode = insn & 0x7F;
        
        if (opcode == 0x03 || opcode == 0x23) return CLASS_LOAD_STORE;
        if (opcode == 0x63 || opcode == 0x6F || opcode == 0x67) return CLASS_BRANCH;
        if (opcode == 0x53) return CLASS_FP;
        if (opcode == 0x57) return CLASS_VECTOR;
        if (opcode == 0x13 || opcode == 0x33) return CLASS_INT;
    }
    return CLASS_OTHER;
}

// 执行回调
static void vcpu_insn_exec(unsigned int cpu_index, void *udata)
{
    enum InsnClass cls = (enum InsnClass)(uintptr_t)udata;
    
    g_mutex_lock(&lock);
    stats.counts[cls]++;
    stats.total++;
    g_mutex_unlock(&lock);
}

// 翻译回调
static void vcpu_tb_trans(qemu_plugin_id_t id, struct qemu_plugin_tb *tb)
{
    size_t n = qemu_plugin_tb_n_insns(tb);
    
    for (size_t i = 0; i < n; i++) {
        struct qemu_plugin_insn *insn = qemu_plugin_tb_get_insn(tb, i);
        
        uint8_t data[16];
        size_t len = qemu_plugin_insn_data(insn, data, sizeof(data));
        
        enum InsnClass cls = classify_insn(data, len);
        
        qemu_plugin_register_vcpu_insn_exec_cb(
            insn, vcpu_insn_exec, QEMU_PLUGIN_CB_NO_REGS,
            (void *)(uintptr_t)cls);
    }
}

// 退出回调
static void plugin_exit(qemu_plugin_id_t id, void *p)
{
    printf("\n=== Instruction Statistics ===\n");
    printf("Total: %lu\n\n", stats.total);
    
    for (int i = 0; i < NUM_CLASSES; i++) {
        double pct = 100.0 * stats.counts[i] / stats.total;
        printf("%-20s: %10lu (%5.2f%%)\n", 
               class_names[i], stats.counts[i], pct);
    }
}

// 插件入口
QEMU_PLUGIN_EXPORT int qemu_plugin_install(qemu_plugin_id_t id,
                                          const qemu_info_t *info,
                                          int argc, char **argv)
{
    memset(&stats, 0, sizeof(stats));
    g_mutex_init(&lock);
    
    qemu_plugin_register_vcpu_tb_trans_cb(id, vcpu_tb_trans);
    qemu_plugin_register_atexit_cb(id, plugin_exit, NULL);
    
    return 0;
}
```

### 示例 3：热点分析器

```c
#include <stdio.h>
#include <glib.h>
#include <qemu-plugin.h>

QEMU_PLUGIN_EXPORT int qemu_plugin_version = QEMU_PLUGIN_VERSION;

static GHashTable *hotspots;  // addr -> count
static GMutex lock;
static int top_n = 10;

// 执行回调
static void vcpu_insn_exec(unsigned int cpu_index, void *udata)
{
    uint64_t addr = (uint64_t)udata;
    
    g_mutex_lock(&lock);
    gpointer key = GUINT_TO_POINTER(addr);
    uint64_t count = GPOINTER_TO_UINT(g_hash_table_lookup(hotspots, key));
    g_hash_table_insert(hotspots, key, GUINT_TO_POINTER(count + 1));
    g_mutex_unlock(&lock);
}

// 翻译回调
static void vcpu_tb_trans(qemu_plugin_id_t id, struct qemu_plugin_tb *tb)
{
    size_t n = qemu_plugin_tb_n_insns(tb);
    
    for (size_t i = 0; i < n; i++) {
        struct qemu_plugin_insn *insn = qemu_plugin_tb_get_insn(tb, i);
        uint64_t addr = qemu_plugin_insn_vaddr(insn);
        
        qemu_plugin_register_vcpu_insn_exec_cb(
            insn, vcpu_insn_exec, QEMU_PLUGIN_CB_NO_REGS,
            (void *)addr);
    }
}

// 比较函数（用于排序）
static gint compare_counts(gconstpointer a, gconstpointer b, gpointer user_data)
{
    uint64_t count_a = GPOINTER_TO_UINT(a);
    uint64_t count_b = GPOINTER_TO_UINT(b);
    return count_b - count_a;  // 降序
}

// 退出回调
static void plugin_exit(qemu_plugin_id_t id, void *p)
{
    printf("\n=== Top %d Hotspots ===\n", top_n);
    
    // 转换为列表并排序
    GList *list = NULL;
    GHashTableIter iter;
    gpointer key, value;
    
    g_hash_table_iter_init(&iter, hotspots);
    while (g_hash_table_iter_next(&iter, &key, &value)) {
        list = g_list_insert_sorted_with_data(list, value, compare_counts, NULL);
    }
    
    // 打印 top N
    int rank = 1;
    for (GList *l = list; l != NULL && rank <= top_n; l = l->next, rank++) {
        uint64_t count = GPOINTER_TO_UINT(l->data);
        printf("%2d. Count: %lu\n", rank, count);
    }
    
    g_list_free(list);
}

// 插件入口
QEMU_PLUGIN_EXPORT int qemu_plugin_install(qemu_plugin_id_t id,
                                          const qemu_info_t *info,
                                          int argc, char **argv)
{
    for (int i = 0; i < argc; i++) {
        g_auto(GStrv) tokens = g_strsplit(argv[i], "=", 2);
        if (g_strcmp0(tokens[0], "top") == 0) {
            top_n = g_ascii_strtoull(tokens[1], NULL, 10);
        }
    }
    
    hotspots = g_hash_table_new(g_direct_hash, g_direct_equal);
    g_mutex_init(&lock);
    
    qemu_plugin_register_vcpu_tb_trans_cb(id, vcpu_tb_trans);
    qemu_plugin_register_atexit_cb(id, plugin_exit, NULL);
    
    return 0;
}
```

**使用：**

```bash
qemu-riscv64 -plugin ./hotspot.so,top=20 program
```

---

## 高级技巧

### 1. 性能优化

**问题：** 插件会显著降低执行速度（5-50倍）。

**优化策略：**

#### a) 减少回调频率

```c
// ❌ 坏：每条指令都回调
static void vcpu_tb_trans(qemu_plugin_id_t id, struct qemu_plugin_tb *tb)
{
    size_t n = qemu_plugin_tb_n_insns(tb);
    for (size_t i = 0; i < n; i++) {
        struct qemu_plugin_insn *insn = qemu_plugin_tb_get_insn(tb, i);
        qemu_plugin_register_vcpu_insn_exec_cb(insn, callback, ...);
    }
}

// ✅ 好：只回调 TB（减少 N 倍调用）
static void vcpu_tb_trans(qemu_plugin_id_t id, struct qemu_plugin_tb *tb)
{
    size_t n = qemu_plugin_tb_n_insns(tb);
    qemu_plugin_register_vcpu_tb_exec_cb(tb, callback, 
                                         QEMU_PLUGIN_CB_NO_REGS,
                                         GUINT_TO_POINTER(n));
}

static void callback(unsigned int cpu_index, void *udata)
{
    uint64_t n = GPOINTER_TO_UINT(udata);
    insn_count += n;  // 一次更新
}
```

#### b) 使用内联计数器

QEMU 提供高性能的内联计数功能：

```c
static void vcpu_tb_trans(qemu_plugin_id_t id, struct qemu_plugin_tb *tb)
{
    size_t n = qemu_plugin_tb_n_insns(tb);
    
    // 直接增加计数器（无函数调用开销）
    qemu_plugin_register_vcpu_tb_exec_inline(tb, 
                                             QEMU_PLUGIN_INLINE_ADD_U64,
                                             &total_insns, n);
}
```

#### c) 减少锁竞争

```c
// 使用 TLS（线程局部存储）
__thread uint64_t local_count = 0;

static void callback(unsigned int cpu_index, void *udata)
{
    local_count++;  // 无锁
}

static void plugin_exit(qemu_plugin_id_t id, void *p)
{
    // 收集所有线程的计数
    // （需要额外机制跟踪线程）
}
```

### 2. 条件监控

**场景：** 只在特定条件下收集数据（如特定地址范围）。

```c
static uint64_t start_addr = 0x10000;
static uint64_t end_addr = 0x20000;

static void vcpu_tb_trans(qemu_plugin_id_t id, struct qemu_plugin_tb *tb)
{
    uint64_t addr = qemu_plugin_tb_vaddr(tb);
    
    // 只监控指定范围
    if (addr >= start_addr && addr < end_addr) {
        // ... 注册回调 ...
    }
}
```

### 3. 与外部工具集成

**生成火焰图数据：**

```c
static FILE *flamegraph_file;

static void plugin_exit(qemu_plugin_id_t id, void *p)
{
    // 输出为 flamegraph 格式
    flamegraph_file = fopen("stacks.txt", "w");
    
    GHashTableIter iter;
    gpointer key, value;
    g_hash_table_iter_init(&iter, call_stacks);
    
    while (g_hash_table_iter_next(&iter, &key, &value)) {
        char *stack = (char *)key;
        uint64_t count = GPOINTER_TO_UINT(value);
        fprintf(flamegraph_file, "%s %lu\n", stack, count);
    }
    
    fclose(flamegraph_file);
}
```

然后用 flamegraph.pl 生成可视化：

```bash
flamegraph.pl stacks.txt > profile.svg
```

---

## 常见问题与调试

### Q1: 插件加载失败

**错误：** `Could not load plugin`

**可能原因：**

1. 缺少 `QEMU_PLUGIN_EXPORT` 标记
2. 缺少 `qemu_plugin_version` 变量
3. 符号未导出

**解决：**

```c
// 必需的导出
QEMU_PLUGIN_EXPORT int qemu_plugin_version = QEMU_PLUGIN_VERSION;
QEMU_PLUGIN_EXPORT int qemu_plugin_install(...) { ... }
```

编译时检查符号：

```bash
nm -D plugin.so | grep qemu_plugin
# 应该看到 T qemu_plugin_install
```

### Q2: 程序崩溃或死锁

**症状：** QEMU 无响应或 Segmentation Fault

**可能原因：**

1. 回调函数中访问了无效内存
2. 锁死锁（忘记 unlock）
3. 多线程竞态条件

**调试方法：**

```bash
# 使用 GDB 调试
gdb --args qemu-riscv64 -plugin ./plugin.so program

# 在 QEMU 中启用日志
qemu-riscv64 -d plugin,cpu -D qemu.log -plugin ./plugin.so program
```

### Q3: 统计数据不准确

**症状：** 指令计数偏差、内存访问遗漏

**可能原因：**

1. 没有处理压缩指令
2. 多线程计数未加锁
3. 只统计了部分指令类型

**检查清单：**

- ✅ 处理 16-bit RVC 指令
- ✅ 所有共享变量都加锁
- ✅ 分类逻辑覆盖所有 opcode

### Q4: 性能太慢

**症状：** 程序执行时间增加 100 倍以上

**优化检查：**

- ✅ 使用 `QEMU_PLUGIN_CB_NO_REGS`（如果不需要寄存器）
- ✅ 用 TB 级回调代替指令级
- ✅ 使用 inline 计数器
- ✅ 减少锁竞争（使用 TLS）
- ✅ 避免在热路径中分配内存

### Q5: 内存泄漏

**症状：** 长时间运行后内存占用不断增长

**检查：**

- ✅ `qemu_plugin_insn_disas()` 返回的字符串需要 `g_free()`
- ✅ `g_strdup()` 的字符串需要释放
- ✅ 哈希表使用 `g_hash_table_new_full()` 指定析构函数

**示例：**

```c
// 创建带析构函数的哈希表
hotspots = g_hash_table_new_full(
    g_direct_hash, g_direct_equal,
    NULL,           // key 析构
    g_free          // value 析构（如果是 g_strdup 的字符串）
);
```

---

## 总结

### 核心要点

1. **QEMU 插件 = 动态插桩工具**
   - 不修改目标程序
   - 在翻译时插入钩子
   - 在执行时收集数据

2. **两级回调机制**
   - **翻译时**：分析指令、注册回调
   - **执行时**：统计、追踪、记录

3. **性能权衡**
   - 回调越少越快（用 TB 代替 insn）
   - 使用 inline 计数器
   - 避免锁竞争

4. **应用场景广泛**
   - 性能分析：指令统计、热点识别
   - 内存研究：访问模式、缓存模拟
   - 安全分析：行为监控、漏洞检测
   - 架构研究：指令分布、向量化评估

### 开发流程总结

```
1. 定义需求
   └→ 想要收集什么数据？

2. 设计数据结构
   └→ 如何存储统计信息？

3. 实现分类/检测逻辑
   └→ vcpu_tb_trans() 中分析指令

4. 注册执行回调
   └→ 选择合适的回调类型和频率

5. 收集数据
   └→ 执行回调中更新统计

6. 生成报告
   └→ plugin_exit() 中输出结果

7. 优化性能
   └→ 减少回调、使用 inline、减少锁
```

---

## 参考资源

### 官方文档

- [QEMU Plugin API](https://qemu.readthedocs.io/en/latest/devel/tcg-plugins.html)
- [QEMU TCG Documentation](https://qemu.readthedocs.io/en/latest/devel/tcg.html)

### 示例插件

QEMU 源码包含多个示例插件：

```
qemu/contrib/plugins/
├── execlog.c       # 记录执行轨迹
├── hotblocks.c     # 热点分析
├── hotpages.c      # 页面访问热度
├── howvec.c        # 向量化分析
└── lockstep.c      # 多核同步检查
```

### 相关工具

- **Pin**：Intel 的动态插桩框架
- **DynamoRIO**：Google 的 DBT 框架
- **Valgrind**：内存调试和性能分析工具

### RISC-V 资源

- [RISC-V 指令集手册](https://riscv.org/technical/specifications/)
- [RISC-V 汇编参考](https://github.com/riscv-non-isa/riscv-asm-manual)

