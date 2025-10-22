# 硬件性能建模完整指南

## 第2部分 D：Event创建时机与时间推进机制

>  **本文是第2部分的第4个子文档，详细讲解Event创建时机和时间推进**   
> 其他子文档：[Event生命周期](./第2部分A_Event生命周期.md) | [资源竞争](./第2部分B_资源竞争建模.md) | [依赖与Notify](./第2部分C_依赖与Notify机制.md) | [Event与资源关系](./第2部分E_Event与资源关系.md)

---

**重要说明** ：本文档内容较长（约1,550行），因为它包含了大量实际代码示例和详细解释。建议分段阅读。

---

## 📖 完整内容

**本文档包含原文档第10节的完整内容：**

### 10. Event创建时机与时间推进机制 {#event-creation-timing}

这一节回答三个核心问题：

1.  **什么时候需要创建event?** 
2.  **不同cycle释放资源需要创建多少个event?** 
3.  **什么时候推进仿真时间?** 

#### 10.1 Event创建的判断原则

**核心原则：当有"未来需要发生的事情"时，就创建event**

```python
问题: 什么时候需要创建event?

判断依据:
┌─────────────────────────────────────────────┐
│ 问自己: "现在做完这件事后，                  │
│          未来还有什么要发生的吗?"            │
│                                             │
│ 如果有 → 创建event                          │
│ 如果没有 → 不创建                           │
└─────────────────────────────────────────────┘
```

**6种需要创建event的场景：**

**场景1: 操作有确定的结束时间**

```python
def handle_operation_start(event):
    """
    场景1: 操作开始后，必然有结束
    """
    op = get_operation(event.operation_id)
    
    # 计算结束时间
    duration = calculate_duration(op)
    end_time = current_time + duration
    
    # 问: 未来有什么要发生?
    # 答: 操作会在end_time结束
    # 结论: 创建COMPLETE event
    complete_event = Event(
        time=end_time,
        type=EventType.OPERATION_COMPLETE,
        operation_id=op.id
    )
    event_queue.enqueue(complete_event)
    
    print(f"[创建Event] 操作{op.id}将在时间{end_time}完成")
```

**场景2: 资源在未来某个时间释放**

```python
def handle_resource_acquire(resource, user_id, duration):
    """
    场景2: 资源被占用后，未来需要释放
    """
    # 更新资源状态
    release_time = current_time + duration
    resource.busy_until = release_time
    resource.current_user = user_id
    
    # 问: 未来有什么要发生?
    # 答: 资源会在release_time变为可用
    # 结论: 创建RESOURCE_FREE event
    free_event = Event(
        time=release_time,
        type=EventType.RESOURCE_FREE,
        resource_id=resource.id,
        user_id=user_id
    )
    event_queue.enqueue(free_event)
    
    print(f"[创建Event] 资源{resource.name}将在时间{release_time}释放")
```

**场景3: 依赖满足后，操作可以立即调度**

```python
def notify_dependents(completed_op_id):
    """
    场景3: 依赖满足，操作立即就绪
    """
    for dep_op_id in get_dependents(completed_op_id):
        if all_dependencies_satisfied(dep_op_id):
            # 问: 未来有什么要发生?
            # 答: 这个操作现在可以开始了
            # 结论: 创建START event (时间是current_time)
            
            if resources_available(dep_op_id):
                start_event = Event(
                    time=current_time,  # 立即！
                    type=EventType.OPERATION_START,
                    operation_id=dep_op_id
                )
                event_queue.enqueue(start_event)
                print(f"[创建Event] 操作{dep_op_id}依赖满足，立即开始")
```

**场景4: 延迟调度 (资源不可用)**

```python
def try_schedule_operation(op):
    """
    场景4: 资源不可用，需要等待
    """
    # 检查资源可用性
    earliest_resource_time = get_earliest_resource_available_time(op)
    
    if earliest_resource_time > current_time:
        # 问: 未来有什么要发生?
        # 答: 在earliest_resource_time，资源会可用，可以尝试调度
        # 结论: 创建SCHEDULE_ATTEMPT event
        
        schedule_event = Event(
            time=earliest_resource_time,
            type=EventType.SCHEDULE_ATTEMPT,
            operation_id=op.id
        )
        event_queue.enqueue(schedule_event)
        
        print(f"[创建Event] 操作{op.id}延迟到时间{earliest_resource_time}调度")
```

**场景5: 超时或定时检查**

```python
def setup_timeout(op, timeout_duration):
    """
    场景5: 需要在未来某时刻做超时检查
    """
    timeout_time = current_time + timeout_duration
    
    # 问: 未来有什么要发生?
    # 答: 需要在timeout_time检查操作是否超时
    # 结论: 创建TIMEOUT_CHECK event
    
    timeout_event = Event(
        time=timeout_time,
        type=EventType.TIMEOUT_CHECK,
        operation_id=op.id
    )
    event_queue.enqueue(timeout_event)
    
    print(f"[创建Event] 操作{op.id}的超时检查在时间{timeout_time}")
```

**场景6: 周期性事件**

```python
def setup_periodic_monitoring(resource, period):
    """
    场景6: 周期性监控或统计
    """
    next_check_time = current_time + period
    
    # 问: 未来有什么要发生?
    # 答: 需要在next_check_time做一次监控
    # 结论: 创建MONITOR event
    
    monitor_event = Event(
        time=next_check_time,
        type=EventType.MONITOR,
        resource_id=resource.id
    )
    event_queue.enqueue(monitor_event)
    
    print(f"[创建Event] 资源{resource.name}的监控在时间{next_check_time}")
```

---

#### 10.2 多资源释放的Event粒度选择

**关键问题：** 如果需要在不同cycle释放多个资源，需要创建多少个event?

