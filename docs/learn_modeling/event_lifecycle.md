# 硬件性能建模完整指南

## 第2部分 A：Event生命周期

> **本文是第2部分的第1个子文档，聚焦于Event的生命周期**  
> 其他子文档：[资源竞争](./第2部分B_资源竞争建模.md) | [依赖与Notify](./第2部分C_依赖与Notify机制.md) | [Event创建时机](./第2部分D_Event创建与时间推进.md) | [Event与资源关系](./第2部分E_Event与资源关系.md)

---

## 导航

- [7.1 Event的6个阶段](#event-6-stages)
- [7.2 阶段1: Event创建](#stage-1-creation)
- [7.3 阶段2: Event入队](#stage-2-enqueue)
- [7.4 阶段3: Event出队](#stage-3-dequeue)
- [7.5 阶段4: Event分发](#stage-4-dispatch)
- [7.6 阶段5: 处理与更新](#stage-5-process)
- [7.7 阶段6: 创建新Event](#stage-6-create-new)
- [7.8 完整示例追踪](#complete-example)

---

### 7. Event生命周期 {#event-lifecycle}

#### 7.1 Event的6个阶段 {#event-6-stages}

```
┌──────────────────────────────────────────┐
│         Event完整生命周期                 │
└──────────────────────────────────────────┘

阶段1: 创建 (Creation)
  ↓ 何时: 初始化、或处理其他event时
  ↓ 谁创建: Scheduler, Event Handler
  ↓
阶段2: 入队 (Enqueue)
  ↓ 如何: event_queue.put(event)
  ↓ 排序: 自动按时间排序 (优先队列)
  ↓
阶段3: 出队 (Dequeue)
  ↓ 如何: event = event_queue.get()
  ↓ 关键: current_time = event.time (时间跳跃!)
  ↓
阶段4: 分发 (Dispatch)
  ↓ 根据event类型调用对应handler
  ↓ 例: START → handle_start()
  ↓
阶段5: 处理与更新 (Process & Update)
  ↓ 更新资源状态
  ↓ 更新操作状态
  ↓ 更新依赖状态
  ↓ 更新统计信息
  ↓
阶段6: 创建新Event (Create Consequences)
  ↓ 完成event → 创建释放event
  ↓ 依赖满足 → 创建就绪event
  └─ 回到阶段1 (循环)
```

---

#### 7.2 阶段1: Event创建 {#stage-1-creation}

**三种创建时机：**

**时机1: 初始化时**
```python
def initialize_simulation():
    """创建初始event"""
    # 所有无依赖的操作可以立即调度
    for op in operations:
        if len(op.dependencies) == 0:
            # 创建START event
            start_event = Event(
                time=0,
                type=EventType.START,
                operation_id=op.id
            )
            event_queue.enqueue(start_event)
            print(f"[初始化] 创建操作{op.id}的START event")
```

**时机2: 处理event时 (因果关系)**
```python
def handle_start_event(event):
    """处理START event, 创建COMPLETE event"""
    op = get_operation(event.operation_id)
    
    # 计算完成时间
    duration = calculate_duration(op)
    complete_time = event.time + duration
    
    # 创建COMPLETE event作为START的后果
    complete_event = Event(
        time=complete_time,
        type=EventType.COMPLETE,
        operation_id=op.id
    )
    event_queue.enqueue(complete_event)
    print(f"[因果] 操作{op.id}将在时间{complete_time}完成")
```

**时机3: 依赖满足时 (notify触发)**
```python
def handle_complete_event(event):
    """处理COMPLETE event, 可能触发依赖的START event"""
    completed_op_id = event.operation_id
    
    # 标记完成
    completed_operations.add(completed_op_id)
    
    # 找到所有依赖这个操作的后继操作
    dependents = dependency_graph.get_dependents(completed_op_id)
    
    for dep_op in dependents:
        # 检查该操作的所有依赖是否都满足了
        if all_dependencies_satisfied(dep_op):
            # 创建START event (notify机制!)
            start_event = Event(
                time=current_time,  # 可以立即开始
                type=EventType.START,
                operation_id=dep_op.id
            )
            event_queue.enqueue(start_event)
            print(f"[Notify] 操作{dep_op.id}依赖已满足，创建START event")
```

---

#### 7.3 阶段2: Event入队 {#stage-2-enqueue}

**实现：优先队列 (最小堆)**

```python
class EventQueue:
    def __init__(self):
        # Python的PriorityQueue基于最小堆
        self.queue = PriorityQueue()
    
    def enqueue(self, event):
        """
        将event加入队列
        时间复杂度: O(log n)
        """
        self.queue.put(event)
        
        # 调试输出
        if DEBUG_MODE:
            print(f"[入队] Event@{event.time}: {event.type} "
                  f"for Op{event.operation_id}")
    
    def dequeue(self):
        """
        取出最早的event
        时间复杂度: O(log n)
        """
        return self.queue.get()
    
    def peek(self):
        """查看最早event但不移除"""
        return self.queue.queue[0]
    
    def empty(self):
        """队列是否为空"""
        return self.queue.empty()
    
    def size(self):
        """队列中event数量"""
        return self.queue.qsize()
```

**关键特性：**

1. **自动排序**: 按时间自动排序，无需手动维护
2. **高效**: 插入和删除都是O(log n)
3. **正确性**: 保证总是取出时间最早的event

**示例：**

```python
# 创建队列
queue = EventQueue()

# 以任意顺序入队
queue.enqueue(Event(time=100, type=COMPLETE, op=1))  # 后发生
queue.enqueue(Event(time=50, type=START, op=2))      # 先发生
queue.enqueue(Event(time=75, type=COMPLETE, op=2))   # 中间

# 内部自动排序为: [50, 75, 100]

# 出队总是按时间顺序
event1 = queue.dequeue()  # Event@50
event2 = queue.dequeue()  # Event@75
event3 = queue.dequeue()  # Event@100
```

---

#### 7.4 阶段3: Event出队 {#stage-3-dequeue}

**主仿真循环：**

```python
class Simulator:
    def run(self):
        """主仿真循环"""
        print("=== 仿真开始 ===")
        
        while not self.event_queue.empty():
            # 1. 出队最早的event
            event = self.event_queue.dequeue()
            
            # 2. 关键：推进仿真时间
            old_time = self.current_time
            self.current_time = event.time
            
            if self.current_time > old_time:
                print(f"\n[时间跳跃] {old_time} → {self.current_time}")
            
            # 3. 处理event
            print(f"[处理Event] 时间{self.current_time}: "
                  f"{event.type} for 操作{event.operation_id}")
            
            self.dispatch_event(event)
            
            # 4. 尝试调度就绪的操作
            self.try_schedule_ready_operations()
        
        print(f"\n=== 仿真结束 ===")
        print(f"总周期数: {self.current_time}")
```

**关键点：**

1. **时间跳跃**: `current_time = event.time` 是核心
   - 不是 `current_time += 1` (那是cycle-accurate)
   - 直接跳到event发生的时间
   
2. **单调性**: 时间只增不减
   - Event必须按时间顺序处理
   - 不能创建过去的event

3. **完整性**: 必须处理完队列中所有event

**时间跳跃示例：**

```
初始: current_time = 0
队列: [Event@50, Event@100, Event@150]

迭代1:
  出队 Event@50
  current_time = 50  ← 从0跳到50，跳过了1-49
  处理event

迭代2:
  出队 Event@100
  current_time = 100  ← 从50跳到100，跳过了51-99
  处理event

迭代3:
  出队 Event@150
  current_time = 150  ← 从100跳到150，跳过了101-149
  处理event

结果: 只执行了3次迭代，而不是150次！
```

---

#### 7.5 阶段4: Event分发 {#stage-4-dispatch}

**根据event类型调用对应的handler:**

```python
def dispatch_event(self, event):
    """根据event类型分发到对应处理函数"""
    
    if event.type == EventType.OPERATION_START:
        self.handle_operation_start(event)
        
    elif event.type == EventType.OPERATION_COMPLETE:
        self.handle_operation_complete(event)
        
    elif event.type == EventType.RESOURCE_FREE:
        self.handle_resource_free(event)
        
    else:
        raise ValueError(f"未知的event类型: {event.type}")
```

**各类型event的职责：**

| Event类型 | 职责 | 创建时机 | 后续event |
|-----------|------|----------|-----------|
| **START** | 开始操作<br>获取资源 | 调度时 | COMPLETE |
| **COMPLETE** | 完成操作<br>释放资源<br>notify依赖 | START处理时 | 依赖的START |
| **RESOURCE_FREE** | 标记资源可用<br>尝试调度等待的操作 | COMPLETE处理时 | 可能触发START |

---

#### 7.6 阶段5: 处理与更新 {#stage-5-process}

**4类状态需要更新：**

**更新1: 操作状态**

```python
class Operation:
    """操作的状态"""
    state: OperationState  # PENDING/READY/RUNNING/COMPLETED
    start_time: int
    end_time: int
    
def handle_operation_start(self, event):
    op = self.operations[event.operation_id]
    
    # 更新操作状态
    op.state = OperationState.RUNNING
    op.start_time = self.current_time
    
    print(f"  → 操作{op.id}状态: READY → RUNNING")
    print(f"  → 开始时间: {op.start_time}")
```

**更新2: 资源状态**

```python
class Resource:
    """资源的状态"""
    busy_until: int = 0
    current_user: Optional[int] = None
    
def handle_operation_start(self, event):
    op = self.operations[event.operation_id]
    
    # 获取资源
    for resource in op.required_resources:
        resource.busy_until = self.current_time + op.duration
        resource.current_user = op.id
        
        print(f"  → 资源{resource.name}被获取")
        print(f"    占用至时间{resource.busy_until}")
```

**更新3: 依赖状态**

```python
class DependencyTracker:
    """依赖追踪器"""
    completed: Set[int]          # 已完成的操作
    pending: Set[int]            # 等待依赖的操作
    ready: Set[int]              # 就绪可调度的操作
    
def handle_operation_complete(self, event):
    # 标记操作完成
    self.dependency_tracker.completed.add(event.operation_id)
    self.dependency_tracker.pending.discard(event.operation_id)
    self.dependency_tracker.ready.discard(event.operation_id)
    
    print(f"  → 操作{event.operation_id}标记为已完成")
    
    # 检查依赖这个操作的后继 (Notify机制！)
    self.notify_dependents(event.operation_id)
```

**更新4: 统计信息**

```python
class Statistics:
    """统计信息"""
    total_operations: int = 0
    total_cycles: int = 0
    resource_busy_time: Dict[str, int] = {}
    
def handle_operation_complete(self, event):
    # 更新统计
    self.stats.total_operations += 1
    self.stats.total_cycles = self.current_time
    
    # 更新资源利用率
    op = self.operations[event.operation_id]
    duration = op.end_time - op.start_time
    for resource in op.used_resources:
        self.stats.resource_busy_time[resource.name] += duration
```

---

#### 7.7 阶段6: 创建新Event {#stage-6-create-new}

**3种新event创建场景：**

**场景1: 因果event (必然发生)**

```python
def handle_operation_start(self, event):
    """START event必然导致COMPLETE event"""
    op = self.operations[event.operation_id]
    
    # 计算完成时间
    duration = self.perf_model.calculate_duration(op)
    complete_time = self.current_time + duration
    
    # 创建COMPLETE event
    complete_event = Event(
        time=complete_time,
        type=EventType.OPERATION_COMPLETE,
        operation_id=op.id
    )
    self.event_queue.enqueue(complete_event)
    
    print(f"  → 创建COMPLETE event @ 时间{complete_time}")
```

**场景2: 资源释放event**

```python
def handle_operation_complete(self, event):
    """COMPLETE event导致资源释放"""
    op = self.operations[event.operation_id]
    
    # 立即创建资源释放event
    for resource in op.used_resources:
        free_event = Event(
            time=self.current_time,  # 立即释放
            type=EventType.RESOURCE_FREE,
            resource_id=resource.id
        )
        self.event_queue.enqueue(free_event)
```

**场景3: Notify触发的event (重要！)**

```python
def handle_operation_complete(self, event):
    """COMPLETE event可能触发依赖操作的START event"""
    completed_op_id = event.operation_id
    
    # Notify机制：通知所有等待的后继操作
    for dependent_op in self.get_dependents(completed_op_id):
        # 检查依赖是否全部满足
        if self.all_dependencies_satisfied(dependent_op):
            # 依赖满足，可以调度了！
            # 检查资源是否可用
            if self.resources_available(dependent_op):
                # 创建START event
                start_event = Event(
                    time=self.current_time,
                    type=EventType.START,
                    operation_id=dependent_op.id
                )
                self.event_queue.enqueue(start_event)
                print(f"  → [Notify] 操作{dependent_op.id}就绪，创建START")
            else:
                # 资源不可用，加入就绪队列
                self.ready_queue.add(dependent_op.id)
                print(f"  → [Notify] 操作{dependent_op.id}就绪但资源不足")
```

---

#### 7.8 完整示例追踪 {#complete-example}

**场景：2个操作，Op1完成后Op2才能开始**

```python
"""
完整追踪event生命周期

场景:
  - 操作1: 无依赖，需要50周期
  - 操作2: 依赖操作1，需要30周期
"""

# === 初始化 ===
print("=== 初始化阶段 ===")

# 创建Event@0 for Op1 (阶段1: 创建)
event1_start = Event(time=0, type=START, op_id=1)
event_queue.enqueue(event1_start)  # 阶段2: 入队

print("[创建] Event@0: START for Op1")
print("[入队] 队列: [Event@0]")

# === 主循环开始 ===
print("\n=== 仿真循环 ===")

# 迭代1: 处理Op1的START
print("\n--- 迭代1 ---")

# 阶段3: 出队
event = event_queue.dequeue()  # Event@0
current_time = event.time      # 时间 = 0

print(f"[出队] Event@{event.time}: {event.type} for Op{event.operation_id}")
print(f"[时间] current_time = {current_time}")

# 阶段4: 分发
dispatch_event(event)  # 调用handle_start()

# 阶段5: 处理与更新
def handle_start(event):
    op = operations[event.operation_id]
    
    # 更新1: 操作状态
    op.state = RUNNING
    op.start_time = current_time
    print(f"[更新] Op{op.id}状态: READY → RUNNING")
    
    # 更新2: 资源状态
    resource.busy_until = current_time + op.duration  # 0 + 50 = 50
    resource.current_user = op.id
    print(f"[更新] 资源占用至时间{resource.busy_until}")
    
    # 阶段6: 创建新Event
    complete_event = Event(
        time=current_time + op.duration,  # 0 + 50 = 50
        type=COMPLETE,
        op_id=op.id
    )
    event_queue.enqueue(complete_event)
    print(f"[创建] Event@50: COMPLETE for Op{op.id}")

# 执行handler
handle_start(event)

print(f"[队列] [Event@50]")

# 迭代2: 处理Op1的COMPLETE
print("\n--- 迭代2 ---")

# 阶段3: 出队
event = event_queue.dequeue()  # Event@50
old_time = current_time
current_time = event.time      # 时间 = 50

print(f"[出队] Event@{event.time}: {event.type} for Op{event.operation_id}")
print(f"[时间跳跃] {old_time} → {current_time}  (跳过了1-49)")

# 阶段4: 分发
dispatch_event(event)  # 调用handle_complete()

# 阶段5: 处理与更新
def handle_complete(event):
    op = operations[event.operation_id]
    
    # 更新1: 操作状态
    op.state = COMPLETED
    op.end_time = current_time
    print(f"[更新] Op{op.id}状态: RUNNING → COMPLETED")
    
    # 更新2: 资源状态
    resource.busy_until = current_time
    resource.current_user = None
    print(f"[更新] 资源释放")
    
    # 更新3: 依赖状态
    completed_ops.add(op.id)
    print(f"[更新] Op{op.id}标记为已完成")
    
    # 阶段6: Notify依赖的操作
    dependents = get_dependents(op.id)  # [Op2]
    for dep_op in dependents:
        if all_dependencies_satisfied(dep_op):
            # Op2的依赖已满足，创建START event
            start_event = Event(
                time=current_time,  # 50
                type=START,
                op_id=dep_op.id
            )
            event_queue.enqueue(start_event)
            print(f"[Notify] Op{dep_op.id}依赖满足，创建Event@{current_time}")

# 执行handler
handle_complete(event)

print(f"[队列] [Event@50]")  # Op2的START

# 迭代3: 处理Op2的START
print("\n--- 迭代3 ---")

event = event_queue.dequeue()  # Event@50 for Op2
current_time = event.time      # 时间仍是50 (同一时刻)

print(f"[出队] Event@{event.time}: {event.type} for Op{event.operation_id}")
print(f"[时间] current_time = {current_time}")

# ... 处理Op2的START，创建COMPLETE@80 ...
# (类似迭代1)

# 迭代4: 处理Op2的COMPLETE
print("\n--- 迭代4 ---")

event = event_queue.dequeue()  # Event@80
current_time = event.time      # 时间 = 80

print(f"[出队] Event@{event.time}: {event.type} for Op{event.operation_id}")
print(f"[时间跳跃] 50 → 80  (跳过了51-79)")

# ... 处理Op2的COMPLETE ...

print("\n=== 仿真结束 ===")
print(f"总周期数: {current_time}  (80)")
print(f"总迭代数: 4")
print(f"跳过的周期: 1-49, 51-79  (共78个周期)")

# 输出总结:
# ============================================================
# 时间线:
#   0: Op1 START
#   1-49: (跳过，什么都没发生)
#   50: Op1 COMPLETE, Op2 START (同一时刻!)
#   51-79: (跳过，什么都没发生)
#   80: Op2 COMPLETE
#
# Event处理顺序:
#   1. Event@0: START Op1
#   2. Event@50: COMPLETE Op1
#   3. Event@50: START Op2    ← 同一时刻的多个event
#   4. Event@80: COMPLETE Op2
#
# 关键观察:
#   - 只执行了4次迭代，而不是80次
#   - 时间直接跳跃，跳过无事发生的周期
#   - 同一时刻可以有多个event
#   - Event之间有因果链: START → COMPLETE → Notify → START
# ============================================================
```

---

## 关键要点总结

### Event生命周期的6个阶段

```
1. 创建 → 2. 入队 → 3. 出队 → 4. 分发 → 5. 处理 → 6. 创建新Event
   ↑                                                        ↓
   └────────────────────── 循环 ──────────────────────────┘
```

### 最重要的3个点

1. **时间跳跃**: `current_time = event.time` (不是 +=1)
2. **优先队列**: 自动按时间排序，O(log n)
3. **因果链**: Event处理会创建新的Event，形成因果链

### 常见错误

❌ **错误1**: 忘记推进时间
```python
# 错误
event = event_queue.dequeue()
# 忘记: current_time = event.time
```

❌ **错误2**: 创建过去的event
```python
# 错误
event = Event(time=current_time - 10, ...)  # 过去的时间！
```

❌ **错误3**: 没有创建后续event
```python
# 错误
def handle_start(event):
    op.state = RUNNING
    # 忘记: 创建COMPLETE event
```

### 调试技巧

```python
def dispatch_event(self, event):
    """添加调试日志"""
    print(f"\n[T={self.current_time}] Processing {event.type}")
    print(f"  Queue size: {self.event_queue.size()}")
    print(f"  Resource states: {self.get_resource_states()}")
    
    # 原有逻辑...
    
    print(f"  Events created: {new_events_count}")
    print(f"  Next event @ {self.event_queue.peek().time}")
```

---

**下一篇**: [第2部分B：资源竞争建模](./第2部分B_资源竞争建模.md)

*本文档行数: ~640行 (原2部分的约15%)*

