# 硬件性能建模完整指南

## 第2部分 C：依赖与Notify机制

>  **本文是第2部分的第3个子文档，聚焦于依赖管理和Notify机制**   
> 其他子文档：[Event生命周期](./第2部分A_Event生命周期.md) | [资源竞争](./第2部分B_资源竞争建模.md) | [Event创建时机](./第2部分D_Event创建与时间推进.md) | [Event与资源关系](./第2部分E_Event与资源关系.md)

---

## 导航

- [9.1 依赖的类型](#dependency-types)
- [9.2 依赖图表示](#dependency-graph)
- [9.3 依赖检查](#dependency-check)
- [9.4 Notify机制（核心）](#notify-mechanism)
- [9.5 完整的依赖管理器](#dependency-manager)
- [9.6 Fork-Join示例](#fork-join-example)

---

### 9. 依赖与Notify机制 {#dependency-notify}

**这是最重要的机制之一！**

#### 9.1 依赖的类型 {#dependency-types}

**类型1: 数据依赖 (Read-After-Write)**

```python
操作A: 写入缓冲区X
操作B: 读取缓冲区X

依赖: B必须等A完成
原因: 确保数据正确性
```

**类型2: 控制依赖**

```python
操作A: 计算循环次数N
操作B: 执行N次迭代

依赖: B必须等A完成
原因: 需要A的结果才能执行B
```

**类型3: 资源依赖**

```python
操作A: 使用处理器P0
操作B: 使用处理器P0

依赖: 隐式(通过资源管理器)
原因: 资源互斥
```

**类型4: 顺序依赖**

```python
操作A: 传输1
操作B: 传输2
操作C: 传输3

依赖: A→B→C (强制顺序)
原因: 业务逻辑要求
```

---

#### 9.2 依赖图表示 {#dependency-graph}

**数据结构：**

```python
class DependencyGraph:
    """依赖图"""
    
    def __init__(self):
        # 前向依赖: op_id → 它依赖的ops
        self.dependencies = defaultdict(set)
        # 例: dependencies[5] = {1, 2, 3}
        #     意思: 操作5依赖操作1,2,3
        
        # 反向依赖: op_id → 依赖它的ops (用于notify!)
        self.dependents = defaultdict(set)
        # 例: dependents[1] = {5, 6}
        #     意思: 操作5,6依赖操作1
    
    def add_dependency(self, from_op, to_op):
        """
        添加依赖: to_op 依赖 from_op
        即: from_op必须先完成，to_op才能执行
        """
        # 前向: to_op依赖from_op
        self.dependencies[to_op].add(from_op)
        
        # 反向: from_op有dependent是to_op
        self.dependents[from_op].add(to_op)
        
        print(f"[依赖] 操作{to_op}依赖操作{from_op}")
    
    def get_dependencies(self, op_id):
        """获取op_id依赖的所有操作"""
        return self.dependencies[op_id]
    
    def get_dependents(self, op_id):
        """
        获取依赖op_id的所有操作
        (用于notify机制!)
        """
        return self.dependents[op_id]

# 示例: 构建依赖图
#     A
#    / \
#   B   C
#    \ /
#     D

graph = DependencyGraph()
graph.add_dependency(from_op='A', to_op='B')  # B依赖A
graph.add_dependency(from_op='A', to_op='C')  # C依赖A
graph.add_dependency(from_op='B', to_op='D')  # D依赖B
graph.add_dependency(from_op='C', to_op='D')  # D依赖C

# 查询
graph.get_dependencies('D')  # 返回: {'B', 'C'}
graph.get_dependents('A')    # 返回: {'B', 'C'}
```

**关键设计：双向依赖图**

| 字段 | 用途 | 查询 |
|------|------|------|
| `dependencies` | 前向依赖 | "我依赖谁？" |
| `dependents` | 反向依赖 | "谁依赖我？" ⭐ Notify用 |

---

#### 9.3 依赖检查 {#dependency-check}

```python
def are_dependencies_satisfied(op_id):
    """
    检查操作的所有依赖是否都已满足
    
    返回: True 如果所有依赖都完成，否则False
    """
    # 获取这个操作依赖的所有前驱操作
    deps = dependency_graph.get_dependencies(op_id)
    
    # 检查每个依赖是否都完成了
    for dep_id in deps:
        if dep_id not in completed_operations:
            # 至少有一个依赖未完成
            print(f"[依赖检查] 操作{op_id}的依赖{dep_id}未完成")
            return False
    
    # 所有依赖都完成了
    print(f"[依赖检查] 操作{op_id}的所有依赖已满足")
    return True
```

---

#### 9.4 Notify机制（核心！）{#notify-mechanism}

**问题：** 依赖满足后如何通知等待的操作？

**方案1: 轮询 (低效) ❌**

```python
def try_schedule_all_operations():
    """
    轮询方式: 每次都检查所有操作
    """
    for op in all_operations:
        if op.state == OperationState.PENDING:
            # 每个操作都检查依赖
            if are_dependencies_satisfied(op.id):
                try_schedule(op)

# 问题:
# 1. 效率低: 即使依赖未变化，也反复检查
# 2. 复杂度高: O(n*m), n=操作数, m=依赖数
# 3. 浪费: 大部分检查都是无用功
```

**方案2: Notify (高效) ✓**

```python
def notify_mechanism_handle_complete(completed_op_id):
    """
    Notify方式: 主动通知依赖这个操作的后继
    
    这是推荐的方式！
    """
    print(f"\n[Notify] 操作{completed_op_id}完成，检查依赖它的操作")
    
    # 1. 标记操作完成
    completed_operations.add(completed_op_id)
    
    # 2. 获取所有依赖这个操作的后继操作 (使用反向依赖图!)
    dependents = dependency_graph.get_dependents(completed_op_id)
    print(f"[Notify] 找到{len(dependents)}个依赖操作: {dependents}")
    
    # 3. 检查每个后继操作
    for dep_op_id in dependents:
        # 检查这个后继的所有依赖是否都满足了
        if are_dependencies_satisfied(dep_op_id):
            # 所有依赖都满足了!
            print(f"[Notify] 操作{dep_op_id}就绪!")
            
            # 移到就绪队列
            pending_operations.discard(dep_op_id)
            ready_operations.add(dep_op_id)
            
            # 立即尝试调度
            try_schedule(dep_op_id)
        else:
            # 还有其他依赖未满足
            remaining = (dependency_graph.get_dependencies(dep_op_id) - 
                        completed_operations)
            print(f"[Notify] 操作{dep_op_id}还需等待: {remaining}")

# 优势:
# 1. 高效: 只检查可能受影响的操作
# 2. 复杂度低: O(dependents * dependencies)，通常很小
# 3. 精确: 依赖满足时立即响应
```

**两种方案对比：**

| 特性 | 轮询 | Notify |
|------|------|--------|
| 效率 | 低（重复检查） | 高（按需检查） |
| 复杂度 | O(n×m) | O(dependents) |
| 响应时间 | 延迟（下次轮询） | 立即 |
| 推荐 | ❌ | ✓ |

**Notify机制的完整流程：**

```
时间轴示例:

时间0:
  操作A开始执行
  
时间50:
  [Event] 操作A完成
    ↓
  [Notify] 查找依赖A的操作
    ↓ 找到: B, C
    ↓
  [Notify] 检查B的依赖
    ↓ B只依赖A → 满足!
    ↓
  [Notify] B进入就绪队列
    ↓
  [调度] 立即调度B (如果资源可用)
    ↓
  [Event] 创建B的START event
    ↓
  [Notify] 检查C的依赖
    ↓ C只依赖A → 满足!
    ↓
  [Notify] C进入就绪队列
    ↓
  [调度] 立即调度C (如果资源可用)
    ↓
  [Event] 创建C的START event

结果: B和C都在时间50被notify并调度，无需轮询!
```

---

#### 9.5 完整的依赖管理器 {#dependency-manager}

```python
class DependencyManager:
    """完整的依赖管理器，集成notify机制"""
    
    def __init__(self):
        self.graph = DependencyGraph()
        self.completed = set()
        self.pending = set()
        self.ready = set()
    
    def add_operation(self, op):
        """添加操作"""
        if len(op.dependencies) == 0:
            # 无依赖，立即就绪
            self.ready.add(op.id)
            print(f"[依赖] 操作{op.id}无依赖，立即就绪")
        else:
            # 有依赖，进入pending
            self.pending.add(op.id)
            print(f"[依赖] 操作{op.id}有{len(op.dependencies)}个依赖，进入pending")
            
            # 建立依赖关系
            for dep_id in op.dependencies:
                self.graph.add_dependency(dep_id, op.id)
    
    def mark_complete(self, op_id):
        """
        标记操作完成，触发notify
        
        这是notify机制的入口!
        """
        print(f"\n{'='*60}")
        print(f"[依赖] 操作{op_id}完成")
        print(f"{'='*60}")
        
        # 标记完成
        self.completed.add(op_id)
        
        # Notify: 检查所有依赖这个操作的后继
        self.notify_dependents(op_id)
    
    def notify_dependents(self, completed_op_id):
        """
        核心: notify所有依赖completed_op_id的操作
        """
        # 获取依赖这个操作的所有后继
        dependents = self.graph.get_dependents(completed_op_id)
        
        if not dependents:
            print(f"[Notify] 操作{completed_op_id}没有依赖者")
            return
        
        print(f"[Notify] 检查{len(dependents)}个依赖者: {dependents}")
        
        for dep_op_id in dependents:
            # 检查这个后继的所有依赖
            all_deps = self.graph.get_dependencies(dep_op_id)
            unsatisfied = all_deps - self.completed
            
            if len(unsatisfied) == 0:
                # 所有依赖都满足了!
                print(f"[Notify] ✓ 操作{dep_op_id}所有依赖已满足")
                
                # 从pending移到ready
                if dep_op_id in self.pending:
                    self.pending.remove(dep_op_id)
                    self.ready.add(dep_op_id)
                    print(f"[Notify]   操作{dep_op_id}: PENDING → READY")
            else:
                # 还有依赖未满足
                print(f"[Notify] ✗ 操作{dep_op_id}还需等待: {unsatisfied}")
    
    def get_ready_operations(self):
        """获取所有就绪的操作"""
        return self.ready
    
    def are_all_dependencies_satisfied(self, op_id):
        """检查操作的依赖是否全部满足"""
        deps = self.graph.get_dependencies(op_id)
        return deps.issubset(self.completed)
```

**DependencyManager的状态转换：**

```
操作状态流转:

PENDING → READY → RUNNING → COMPLETED
   ↑         ↑
   |         |
   └─ 有依赖  └─ Notify触发
```

---

#### 9.6 Notify机制示例 {#fork-join-example}

**场景：Fork-Join模式**

```python
# 依赖图:
#     A
#    / \
#   B   C
#    \ /
#     D

# 初始化
dep_mgr = DependencyManager()

op_a = Operation(id='A', dependencies=[])
op_b = Operation(id='B', dependencies=['A'])
op_c = Operation(id='C', dependencies=['A'])
op_d = Operation(id='D', dependencies=['B', 'C'])

dep_mgr.add_operation(op_a)
dep_mgr.add_operation(op_b)
dep_mgr.add_operation(op_c)
dep_mgr.add_operation(op_d)

# 输出:
# [依赖] 操作A无依赖，立即就绪
# [依赖] 操作B有1个依赖，进入pending
# [依赖] 操作C有1个依赖，进入pending
# [依赖] 操作D有2个依赖，进入pending

# 状态:
# ready: {A}
# pending: {B, C, D}

# --- 时间50: A完成 ---
dep_mgr.mark_complete('A')

# 输出:
# ============================================================
# [依赖] 操作A完成
# ============================================================
# [Notify] 检查2个依赖者: {B, C}
# [Notify] ✓ 操作B所有依赖已满足
# [Notify]   操作B: PENDING → READY
# [Notify] ✓ 操作C所有依赖已满足
# [Notify]   操作C: PENDING → READY

# 状态:
# ready: {B, C}
# pending: {D}
# completed: {A}

# --- 时间80: B完成 ---
dep_mgr.mark_complete('B')

# 输出:
# ============================================================
# [依赖] 操作B完成
# ============================================================
# [Notify] 检查1个依赖者: {D}
# [Notify] ✗ 操作D还需等待: {C}

# 状态:
# ready: {C}
# pending: {D}
# completed: {A, B}

# --- 时间85: C完成 ---
dep_mgr.mark_complete('C')

# 输出:
# ============================================================
# [依赖] 操作C完成
# ============================================================
# [Notify] 检查1个依赖者: {D}
# [Notify] ✓ 操作D所有依赖已满足
# [Notify]   操作D: PENDING → READY

# 状态:
# ready: {D}
# pending: {}
# completed: {A, B, C}
```

**关键观察：**

1.  **A完成后**  ，立即notify B和C → 都变为READY
2.  **B完成后**  ，notify D，但D还需等C → D保持PENDING
3.  **C完成后**  ，notify D，D的所有依赖满足 → D变为READY
4.  **整个过程无需轮询**  ，高效精确

**时间线可视化：**

```
时间    0         50        80  85
        |         |         |   |
A:      |===A====>|
                  ↓ Notify
B:                |===B====>|
                            ↓ Notify (D还需等C)
C:                |=====C====>|
                              ↓ Notify (D就绪!)
D:                            |===D===>

关键点:
- t=50: A完成，B和C被notify并立即开始（并行）
- t=80: B完成，D被notify但还需等C
- t=85: C完成，D被notify并就绪
```

---

## 关键要点总结

### Notify机制的核心

**3个关键步骤：**

```python
1. 操作完成时：
   completed_operations.add(op_id)

2. 查找依赖者：
   dependents = graph.get_dependents(op_id)  # ← 反向依赖！

3. 逐一检查：
   for dep in dependents:
       if all_dependencies_satisfied(dep):
           move_to_ready(dep)
```

### 为什么Notify高效？

```
轮询方式（每次event）:
  检查所有操作 → 大量无用检查
  复杂度: O(所有操作数)

Notify方式（操作完成时）:
  只检查直接依赖者 → 精确高效
  复杂度: O(依赖者数量)
  
典型场景:
  - 100个操作
  - 每个操作平均2个依赖者
  
  轮询: 每次检查100个
  Notify: 每次检查2个 → 50倍提升！
```

### 双向依赖图的作用

| 依赖方向 | 数据结构 | 用途 |
|---------|---------|------|
| 前向 | `dependencies[op]` | 检查依赖是否满足 |
| 反向 | `dependents[op]` |  **Notify机制**  ⭐ |

### 常见错误

❌  **错误1**  ： 只维护前向依赖

```python
# 错误：没有反向依赖
self.dependencies = {}  # 只有这个

# 问题：无法高效找到dependents，只能轮询
```

✓  **正确做法**  ：

```python
# 同时维护双向
self.dependencies = {}   # 前向
self.dependents = {}     # 反向（Notify用）
```

❌  **错误2**  ： 忘记检查所有依赖

```python
# 错误：只检查一个依赖
if dep_id in completed:
    move_to_ready(op)

# 问题：可能还有其他依赖未满足
```

✓  **正确做法**  ：

```python
# 检查所有依赖
all_deps = graph.get_dependencies(op_id)
if all_deps.issubset(completed):
    move_to_ready(op)
```

❌  **错误3**  ： 轮询所有操作

```python
# 错误：低效轮询
for op in all_operations:
    if dependencies_satisfied(op):
        schedule(op)
```

✓  **正确做法**  ：

```python
# 使用Notify
def on_operation_complete(op_id):
    # 只检查依赖这个操作的后继
    for dep in graph.get_dependents(op_id):
        if dependencies_satisfied(dep):
            schedule(dep)
```

### 实现checklist

✓ 数据结构:

- [ ] 前向依赖图 (`dependencies`)
- [ ] 反向依赖图 (`dependents`)
- [ ] 完成集合 (`completed`)
- [ ] 就绪队列 (`ready`)

✓ 核心方法:

- [ ] `add_dependency()` - 同时更新双向图
- [ ] `notify_dependents()` - Notify机制
- [ ] `are_dependencies_satisfied()` - 依赖检查
- [ ] `mark_complete()` - 触发Notify

✓ 测试要点:

- [ ] Fork模式（一个操作→多个后继）
- [ ] Join模式（多个操作→一个后继）
- [ ] Fork-Join组合
- [ ] 链式依赖（A→B→C→D）

---

**下一篇** ： [第2部分D：Event创建与时间推进](./第2部分D_Event创建与时间推进.md)

*本文档行数: ~590行 (原2部分第9节)*