**选项1: 为每个资源释放创建独立event (细粒度)**

```python
def handle_operation_complete_fine_grained(event):
    """
    方案1: 细粒度 - 每个资源释放都创建独立event
    
    优点:
    - 精确：每个资源在确切的时间点释放
    - 灵活：不同资源可以有不同的释放策略
    - 易于调试：每个event对应明确的动作
    
    缺点:
    - Event数量多
    - 可能产生大量同时间的event
    """
    op = get_operation(event.operation_id)
    
    # 释放多个资源，每个在不同时间
    resources_and_times = [
        (channel, current_time + 10),      # 通道10周期后释放
        (port, current_time + 20),         # 端口20周期后释放
        (fifo, current_time + 5),          # FIFO 5周期后释放
        (compute_unit, current_time),      # 计算单元立即释放
    ]
    
    # 为每个资源创建独立的释放event
    for resource, release_time in resources_and_times:
        free_event = Event(
            time=release_time,
            type=EventType.RESOURCE_FREE,
            resource_id=resource.id,
            resource_type=resource.type
        )
        event_queue.enqueue(free_event)
        
        print(f"[创建Event] {resource.name}在时间{release_time}释放")

# 结果: 创建了4个event
```

**选项2: 创建一个综合event，处理时按时间释放 (粗粒度)**

```python
def handle_operation_complete_coarse_grained(event):
    """
    方案2: 粗粒度 - 创建一个event，包含所有释放信息
    
    优点:
    - Event数量少
    - 减少event queue开销
    
    缺点:
    - 不够精确：可能过早或过晚触发
    - 复杂：需要在event处理时判断哪些资源该释放
    - 难以优化：无法利用时间局部性
    """
    op = get_operation(event.operation_id)
    
    # 记录所有资源的释放时间
    release_schedule = {
        channel: current_time + 10,
        port: current_time + 20,
        fifo: current_time + 5,
        compute_unit: current_time,
    }
    
    # 找到最晚的释放时间
    latest_release_time = max(release_schedule.values())
    
    # 创建一个综合event
    release_event = Event(
        time=latest_release_time,
        type=EventType.RESOURCES_RELEASE,
        operation_id=op.id,
        release_schedule=release_schedule  # 附带所有信息
    )
    event_queue.enqueue(release_event)
    
    print(f"[创建Event] 操作{op.id}的资源释放event在时间{latest_release_time}")

def handle_resources_release(event):
    """处理综合释放event"""
    for resource, release_time in event.release_schedule.items():
        if current_time >= release_time:
            resource.release()
            print(f"  释放{resource.name}")

# 结果: 只创建了1个event，但可能不够及时
```

**选项3: 混合方案 (推荐) ✓**

```python
def handle_operation_complete_hybrid(event):
    """
    方案3: 混合方案 - 按释放时间分组
    
    原则:
    1. 同一时间释放的资源 → 合并为一个event
    2. 不同时间释放的资源 → 分别创建event
    
    这是实践中最常用的方案！
    """
    op = get_operation(event.operation_id)
    
    # 资源按释放时间分组
    release_groups = defaultdict(list)
    release_groups[current_time].append(compute_unit)     # 立即释放
    release_groups[current_time + 5].append(fifo)         # 5周期后
    release_groups[current_time + 10].append(channel)     # 10周期后
    release_groups[current_time + 20].append(port)        # 20周期后
    
    # 为每个时间点创建一个event
    for release_time, resources in release_groups.items():
        free_event = Event(
            time=release_time,
            type=EventType.RESOURCE_FREE,
            resources=resources  # 一组资源
        )
        event_queue.enqueue(free_event)
        
        resource_names = [r.name for r in resources]
        print(f"[创建Event] 时间{release_time}释放: {resource_names}")

# 结果: 创建了4个event (因为正好4个不同时间)
# 如果有资源在同一时间释放，event数量会更少
```

**实际案例：DLA GDMA传输**

```python
class GDMATransfer:
    """真实案例: GDMA传输涉及多个资源"""
    
    def complete(self):
        """
        传输完成后，不同资源在不同时间释放:
        
        时间线:
        current_time:           XFE释放, OB entries开始释放
        current_time + 5:       OB entries完全释放  
        current_time + 10:      GDMA channel释放
        current_time + 20:      源端口释放
        current_time + 30:      目的端口释放
        """
        # 使用混合方案
        
        # 立即释放: XFE, 开始释放OB
        immediate_release_event = Event(
            time=current_time,
            type=EventType.IMMEDIATE_RELEASE,
            resources=[self.xfe_resource, self.ob_resource]
        )
        event_queue.enqueue(immediate_release_event)
        
        # 5周期后: OB完全释放
        ob_full_release_event = Event(
            time=current_time + 5,
            type=EventType.OB_FULL_RELEASE,
            ob_entries=self.ob_entries
        )
        event_queue.enqueue(ob_full_release_event)
        
        # 10周期后: Channel释放
        channel_release_event = Event(
            time=current_time + 10,
            type=EventType.CHANNEL_RELEASE,
            channel=self.channel
        )
        event_queue.enqueue(channel_release_event)
        
        # 20周期后: 源端口释放
        src_port_release_event = Event(
            time=current_time + 20,
            type=EventType.PORT_RELEASE,
            port=self.src_port
        )
        event_queue.enqueue(src_port_release_event)
        
        # 30周期后: 目的端口释放
        dst_port_release_event = Event(
            time=current_time + 30,
            type=EventType.PORT_RELEASE,
            port=self.dst_port
        )
        event_queue.enqueue(dst_port_release_event)
        
        print(f"[GDMA] 传输{self.id}完成，创建了5个释放event")
```

**选择建议：**

