# 硬件性能建模完整指南

## 第2部分 B：资源竞争建模

>  **本文是第2部分的第2个子文档，聚焦于资源竞争的建模方法**   
> 其他子文档：[Event生命周期](./第2部分A_Event生命周期.md) | [依赖与Notify](./第2部分C_依赖与Notify机制.md) | [Event创建时机](./第2部分D_Event创建与时间推进.md) | [Event与资源关系](./第2部分E_Event与资源关系.md)

---

## 导航

- [8.1 资源竞争的本质](#resource-contention-essence)
- [8.2 资源状态模型](#resource-state-model)
- [8.3 竞争解决策略](#contention-resolution)
- [8.4 多资源协调](#multi-resource-coordination)
- [8.5 实战示例](#practical-example)

---

### 8. 资源竞争建模 {#resource-contention}

#### 8.1 资源竞争的本质 {#resource-contention-essence}

**问题：** 多个操作同时需要同一个资源

```
时间轴:
      0         50        100       150
      |         |         |         |
操作1: 想用处理器P0 (0-100周期)
操作2: 也想用P0 (0-80周期)  ← 冲突！

如果不处理竞争:
P0:   |===操作1===||===操作2===|  (重叠使用，错误!)

正确处理竞争:
P0:   |===操作1===|             (0-100)
                  |===操作2===| (100-180) ← 串行化
```

**竞争的3个关键要素：**

1.  **时间重叠**  ： 多个操作在时间上重叠
2.  **资源独占**  ： 资源不能同时被多个操作使用
3.  **冲突解决**  ： 必须有机制决定谁先使用

---

#### 8.2 资源状态模型 {#resource-state-model}

**基本资源状态：**

```python
class Resource:
    """资源状态的基本模型"""
    
    def __init__(self, name):
        self.name = name
        self.busy_until = 0       # 资源忙到什么时候
        self.current_user = None  # 谁在使用
        
        # 统计
        self.total_busy_time = 0
        self.acquisition_count = 0
    
    def is_available(self, time):
        """
        查询资源在某时刻是否可用
        """
        return time >= self.busy_until
    
    def get_available_time(self):
        """
        获取资源何时变为可用
        """
        return self.busy_until
    
    def acquire(self, user_id, start_time, duration):
        """
        获取资源
        
        参数:
            user_id: 使用者ID
            start_time: 开始使用的时间
            duration: 使用时长
        """
        self.busy_until = start_time + duration
        self.current_user = user_id
        
        # 更新统计
        self.total_busy_time += duration
        self.acquisition_count += 1
        
        print(f"    [{self.name}] 被操作{user_id}获取"
              f" ({start_time} - {self.busy_until})")
    
    def release(self):
        """
        释放资源
        """
        print(f"    [{self.name}] 被操作{self.current_user}释放"
              f" @ 时间{self.busy_until}")
        self.current_user = None
    
    def get_utilization(self, total_time):
        """
        计算利用率
        """
        if total_time == 0:
            return 0.0
        return self.total_busy_time / total_time
```

**关键字段说明：**

| 字段 | 含义 | 何时更新 |
|------|------|---------|
| `busy_until` | 资源忙到何时 | acquire()时设置 |
| `current_user` | 当前使用者 | acquire()设置, release()清除 |
| `total_busy_time` | 总忙碌时间 | acquire()累加 |
| `acquisition_count` | 获取次数 | acquire()递增 |

---

#### 8.3 竞争解决策略 {#contention-resolution}

**策略1: 串行化 (互斥资源)**

```python
def calculate_start_time_serialized(op, resource):
    """
    串行化策略：必须等资源完全空闲
    
    适用: 不能共享的资源(处理器、端口等)
    """
    # 约束1: 当前时间
    constraint1 = current_time
    
    # 约束2: 资源可用时间
    constraint2 = resource.get_available_time()
    
    # 必须满足所有约束
    start_time = max(constraint1, constraint2)
    
    return start_time

# 示例
current_time = 0
processor = Resource("P0")

# 操作1
start1 = calculate_start_time_serialized(op1, processor)
# start1 = max(0, 0) = 0
processor.acquire(op1.id, start=0, duration=100)
# processor.busy_until = 100

# 操作2
start2 = calculate_start_time_serialized(op2, processor)
# start2 = max(0, 100) = 100  ← 必须等待！
processor.acquire(op2.id, start=100, duration=80)
# processor.busy_until = 180

结果: 操作2被推迟到100开始，避免了冲突
```

**策略2: 带宽共享 (可共享资源)**

```python
def calculate_effective_bandwidth(resource, num_concurrent_users):
    """
    带宽共享策略：多用户分享带宽
    
    适用: 内存总线、网络链路等
    """
    base_bandwidth = resource.bandwidth
    
    if num_concurrent_users == 1:
        # 独占
        return base_bandwidth
    else:
        # 共享，考虑开销
        overhead = 0.9  # 10%开销
        return (base_bandwidth / num_concurrent_users) * overhead

# 示例
memory_bus = Resource("Memory")
memory_bus.bandwidth = 32  # GB/s

# 1个用户
bw1 = calculate_effective_bandwidth(memory_bus, 1)
# bw1 = 32 GB/s

# 2个用户并发
bw2 = calculate_effective_bandwidth(memory_bus, 2)
# bw2 = (32 / 2) * 0.9 = 14.4 GB/s per user

# 4个用户并发
bw4 = calculate_effective_bandwidth(memory_bus, 4)
# bw4 = (32 / 4) * 0.9 = 7.2 GB/s per user
```

**策略3: 容量限制 (有限并发)**

```python
class CapacityLimitedResource:
    """
    容量受限的资源
    
    适用: Outstanding Buffer, 连接数等
    """
    
    def __init__(self, name, capacity):
        self.name = name
        self.capacity = capacity          # 最大容量
        self.current_usage = 0            # 当前使用量
        self.allocations = {}             # 记录分配
    
    def can_allocate(self, amount):
        """检查是否能分配"""
        return (self.current_usage + amount) <= self.capacity
    
    def allocate(self, user_id, amount, release_time):
        """分配容量"""
        if not self.can_allocate(amount):
            raise ValueError(f"容量不足: 需要{amount}, "
                           f"剩余{self.capacity - self.current_usage}")
        
        self.current_usage += amount
        self.allocations[user_id] = {
            'amount': amount,
            'release_time': release_time
        }
        
        print(f"    [{self.name}] 分配{amount}给操作{user_id}, "
              f"使用量: {self.current_usage}/{self.capacity}")
    
    def release(self, user_id):
        """释放容量"""
        if user_id in self.allocations:
            amount = self.allocations[user_id]['amount']
            self.current_usage -= amount
            del self.allocations[user_id]
            
            print(f"    [{self.name}] 操作{user_id}释放{amount}, "
                  f"使用量: {self.current_usage}/{self.capacity}")

# 示例: Outstanding Buffer
ob = CapacityLimitedResource("OB", capacity=128)

# 操作1申请64 entries
if ob.can_allocate(64):
    ob.allocate(op1.id, 64, release_time=100)
    # 使用量: 64/128

# 操作2申请64 entries  
if ob.can_allocate(64):
    ob.allocate(op2.id, 64, release_time=120)
    # 使用量: 128/128 (满了!)

# 操作3申请32 entries
if ob.can_allocate(32):
    ob.allocate(op3.id, 32, release_time=140)
else:
    print("OB容量不足，操作3必须等待")
    # 必须等待操作1或操作2释放
```

**三种策略对比：**

| 策略 | 并发性 | 适用资源 | 复杂度 |
|------|--------|---------|--------|
| 串行化 | 无并发 | 处理器、通道 | 简单 |
| 带宽共享 | 完全并发 | 内存总线、网络 | 中等 |
| 容量限制 | 有限并发 | Buffer、连接池 | 复杂 |

---

#### 8.4 多资源协调 {#multi-resource-coordination}

**问题：** 操作通常需要多个资源

```python
def calculate_start_time_multi_resource(op):
    """
    计算需要多个资源的操作的开始时间
    
    原则: 必须所有资源都可用才能开始
    """
    # 约束列表
    constraints = []
    
    # 约束1: 当前时间
    constraints.append(current_time)
    
    # 约束2: 所有需要的资源
    for resource in op.required_resources:
        resource_avail = resource.get_available_time()
        constraints.append(resource_avail)
    
    # 约束3: 依赖操作的完成时间
    for dep_id in op.dependencies:
        dep_complete = get_operation_complete_time(dep_id)
        constraints.append(dep_complete)
    
    # 约束4: 用户指定的最早开始时间
    if op.earliest_start is not None:
        constraints.append(op.earliest_start)
    
    # 必须满足所有约束
    start_time = max(constraints)
    
    return start_time

# 示例
op = Operation(id=5)
op.required_resources = [processor, memory, dma_channel]
op.dependencies = [1, 2]
op.earliest_start = 50

start = calculate_start_time_multi_resource(op)
# start = max(
#     current_time=0,
#     processor.busy_until=30,
#     memory.busy_until=40,
#     dma_channel.busy_until=20,
#     op1.end_time=35,
#     op2.end_time=45,
#     op.earliest_start=50
# ) = 50

# 操作5必须等到时间50才能开始
```

**多资源协调的关键：**

1.  **收集所有约束**  ： 资源、依赖、时间等
2.  **取最严格约束**  ： max(所有约束)
3.  **原子性获取**  ： 要么全部获取，要么都不获取
4.  **顺序释放**  ： 避免死锁

---

#### 8.5 实战示例 {#practical-example}

**完整示例：3个操作竞争2个资源**

```python
"""
场景:
  - 资源: Processor P0, Memory M0
  - 操作1: 需要P0 (50周期)
  - 操作2: 需要M0 (30周期)
  - 操作3: 需要P0和M0 (40周期)
"""

# 初始化
processor = Resource("P0")
memory = Resource("M0")
current_time = 0

print("=== 资源竞争示例 ===\n")

# 操作1: 需要P0
print("--- 操作1 ---")
op1_start = calculate_start_time_multi_resource(
    op1, [processor], current_time
)
print(f"操作1开始时间: {op1_start}")
# op1_start = max(0, 0) = 0

processor.acquire(op1.id, start=op1_start, duration=50)
print(f"P0状态: busy_until={processor.busy_until}")
# P0: busy_until=50

# 操作2: 需要M0
print("\n--- 操作2 ---")
op2_start = calculate_start_time_multi_resource(
    op2, [memory], current_time
)
print(f"操作2开始时间: {op2_start}")
# op2_start = max(0, 0) = 0

memory.acquire(op2.id, start=op2_start, duration=30)
print(f"M0状态: busy_until={memory.busy_until}")
# M0: busy_until=30

# 操作3: 需要P0和M0 (两个都需要!)
print("\n--- 操作3 ---")
print("操作3需要: P0和M0")
print(f"  P0可用时间: {processor.get_available_time()}")  # 50
print(f"  M0可用时间: {memory.get_available_time()}")     # 30

op3_start = calculate_start_time_multi_resource(
    op3, [processor, memory], current_time
)
print(f"操作3开始时间: {op3_start}")
# op3_start = max(0, 50, 30) = 50
# 必须等P0和M0都可用!

processor.acquire(op3.id, start=op3_start, duration=40)
memory.acquire(op3.id, start=op3_start, duration=40)

print(f"\n最终状态:")
print(f"  P0: busy_until={processor.busy_until}")  # 90
print(f"  M0: busy_until={memory.busy_until}")     # 90

print("\n时间线:")
print("P0: |===Op1===|             |===Op3===|")
print("    0        50            90")
print("\nM0: |==Op2==|             |===Op3===|")
print("    0       30            90")

print("\n关键观察:")
print("  - 操作1和操作2并行执行 (使用不同资源)")
print("  - 操作3必须等待两个资源都可用 (时间50)")
print("  - 操作3在50-90执行，独占两个资源")
```

**输出：**

```
=== 资源竞争示例 ===

--- 操作1 ---
操作1开始时间: 0
    [P0] 被操作1获取 (0 - 50)
P0状态: busy_until=50

--- 操作2 ---
操作2开始时间: 0
    [M0] 被操作2获取 (0 - 30)
M0状态: busy_until=30

--- 操作3 ---
操作3需要: P0和M0
  P0可用时间: 50
  M0可用时间: 30
操作3开始时间: 50
    [P0] 被操作3获取 (50 - 90)
    [M0] 被操作3获取 (50 - 90)

最终状态:
  P0: busy_until=90
  M0: busy_until=90

时间线:
P0: |===Op1===|             |===Op3===|
    0        50            90

M0: |==Op2==|             |===Op3===|
    0       30            90

关键观察:
  - 操作1和操作2并行执行 (使用不同资源)
  - 操作3必须等待两个资源都可用 (时间50)
  - 操作3在50-90执行，独占两个资源
```

---

## 关键要点总结

### 资源竞争的本质

```
多个操作 + 有限资源 → 竞争
竞争 + 无协调 → 冲突
冲突 + 串行化 → 延迟
```

### 三种解决策略

1.  **串行化**  ： 互斥，无并发
2.  **带宽共享**  ： 完全并发，性能降低
3.  **容量限制**  ： 有限并发，精细控制

### 多资源协调原则

```python
start_time = max(
    current_time,
    resource1.busy_until,
    resource2.busy_until,
    ...
    dependency_complete_time,
    earliest_start_time
)

关键: 必须满足所有约束
```

### 资源状态追踪

```python
class Resource:
    busy_until: int       # 何时可用（最重要）
    current_user: int     # 谁在用（调试）
    total_busy_time: int  # 利用率统计
```

### 常见错误

❌  **错误1**  ： 忘记检查资源可用性

```python
# 错误
processor.acquire(op.id, current_time, duration)
# 没有检查 is_available()
```

❌  **错误2**  ： 部分获取资源

```python
# 错误
processor.acquire(...)  # 成功
memory.acquire(...)     # 失败！但processor已获取
```

❌  **错误3**  ： 忽略多资源约束

```python
# 错误
start = max(current_time, processor.busy_until)
# 忘记检查 memory.busy_until
```

### 正确做法

✓  **检查再获取** 

```python
if all_resources_available(op, resources):
    for resource in resources:
        resource.acquire(...)
```

✓  **原子性操作** 

```python
acquired = []
try:
    for resource in resources:
        if not resource.is_available():
            # 回滚
            for r in acquired:
                r.release()
            return False
        resource.acquire(...)
        acquired.append(resource)
except:
    # 回滚
    for r in acquired:
        r.release()
```

✓  **考虑所有约束** 

```python
constraints = [
    current_time,
    *[r.busy_until for r in resources],
    *[dep.end_time for dep in dependencies]
]
start_time = max(constraints)
```

---

**下一篇** ： [第2部分C：依赖与Notify机制](./第2部分C_依赖与Notify机制.md)

*本文档行数: ~570行 (原2部分的约13%)*