```
┌────────────────────────────────────────────────────────┐
│ 选择Event粒度的决策树                                   │
└────────────────────────────────────────────────────────┘

问题1: 资源释放时间是否相同?
  ├─ 是 → 合并为一个event (粗粒度)
  └─ 否 → 继续问题2

问题2: 时间间隔是否很小(<5 cycle)?
  ├─ 是 → 可以考虑合并 (适度粗粒度)
  └─ 否 → 继续问题3

问题3: 是否需要精确的资源释放时机?
  ├─ 是 → 为每个时间点创建event (细粒度)
  └─ 否 → 可以合并 (粗粒度)

推荐: 使用混合方案，按释放时间分组
```

---

#### 10.3 仿真时间推进机制

**核心问题：** 什么时候推进仿真时间？

**答案：每次从event queue取出event时！**

```python
class Simulator:
    def __init__(self):
        self.current_time = 0
        self.event_queue = PriorityQueue()
    
    def run(self):
        """
        主仿真循环 - 时间推进的唯一地方
        """
        print(f"仿真开始 @ 时间0")
        
        while not self.event_queue.empty():
            # ====================================
            # 关键: 这是时间推进的唯一位置！
            # ====================================
            event = self.event_queue.get()
            old_time = self.current_time
            self.current_time = event.time  # ← 时间推进！
            # ====================================
            
            # 时间跳跃检测
            if self.current_time > old_time:
                time_jump = self.current_time - old_time
                print(f"\n[时间推进] {old_time} → {self.current_time} "
                      f"(跳过{time_jump}周期)")
            elif self.current_time == old_time:
                print(f"[同一时间] 时间{self.current_time}的另一个event")
            else:
                # 这不应该发生！
                raise RuntimeError(f"时间倒退! {old_time} → {self.current_time}")
            
            # 处理event
            self.handle_event(event)
        
        print(f"\n仿真结束 @ 时间{self.current_time}")
```

**时间推进的3种情况：**

**情况1: 时间跳跃 (最常见)**

```python
示例:
当前时间: 50
Event队列: [Event@100, Event@150, Event@200]

从队列取出Event@100:
  current_time = 100  ← 从50跳到100
  跳过了51-99这49个周期
  
关键点:
- 这49个周期内没有任何事情发生
- 不需要逐周期模拟，直接跳过
- 这是离散事件仿真高效的原因！

对比cycle-accurate仿真:
  for cycle in range(50, 100):  # 需要迭代49次！
      check_all_components()     # 每次都检查所有组件
  # 慢，但精确
```

**情况2: 同一时间的多个event**

```python
示例:
当前时间: 100
Event队列: [Event@100_A, Event@100_B, Event@100_C, Event@150]

取出Event@100_A:
  current_time = 100  (保持不变)
  处理event A
  
取出Event@100_B:
  current_time = 100  (仍然不变)
  处理event B
  
取出Event@100_C:
  current_time = 100  (还是不变)
  处理event C
  
取出Event@150:
  current_time = 150  (时间推进!)
  处理event

关键点:
- 同一时间的多个event会连续处理
- current_time不变，直到处理完所有同时刻的event
- 这模拟了"同时发生"的事件
```

**情况3: 时间0的初始event**

```python
初始化:
  current_time = 0
  event_queue = [Event@0_init1, Event@0_init2, Event@50]

第一个event:
  取出Event@0_init1
  current_time = 0  (保持0)
  处理初始化event

第二个event:
  取出Event@0_init2
  current_time = 0  (仍然0)
  处理另一个初始化event

第三个event:
  取出Event@50
  current_time = 50  (第一次时间推进!)
```

---

#### 10.4 时间推进的5个关键问题

**问题1: 可以在event处理中直接修改current_time吗?**

```python
# ❌ 错误做法
def handle_operation_complete(event):
    # 不要这样做！
    self.current_time += 10  # 错误：手动推进时间
    
    # 这会破坏仿真的时间顺序
    # 下一个event可能在更早的时间！

# ✓ 正确做法
def handle_operation_complete(event):
    # 只创建未来的event，让主循环推进时间
    next_event = Event(
        time=self.current_time + 10,  # 未来的时间
        type=EventType.SOMETHING
    )
    self.event_queue.enqueue(next_event)
    
    # current_time由主循环管理，不要手动修改
```

**问题2: 可以创建过去时间的event吗?**

```python
# ❌ 绝对禁止
def bad_example():
    past_event = Event(
        time=self.current_time - 10,  # 过去的时间！
        type=EventType.SOMETHING
    )
    self.event_queue.enqueue(past_event)
    # 这会导致时间倒退，破坏因果关系

# ✓ 只能创建当前或未来的event
def good_example():
    # 当前时间 - 立即处理
    immediate_event = Event(
        time=self.current_time,  # 当前
        type=EventType.IMMEDIATE
    )
    
    # 未来时间 - 延迟处理
    future_event = Event(
        time=self.current_time + 100,  # 未来
        type=EventType.DELAYED
    )
    
    self.event_queue.enqueue(immediate_event)
    self.event_queue.enqueue(future_event)
```

**问题3: 如果多个event时间相同，处理顺序重要吗?**

```python
# 重要性取决于event之间是否有依赖关系

# 场景1: 无依赖 - 顺序不重要
Event@100: 资源A释放
Event@100: 资源B释放
Event@100: 统计更新
# 这些可以任意顺序处理

# 场景2: 有依赖 - 顺序很重要！
Event@100: 操作X完成        # 必须先处理
Event@100: 操作Y开始        # 依赖X，必须后处理

# 解决方案1: 使用优先级
class Event:
    def __init__(self, time, type, priority=0):
        self.time = time
        self.type = type
        self.priority = priority
    
    def __lt__(self, other):
        if self.time != other.time:
            return self.time < other.time
        else:
            return self.priority < other.priority  # 同时间按优先级

# 解决方案2: 使用因果关系（推荐）
# 完成event创建开始event时，设置稍晚的时间
complete_event.time = 100
start_event.time = 100.0001  # 稍晚一点点
```

**问题4: 如何处理"立即"需要发生的事情?**

```python
def handle_operation_complete(event):
    """
    操作完成后，有些事情需要"立即"发生
    """
    # 选项1: 直接在当前event处理中完成（推荐简单场景）
    # 优点: 简单直接
    # 缺点: 无法被其他event中断
    resource.release()
    notify_dependents(event.operation_id)
    
    # 选项2: 创建current_time的新event（推荐复杂场景）
    # 优点: 保持一致性，所有动作都是event
    # 缺点: 稍微复杂一点
    immediate_event = Event(
        time=self.current_time,  # 立即
        type=EventType.RESOURCE_RELEASE,
        resource=resource
    )
    self.event_queue.enqueue(immediate_event)
    
    # 选择建议:
    # - 简单状态更新 → 直接在当前event中做
    # - 可能触发其他动作 → 创建新event
```

**问题5: 如何确保时间推进的正确性?**

```python
class Simulator:
    """添加时间推进的安全检查"""
    
    def run(self):
        last_time = -1  # 追踪上一个时间
        
        while not self.event_queue.empty():
            event = self.event_queue.get()
            
            # 安全检查1: 时间单调性
            if event.time < self.current_time:
                raise RuntimeError(
                    f"时间倒退! current={self.current_time}, "
                    f"event.time={event.time}"
                )
            
            # 安全检查2: 时间有效性
            if event.time < 0:
                raise ValueError(f"无效的时间: {event.time}")
            
            # 记录时间推进
            if event.time > self.current_time:
                time_jump = event.time - self.current_time
                self.stats.record_time_jump(time_jump)
            
            # 推进时间
            last_time = self.current_time
            self.current_time = event.time
            
            # 处理event
            self.handle_event(event)
            
            # 调试输出
            if DEBUG:
                print(f"[时间] {last_time} → {self.current_time}")
```

---

#### 10.5 完整示例：时间推进与Event创建

```python
"""
完整示例: 展示时间推进和event创建的配合
"""

class CompleteSimulator:
    def __init__(self):
        self.current_time = 0
        self.event_queue = PriorityQueue()
        self.operations = {}
        self.resources = {}
    
    def initialize(self):
        """
        初始化: 创建初始event
        """
        # 操作0: 无依赖，立即可调度
        init_event = Event(
            time=0,
            type=EventType.OPERATION_START,
            operation_id=0
        )
        self.event_queue.enqueue(init_event)
        print(f"[初始化] 创建操作0的START event @ 时间0")
    
    def run(self):
        """主循环"""
        print(f"\n{'='*60}")
        print(f"仿真开始")
        print(f"{'='*60}\n")
        
        while not self.event_queue.empty():
            # 取出最早的event
            event = self.event_queue.get()
            old_time = self.current_time
            
            # 推进时间
            self.current_time = event.time
            
            # 报告时间变化
            if self.current_time > old_time:
                print(f"\n{'─'*60}")
                print(f"⏰ 时间推进: {old_time} → {self.current_time}")
                print(f"   (跳过 {self.current_time - old_time} 周期)")
                print(f"{'─'*60}\n")
            
            # 处理event
            print(f"[{self.current_time:4d}] 处理Event: {event.type} "
                  f"for 操作{event.operation_id}")
            self.dispatch_event(event)
        
        print(f"\n{'='*60}")
        print(f"仿真结束 @ 时间{self.current_time}")
        print(f"{'='*60}\n")
    
    def dispatch_event(self, event):
        """分发event"""
        if event.type == EventType.OPERATION_START:
            self.handle_operation_start(event)
        elif event.type == EventType.OPERATION_COMPLETE:
            self.handle_operation_complete(event)
        elif event.type == EventType.RESOURCE_FREE:
            self.handle_resource_free(event)
    
    def handle_operation_start(self, event):
        """
        处理START event
        """
        op = self.operations[event.operation_id]
        
        # 1. 获取资源
        for resource_id in op.required_resources:
            resource = self.resources[resource_id]
            resource.acquire(op.id, self.current_time, op.duration)
            print(f"  → 获取资源{resource_id}")
        
        # 2. 更新操作状态
        op.state = OperationState.RUNNING
        op.start_time = self.current_time
        op.end_time = self.current_time + op.duration
        print(f"  → 操作开始执行")
        
        # 3. 创建COMPLETE event (因果关系)
        complete_event = Event(
            time=op.end_time,
            type=EventType.OPERATION_COMPLETE,
            operation_id=op.id
        )
        self.event_queue.enqueue(complete_event)
        print(f"  → 创建COMPLETE event @ 时间{op.end_time}")
    
    def handle_operation_complete(self, event):
        """
        处理COMPLETE event
        """
        op = self.operations[event.operation_id]
        
        # 1. 更新操作状态
        op.state = OperationState.COMPLETED
        print(f"  → 操作完成")
        
        # 2. 创建资源释放event
        for resource_id in op.required_resources:
            resource = self.resources[resource_id]
            
            # 计算释放时间（可能不同）
            release_time = self.calculate_release_time(
                resource, op, self.current_time
            )
            
            # 创建释放event
            if release_time > self.current_time:
                # 延迟释放
                free_event = Event(
                    time=release_time,
                    type=EventType.RESOURCE_FREE,
                    resource_id=resource_id,
                    user_id=op.id
                )
                self.event_queue.enqueue(free_event)
                print(f"  → 创建资源{resource_id}释放event @ "
                      f"时间{release_time}")
            else:
                # 立即释放
                resource.release()
                print(f"  → 立即释放资源{resource_id}")
        
        # 3. Notify依赖这个操作的后继
        self.notify_dependents(op.id)
    
    def handle_resource_free(self, event):
        """
        处理RESOURCE_FREE event
        """
        resource = self.resources[event.resource_id]
        
        # 释放资源
        resource.release()
        print(f"  → 资源{event.resource_id}释放")
        
        # 尝试调度等待这个资源的操作
        waiting_ops = self.get_waiting_operations(resource)
        for op in waiting_ops:
            if self.can_schedule(op):
                # 创建START event
                start_event = Event(
                    time=self.current_time,
                    type=EventType.OPERATION_START,
                    operation_id=op.id
                )
                self.event_queue.enqueue(start_event)
                print(f"  → 操作{op.id}就绪，创建START event")
    
    def calculate_release_time(self, resource, op, current_time):
        """
        计算资源释放时间
        
        示例: 不同类型资源有不同的释放延迟
        """
        release_delays = {
            'channel': 10,    # 通道需要10周期清理
            'port': 5,        # 端口需要5周期清理
            'compute': 0,     # 计算单元立即释放
            'buffer': 2,      # 缓冲区需要2周期清理
        }
        
        delay = release_delays.get(resource.type, 0)
        return current_time + delay

# 运行示例
sim = CompleteSimulator()
sim.initialize()
sim.run()

# 输出示例:
# ============================================================
# 仿真开始
# ============================================================
#
# [   0] 处理Event: OPERATION_START for 操作0
#   → 获取资源channel0
#   → 获取资源port1
#   → 操作开始执行
#   → 创建COMPLETE event @ 时间100
#
# ────────────────────────────────────────────────────────────
# ⏰ 时间推进: 0 → 100
#    (跳过 100 周期)
# ────────────────────────────────────────────────────────────
#
# [ 100] 处理Event: OPERATION_COMPLETE for 操作0
#   → 操作完成
#   → 创建资源channel0释放event @ 时间110
#   → 创建资源port1释放event @ 时间105
#   → Notify后继操作...
#
# ────────────────────────────────────────────────────────────
# ⏰ 时间推进: 100 → 105
#    (跳过 5 周期)
# ────────────────────────────────────────────────────────────
#
# [ 105] 处理Event: RESOURCE_FREE for port1
#   → 资源port1释放
#   → 操作1就绪，创建START event
#
# [ 105] 处理Event: OPERATION_START for 操作1
#   → 获取资源port1
#   → ...
```

---

#### 10.6 最佳实践总结

**Event创建的最佳实践：**

```python
✓ 正确做法:
1. 只在有"未来要发生的事情"时创建event
2. 为不同时间的动作创建独立event
3. 相同时间的动作可以合并到一个event
4. 立即的简单动作直接执行，不创建event
5. 立即的复杂动作创建current_time的event

✗ 错误做法:
1. 为已经发生的事情创建event
2. 创建过去时间的event
3. 创建过多的细粒度event（过度设计）
4. 创建过少的粗粒度event（不够精确）
5. 在event处理中修改current_time
```

**时间推进的最佳实践：**

```python
✓ 正确做法:
1. 只在主循环的一个位置推进时间
2. 时间总是单调递增
3. 添加时间有效性检查
4. 记录时间跳跃用于调试和统计
5. 同一时间的event可以任意顺序处理（如果无依赖）

✗ 错误做法:
1. 在多个地方修改current_time
2. 在event处理中推进时间
3. 不检查时间单调性
4. 假设event会按创建顺序处理
5. 逐周期推进（那是cycle-accurate，不是event-driven）
```

**调试技巧：**

```python
def debug_event_creation(event, creation_location):
    """调试event创建"""
    print(f"[DEBUG] 创建Event")
    print(f"  时间: {event.time}")
    print(f"  类型: {event.type}")
    print(f"  当前时间: {current_time}")
    print(f"  创建位置: {creation_location}")
    
    # 检查
    if event.time < current_time:
        print(f"  ⚠️ 警告: 创建了过去的event!")
    elif event.time == current_time:
        print(f"  ℹ️ 立即event")
    else:
        delta = event.time - current_time
        print(f"  ℹ️ 延迟{delta}周期")

def debug_time_advance(old_time, new_time):
    """调试时间推进"""
    print(f"[DEBUG] 时间推进")
    print(f"  从: {old_time}")
    print(f"  到: {new_time}")
    print(f"  跳过: {new_time - old_time}周期")
    
    if new_time < old_time:
        print(f"  ❌ 错误: 时间倒退!")
    elif new_time == old_time:
        print(f"  ℹ️ 同一时间的另一个event")
```

---

#### 10.7 资源等待问题：如何避免轮询 {#resource-waiting}

**核心问题：** 如果需要等待一个资源释放，但不知道资源什么时候释放，如何设定event的cycle？难道需要每个cycle去探测吗？

**答案：绝对不需要！有3种高效的方法。**

---

##### 方法1：查询资源状态，直接获取释放时间 (推荐) ✓

**核心思想：** 资源状态中已经记录了 `busy_until`，直接读取即可！

```python
class Resource:
    """资源状态包含释放时间"""
    def __init__(self, name):
        self.name = name
        self.busy_until = 0        # ← 关键：记录资源忙到什么时候
        self.current_user = None
    
    def get_available_time(self):
        """
        直接返回资源何时可用
        不需要轮询，不需要等待！
        """
        return self.busy_until
    
    def is_available_at(self, time):
        """检查资源在某个时刻是否可用"""
        return time >= self.busy_until

# 使用示例：操作需要等待资源
def try_schedule_operation(op):
    """
    尝试调度操作
    """
    # 检查所有需要的资源
    resource_available_times = []
    for resource in op.required_resources:
        # 直接查询资源何时可用（O(1)操作！）
        avail_time = resource.get_available_time()
        resource_available_times.append(avail_time)
    
    # 计算最早可以开始的时间
    earliest_start = max(
        current_time,                           # 约束1: 不能早于当前时间
        max(resource_available_times),          # 约束2: 所有资源都可用
        op.dependency_satisfied_time            # 约束3: 依赖满足
    )
    
    if earliest_start > current_time:
        # 需要等待，创建延迟调度的event
        schedule_event = Event(
            time=earliest_start,  # ← 直接设置为资源可用的时间
            type=EventType.SCHEDULE_ATTEMPT,
            operation_id=op.id
        )
        event_queue.enqueue(schedule_event)
        
        print(f"[调度] 操作{op.id}需要等待到时间{earliest_start}")
        print(f"  当前时间: {current_time}")
        print(f"  资源可用时间: {resource_available_times}")
    else:
        # 资源立即可用，立即调度
        start_event = Event(
            time=current_time,
            type=EventType.OPERATION_START,
            operation_id=op.id
        )
        event_queue.enqueue(start_event)
        print(f"[调度] 操作{op.id}立即开始")
```

**完整示例：**

```python
# 场景：3个操作竞争同一个资源

# 初始状态
current_time = 0
processor = Resource("P0")

# 操作1：立即开始，占用0-100
op1 = Operation(id=1, duration=100)
processor.acquire(op1.id, start=0, duration=100)
print(f"操作1: 0-100, processor.busy_until = {processor.busy_until}")
# 输出: processor.busy_until = 100

# 操作2：在时间10尝试调度
current_time = 10
op2 = Operation(id=2, duration=50)

# 方法1: 直接查询资源可用时间
avail_time = processor.get_available_time()  # 返回 100
print(f"操作2尝试调度 @ 时间{current_time}")
print(f"  资源可用时间: {avail_time}")

# 创建延迟调度event
schedule_event = Event(
    time=avail_time,  # 100，不是10！
    type=EventType.SCHEDULE_ATTEMPT,
    operation_id=op2.id
)
event_queue.enqueue(schedule_event)
print(f"  创建调度event @ 时间{avail_time}")

# 时间跳跃：10 → 100 (直接跳过，不需要轮询！)

# 时间100：处理操作2的调度event
current_time = 100
# 此时资源已经释放，可以立即开始
processor.acquire(op2.id, start=100, duration=50)
print(f"操作2: 100-150, processor.busy_until = {processor.busy_until}")

# 操作3：在时间120尝试调度
current_time = 120
op3 = Operation(id=3, duration=30)

avail_time = processor.get_available_time()  # 返回 150
print(f"操作3尝试调度 @ 时间{current_time}")
print(f"  资源可用时间: {avail_time}")

schedule_event = Event(
    time=150,  # 直接设置为150
    type=EventType.SCHEDULE_ATTEMPT,
    operation_id=op3.id
)
event_queue.enqueue(schedule_event)

# 时间跳跃：120 → 150 (又直接跳过！)

# 总结：
# - 没有任何周期的轮询
# - 时间序列：0 → 10 → 100 → 120 → 150
# - 只处理了5个event，而不是150次循环
```

**关键观察：**

1. ✓  **O(1)查询**  ：`get_available_time()` 是常数时间操作
2. ✓  **无需轮询**  ：直接跳到资源可用的时间
3. ✓  **精确高效**  ：不会错过资源释放的时刻

---

##### 方法2：资源释放时主动通知 (Notify模式) ✓

**核心思想：** 资源释放时，主动通知所有等待的操作

```python
class Resource:
    """支持等待队列的资源"""
    def __init__(self, name):
        self.name = name
        self.busy_until = 0
        self.current_user = None
        self.waiting_queue = []  # ← 等待这个资源的操作队列
    
    def add_waiter(self, operation_id):
        """操作加入等待队列"""
        self.waiting_queue.append(operation_id)
        print(f"  [{self.name}] 操作{operation_id}加入等待队列")
    
    def release(self):
        """释放资源，主动通知等待者"""
        print(f"  [{self.name}] 释放，当前时间{current_time}")
        self.current_user = None
        self.busy_until = current_time
        
        # 关键：通知所有等待者！
        if len(self.waiting_queue) > 0:
            print(f"  [{self.name}] 通知{len(self.waiting_queue)}个等待者")
            
            for op_id in self.waiting_queue:
                # 创建调度尝试event
                schedule_event = Event(
                    time=current_time,  # 立即尝试调度
                    type=EventType.SCHEDULE_ATTEMPT,
                    operation_id=op_id
                )
                event_queue.enqueue(schedule_event)
                print(f"    → 通知操作{op_id}")
            
            # 清空等待队列
            self.waiting_queue.clear()

def try_schedule_operation(op):
    """尝试调度操作"""
    # 检查所有资源是否可用
    all_available = True
    for resource in op.required_resources:
        if not resource.is_available_at(current_time):
            all_available = False
            # 加入资源的等待队列
            resource.add_waiter(op.id)
    
    if all_available:
        # 立即调度
        start_event = Event(
            time=current_time,
            type=EventType.OPERATION_START,
            operation_id=op.id
        )
        event_queue.enqueue(start_event)
        print(f"[调度] 操作{op.id}立即开始")
    else:
        # 已加入等待队列，等待资源释放时的通知
        print(f"[调度] 操作{op.id}加入等待队列，等待通知")
        # 不创建任何event！等待资源释放时主动通知

def handle_operation_complete(event):
    """处理操作完成"""
    op = operations[event.operation_id]
    
    # 释放资源
    for resource in op.used_resources:
        resource.release()  # ← 这会自动通知等待者
```

**完整示例：**

```python
# 场景：多个操作等待同一个资源

# 时间0：操作1开始
current_time = 0
processor = Resource("P0")
op1 = Operation(id=1, duration=100)
processor.acquire(op1.id, 0, 100)
print(f"操作1开始 @ 时间0, 将在时间100完成")

# 时间10：操作2尝试调度，资源不可用
current_time = 10
op2 = Operation(id=2, duration=50)
print(f"\n操作2尝试调度 @ 时间10")
if not processor.is_available_at(current_time):
    processor.add_waiter(op2.id)
    print(f"  资源不可用，加入等待队列")
    # 注意：没有创建任何event！

# 时间30：操作3尝试调度，资源不可用
current_time = 30
op3 = Operation(id=3, duration=30)
print(f"\n操作3尝试调度 @ 时间30")
if not processor.is_available_at(current_time):
    processor.add_waiter(op3.id)
    print(f"  资源不可用，加入等待队列")
    # 注意：还是没有创建event！

# 此时等待队列：[op2, op3]

# 时间100：操作1完成，资源释放
current_time = 100
print(f"\n操作1完成 @ 时间100")
processor.release()
# 输出:
#   [P0] 释放，当前时间100
#   [P0] 通知2个等待者
#     → 通知操作2
#     → 通知操作3

# release()内部会创建2个SCHEDULE_ATTEMPT event @ 时间100
# 这2个event会立即被处理（同一时间）

# 操作2和3会竞争资源，先到先得（或按优先级）
```

**优势：**

1. ✓  **完全被动等待**  ：操作加入队列后无需任何event
2. ✓  **主动通知**  ：资源释放时立即通知，无延迟
3. ✓  **适合多等待者**  ：自动管理所有等待的操作

---

##### 方法3：混合方案 - 查询 + 通知 (最佳实践) ✓

**核心思想：** 结合方法1和方法2的优点

```python
class ResourceManager:
    """资源管理器：混合方案"""
    
    def try_schedule_operation(self, op):
        """
        尝试调度操作
        
        策略：
        1. 先查询资源可用时间（方法1）
        2. 如果需要等待，有两个选择：
           a) 如果知道确切时间 → 创建延迟event
           b) 如果资源被多个操作竞争 → 加入等待队列
        """
        # 检查依赖
        if not self.all_dependencies_satisfied(op):
            return  # 依赖未满足，等待notify
        
        # 检查资源，计算最早开始时间
        earliest_start = current_time
        blocking_resources = []
        
        for resource in op.required_resources:
            avail_time = resource.get_available_time()
            if avail_time > earliest_start:
                earliest_start = avail_time
                blocking_resources.append(resource)
        
        if earliest_start == current_time:
            # 情况1: 资源立即可用，立即调度
            self.schedule_operation_now(op)
            print(f"[调度] 操作{op.id}立即开始")
            
        elif len(blocking_resources) == 1:
            # 情况2: 只有一个资源阻塞，创建延迟event（方法1）
            schedule_event = Event(
                time=earliest_start,
                type=EventType.SCHEDULE_ATTEMPT,
                operation_id=op.id
            )
            event_queue.enqueue(schedule_event)
            print(f"[调度] 操作{op.id}延迟到时间{earliest_start}")
            
        else:
            # 情况3: 多个资源阻塞，使用等待队列（方法2）
            # 因为不同资源可能被不同操作释放，很难预测确切时间
            for resource in blocking_resources:
                resource.add_waiter(op.id)
            print(f"[调度] 操作{op.id}加入{len(blocking_resources)}个等待队列")
    
    def handle_resource_release(self, resource):
        """
        处理资源释放
        
        策略：同时通知等待队列中的操作
        """
        resource.release()
        
        # 通知所有等待者
        for op_id in resource.waiting_queue:
            # 创建立即调度尝试event
            schedule_event = Event(
                time=current_time,
                type=EventType.SCHEDULE_ATTEMPT,
                operation_id=op_id
            )
            event_queue.enqueue(schedule_event)
        
        resource.waiting_queue.clear()
```

**决策树：**

```
操作尝试调度
  ↓
检查依赖是否满足？
  ├─ 否 → 不做任何事，等待依赖完成时的notify
  └─ 是 → 继续
  ↓
检查资源可用性
  ↓
所有资源立即可用？
  ├─ 是 → 创建START event @ current_time
  └─ 否 → 继续
  ↓
只有一个资源阻塞？
  ├─ 是 → 创建SCHEDULE_ATTEMPT event @ resource.busy_until
  └─ 否 → 加入所有阻塞资源的等待队列
```

---

##### 对比：轮询 vs 事件驱动

**错误方案：周期轮询 ❌**

```python
# 这是错误的做法！
def bad_approach_polling():
    """
    错误：每个cycle都检查资源
    """
    for cycle in range(0, 1000):  # 1000次循环！
        current_time = cycle
        
        # 检查所有等待的操作
        for op in pending_operations:
            # 每个cycle都检查资源
            if all_resources_available(op):
                schedule_operation(op)
        
        # 处理当前cycle的event
        process_events_at(cycle)
    
    # 问题：
    # 1. 复杂度：O(cycles * operations * resources)
    # 2. 浪费：99%的检查都是无用功
    # 3. 慢：即使没有任何事情发生也要循环

# 假设：
# - 1000个周期
# - 100个等待操作
# - 每个操作需要3个资源
# 总检查次数：1000 * 100 * 3 = 300,000 次！
```

**正确方案：事件驱动 ✓**

```python
def correct_approach_event_driven():
    """
    正确：事件驱动，只在必要时检查
    """
    while not event_queue.empty():
        # 取出最早的event
        event = event_queue.get()
        
        # 跳到event发生的时间（时间跳跃！）
        current_time = event.time
        
        # 处理event
        if event.type == EventType.SCHEDULE_ATTEMPT:
            op = operations[event.operation_id]
            
            # 只检查这一个操作
            if all_resources_available(op):
                schedule_operation(op)
            else:
                # 方法1: 重新计算等待时间
                earliest = get_earliest_resource_available_time(op)
                reschedule_event = Event(
                    time=earliest,
                    type=EventType.SCHEDULE_ATTEMPT,
                    operation_id=op.id
                )
                event_queue.enqueue(reschedule_event)
                
                # 方法2: 加入等待队列
                # for resource in op.required_resources:
                #     if not resource.is_available():
                #         resource.add_waiter(op.id)
    
    # 优势：
    # 1. 只处理有意义的时间点
    # 2. 只检查可能就绪的操作
    # 3. 复杂度：O(events)，events << cycles * operations

# 假设：
# - 1000个周期，但只有50个event发生
# - 每个event只检查1个操作的资源
# 总检查次数：50 * 3 = 150 次
# 加速比：300,000 / 150 = 2000倍！
```

---

##### 实际案例：DLA GDMA调度器

```python
class GDMAScheduler:
    """真实案例：GDMA传输调度"""
    
    def try_schedule_transfer(self, transfer):
        """
        尝试调度传输
        """
        # 1. 计算所有资源的可用时间
        channel_avail = self.get_channel_available_time(transfer.channel_id)
        src_port_avail = self.get_port_available_time(transfer.src_port)
        dst_port_avail = self.get_port_available_time(transfer.dst_port)
        fifo_avail = self.get_fifo_available_time(transfer.fifo_id)
        ob_avail = self.get_ob_available_time(transfer.ob_entries)
        xfe_avail = self.get_xfe_available_time()
        
        # 2. 计算依赖约束
        dependency_satisfied = self.get_dependency_satisfied_time(transfer)
        
        # 3. 综合所有约束
        earliest_start = max(
            current_time,
            channel_avail,
            src_port_avail,
            dst_port_avail,
            fifo_avail,
            ob_avail,
            xfe_avail,
            dependency_satisfied
        )
        
        print(f"[GDMA] 传输{transfer.id}调度分析:")
        print(f"  当前时间: {current_time}")
        print(f"  Channel可用: {channel_avail}")
        print(f"  源端口可用: {src_port_avail}")
        print(f"  目的端口可用: {dst_port_avail}")
        print(f"  FIFO可用: {fifo_avail}")
        print(f"  OB可用: {ob_avail}")
        print(f"  XFE可用: {xfe_avail}")
        print(f"  依赖满足: {dependency_satisfied}")
        print(f"  → 最早开始时间: {earliest_start}")
        
        if earliest_start == current_time:
            # 立即调度
            self.schedule_transfer_now(transfer)
        else:
            # 创建延迟调度event
            schedule_event = Event(
                time=earliest_start,
                type=EventType.GDMA_SCHEDULE_ATTEMPT,
                transfer_id=transfer.id
            )
            event_queue.enqueue(schedule_event)
            print(f"  → 创建延迟调度event @ 时间{earliest_start}")
        
        # 关键：无需轮询，直接跳到earliest_start！
```

---

##### 总结：资源等待的最佳实践

**核心原则：永远不要轮询！**

```
┌─────────────────────────────────────────────────────────┐
│ 资源等待的3种方法                                        │
└─────────────────────────────────────────────────────────┘

方法1: 查询资源状态 ✓
  • 使用场景: 单资源阻塞，或资源释放时间确定
  • 实现: resource.get_available_time()
  • 复杂度: O(1)
  • 优点: 简单直接，精确高效
  • 缺点: 需要维护资源状态

方法2: 资源释放通知 ✓
  • 使用场景: 多资源竞争，或资源释放时间不确定
  • 实现: 等待队列 + release时notify
  • 复杂度: O(waiters)
  • 优点: 完全被动，无需预测
  • 缺点: 需要维护等待队列

方法3: 混合方案 ✓ (推荐)
  • 使用场景: 通用场景
  • 实现: 简单情况用方法1，复杂情况用方法2
  • 复杂度: 根据场景自适应
  • 优点: 灵活高效
  • 缺点: 实现稍复杂

永远不要用：周期轮询 ❌
  • 复杂度: O(cycles * operations)
  • 效率: 比事件驱动慢1000倍以上
  • 这不是event-driven，是cycle-accurate
```

**关键要点：**

1.  **资源状态是Oracle**  ：`busy_until` 告诉你未来，无需猜测
2.  **时间跳跃是核心**  ：直接跳到资源可用时间，不要逐周期推进
3.  **Notify是朋友**  ：资源释放时主动通知，无需轮询
4.  **Event是载体**  ：所有未来的动作都通过event表达

**代码模板：**

```python
# 查询资源可用时间（方法1）
avail_time = resource.get_available_time()  # O(1)
if avail_time > current_time:
    # 创建event，直接跳到avail_time
    event = Event(time=avail_time, type=SCHEDULE_ATTEMPT, op=op.id)
    event_queue.enqueue(event)

# 加入等待队列（方法2）
if not resource.is_available():
    resource.add_waiter(op.id)
    # 不创建event，等待release时的notify

# 资源释放时通知
def handle_resource_release(resource):
    for waiter_id in resource.waiting_queue:
        notify_event = Event(time=current_time, type=SCHEDULE_ATTEMPT, op=waiter_id)
        event_queue.enqueue(notify_event)
```

---

*第10.7节完成，详细解答了如何避免轮询等待资源释放*

---

*第10节完成，详细解答了Event创建时机、资源释放的Event粒度选择、时间推进机制、以及资源等待问题*

---

---

**下一篇** ： [第2部分E：Event与资源关系](./第2部分E_Event与资源关系.md)

*本文档行数: ~1,553行 (原2部分第10节完整内容)*
