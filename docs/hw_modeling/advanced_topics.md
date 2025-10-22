# 硬件性能建模完整指南 - 第3部分

## 第四部分：高级建模技术

### 11. 多通道并行执行建模 {#multi-channel}

#### 11.1 并行执行的挑战

**问题：** 多个通道同时执行时，如何建模它们之间的交互？

```
场景: 4通道DMA系统

时间轴:
      0         100       200       300       400
      |         |         |         |         |

理想情况 (无竞争):
Ch0:  |====传输0====|
Ch1:        |====传输1====|
Ch2:              |====传输2====|
Ch3:                    |====传输3====|
吞吐量: 4个传输同时进行

实际情况 (有竞争):
Ch0:  |====传输0====|
Ch1:        |===传输1===|← 等待端口
Ch2:                  |=传输2=|← 等待端口
Ch3:                      |=传输3=|← 等待端口
吞吐量: 串行化，效率降低
```

**关键问题：**

1. 如何表达通道之间的独立性？
2. 如何建模共享资源的竞争？
3. 如何处理通道间的依赖关系？
4. 如何评估并行效率？

---

#### 11.2 通道独立性建模

**核心思想：** 每个通道有独立的状态和event

```python
class Channel:
    """单个通道的状态"""
    def __init__(self, channel_id):
        self.id = channel_id
        self.state = ChannelState.IDLE
        self.current_transfer = None
        self.busy_until = 0
    
    def is_available(self, time):
        """通道是否可用"""
        return time >= self.busy_until
    
    def acquire(self, transfer, start_time, duration):
        """获取通道"""
        self.state = ChannelState.BUSY
        self.current_transfer = transfer
        self.busy_until = start_time + duration
        print(f"[Ch{self.id}] 开始传输{transfer.id} @ "
              f"时间{start_time}, 持续{duration}周期")
    
    def release(self):
        """释放通道"""
        print(f"[Ch{self.id}] 完成传输{self.current_transfer.id} @ "
              f"时间{self.busy_until}")
        self.state = ChannelState.IDLE
        self.current_transfer = None

class MultiChannelSystem:
    """多通道系统"""
    def __init__(self, num_channels):
        # 每个通道独立
        self.channels = [Channel(i) for i in range(num_channels)]
        self.event_queue = PriorityQueue()
    
    def try_schedule_transfer(self, transfer):
        """
        尝试调度传输到任意可用通道
        """
        # 1. 找到最早可用的通道
        earliest_channel = None
        earliest_time = float('inf')
        
        for channel in self.channels:
            if transfer.channel_id is not None:
                # 如果指定了通道，只能用这个通道
                if channel.id != transfer.channel_id:
                    continue
            
            avail_time = max(
                current_time,
                channel.busy_until
            )
            
            if avail_time < earliest_time:
                earliest_time = avail_time
                earliest_channel = channel
        
        if earliest_channel is None:
            print(f"[调度] 传输{transfer.id}无可用通道")
            return False
        
        # 2. 检查其他共享资源
        port_avail = self.get_port_available_time(transfer)
        fifo_avail = self.get_fifo_available_time(transfer)
        
        earliest_start = max(
            earliest_time,
            port_avail,
            fifo_avail,
            transfer.dependency_satisfied_time
        )
        
        print(f"[调度] 传输{transfer.id}:")
        print(f"  通道Ch{earliest_channel.id}可用: {earliest_time}")
        print(f"  端口可用: {port_avail}")
        print(f"  FIFO可用: {fifo_avail}")
        print(f"  → 最早开始: {earliest_start}")
        
        if earliest_start > current_time:
            # 创建延迟调度event
            schedule_event = Event(
                time=earliest_start,
                type=EventType.SCHEDULE_ATTEMPT,
                transfer_id=transfer.id
            )
            self.event_queue.enqueue(schedule_event)
        else:
            # 立即开始
            self.start_transfer(transfer, earliest_channel)
        
        return True
```

**关键点：**

1. ✓ **独立状态**：每个通道有自己的 `busy_until`
2. ✓ **独立event**：每个通道的START/COMPLETE event独立
3. ✓ **灵活调度**：可以选择任意可用通道

---

#### 11.3 共享资源竞争建模

**问题：** 多个通道竞争同一个端口

**示例：UB读端口共享**

```python
class SharedPortManager:
    """共享端口管理器"""
    
    def __init__(self, num_ports):
        self.ports = [PortState(i) for i in range(num_ports)]
        self.port_groups = {}  # 端口分组（用于共享）
    
    def setup_sharing_group(self, group_id, port_ids):
        """
        设置端口共享组
        
        例如: UB读端口0-3可以被Ch0-3共享
        """
        self.port_groups[group_id] = {
            'port_ids': port_ids,
            'ports': [self.ports[i] for i in port_ids],
            'current_users': {}  # port_id -> channel_id
        }
    
    def acquire_port(self, group_id, channel_id, transfer, start_time, duration):
        """
        从共享组中获取一个可用端口
        
        返回: (port_id, success)
        """
        group = self.port_groups[group_id]
        
        # 找到最早可用的端口
        best_port = None
        best_time = float('inf')
        
        for port in group['ports']:
            avail_time = port.get_available_time()
            if avail_time <= start_time and avail_time < best_time:
                best_port = port
                best_time = avail_time
        
        if best_port is None:
            # 所有端口都忙
            return None, False
        
        # 获取端口
        best_port.acquire(channel_id, start_time, duration)
        group['current_users'][best_port.id] = channel_id
        
        print(f"  [Port{best_port.id}] 被Ch{channel_id}获取")
        return best_port.id, True
    
    def release_port(self, group_id, port_id):
        """释放端口"""
        group = self.port_groups[group_id]
        port = self.ports[port_id]
        
        channel_id = group['current_users'].pop(port_id, None)
        port.release()
        
        print(f"  [Port{port_id}] 被Ch{channel_id}释放")

# 使用示例
port_mgr = SharedPortManager(num_ports=8)

# 设置共享组: UB读端口0-3
port_mgr.setup_sharing_group(
    group_id='UB_READ',
    port_ids=[0, 1, 2, 3]
)

# 设置共享组: MC写端口4-7
port_mgr.setup_sharing_group(
    group_id='MC_WRITE',
    port_ids=[4, 5, 6, 7]
)

# Ch0尝试获取UB读端口
port_id, success = port_mgr.acquire_port(
    group_id='UB_READ',
    channel_id=0,
    transfer=transfer0,
    start_time=100,
    duration=50
)
```

**竞争场景示例：**

```python
# 场景: 4个通道同时需要UB读端口（只有4个）

# 时间0: Ch0获取Port0
port_mgr.acquire_port('UB_READ', channel_id=0, ...)
# 输出: [Port0] 被Ch0获取

# 时间0: Ch1获取Port1
port_mgr.acquire_port('UB_READ', channel_id=1, ...)
# 输出: [Port1] 被Ch1获取

# 时间0: Ch2获取Port2
port_mgr.acquire_port('UB_READ', channel_id=2, ...)
# 输出: [Port2] 被Ch2获取

# 时间0: Ch3获取Port3
port_mgr.acquire_port('UB_READ', channel_id=3, ...)
# 输出: [Port3] 被Ch3获取

# 时间0: Ch0又想开始新传输（所有端口已占用！）
port_id, success = port_mgr.acquire_port('UB_READ', channel_id=0, ...)
# 返回: None, False
# → Ch0必须等待某个端口释放

# 时间100: Ch0的传输完成，释放Port0
port_mgr.release_port('UB_READ', port_id=0)
# 输出: [Port0] 被Ch0释放

# 现在Ch0可以开始新传输了
port_id, success = port_mgr.acquire_port('UB_READ', channel_id=0, ...)
# 返回: 0, True
```

---

#### 11.4 通道间依赖建模

**场景：** Pipeline模式，前一个通道的输出是后一个通道的输入

```
Pipeline示例:
Ch0: 读取数据从MC到UB
  ↓ 依赖
Ch1: 读取数据从UB到Compute
  ↓ 依赖
Ch2: 写回结果从Compute到UB
  ↓ 依赖
Ch3: 写回数据从UB到MC
```

**实现：**

```python
class ChannelDependencyManager:
    """通道间依赖管理"""
    
    def __init__(self):
        self.dependencies = defaultdict(set)  # transfer_id → 依赖的transfers
        self.dependents = defaultdict(set)    # transfer_id → 依赖它的transfers
        self.completed = set()
    
    def add_dependency(self, from_transfer_id, to_transfer_id):
        """
        添加依赖: to_transfer依赖from_transfer
        """
        self.dependencies[to_transfer_id].add(from_transfer_id)
        self.dependents[from_transfer_id].add(to_transfer_id)
        
        print(f"[依赖] 传输{to_transfer_id}依赖传输{from_transfer_id}")
    
    def mark_complete(self, transfer_id, complete_time):
        """
        标记传输完成，通知依赖它的后继
        """
        self.completed.add(transfer_id)
        
        # Notify所有依赖这个传输的后继
        dependents = self.dependents[transfer_id]
        if not dependents:
            return []
        
        ready_transfers = []
        for dep_transfer_id in dependents:
            # 检查这个后继的所有依赖是否都满足
            all_deps = self.dependencies[dep_transfer_id]
            if all_deps.issubset(self.completed):
                # 所有依赖都满足了
                ready_transfers.append(dep_transfer_id)
                print(f"[Notify] 传输{dep_transfer_id}就绪 @ "
                      f"时间{complete_time}")
        
        return ready_transfers

# 使用示例: Pipeline
dep_mgr = ChannelDependencyManager()

# 创建4个传输（pipeline）
transfer0 = Transfer(id=0, channel=0, desc="MC→UB")
transfer1 = Transfer(id=1, channel=1, desc="UB→Compute")
transfer2 = Transfer(id=2, channel=2, desc="Compute→UB")
transfer3 = Transfer(id=3, channel=3, desc="UB→MC")

# 建立依赖链
dep_mgr.add_dependency(from_transfer_id=0, to_transfer_id=1)  # 1依赖0
dep_mgr.add_dependency(from_transfer_id=1, to_transfer_id=2)  # 2依赖1
dep_mgr.add_dependency(from_transfer_id=2, to_transfer_id=3)  # 3依赖2

# 仿真执行
# 时间0: 传输0开始（无依赖）
schedule_transfer(transfer0)

# 时间100: 传输0完成
ready = dep_mgr.mark_complete(transfer_id=0, complete_time=100)
# 输出: [Notify] 传输1就绪 @ 时间100
# ready = [1]

# 调度就绪的传输
for transfer_id in ready:
    schedule_transfer(transfers[transfer_id])

# 时间150: 传输1完成
ready = dep_mgr.mark_complete(transfer_id=1, complete_time=150)
# 输出: [Notify] 传输2就绪 @ 时间150
# ready = [2]

# ... 以此类推
```

---

#### 11.5 并行效率评估

**关键指标：**

```python
class ParallelEfficiencyAnalyzer:
    """并行效率分析器"""
    
    def __init__(self, num_channels):
        self.num_channels = num_channels
        self.channel_busy_time = [0] * num_channels
        self.total_simulation_time = 0
        self.total_transfers = 0
    
    def record_transfer(self, channel_id, duration):
        """记录传输"""
        self.channel_busy_time[channel_id] += duration
        self.total_transfers += 1
    
    def finalize(self, total_time):
        """完成统计"""
        self.total_simulation_time = total_time
    
    def calculate_metrics(self):
        """计算并行效率指标"""
        metrics = {}
        
        # 1. 每个通道的利用率
        channel_utilization = []
        for i in range(self.num_channels):
            util = self.channel_busy_time[i] / self.total_simulation_time
            channel_utilization.append(util)
        
        metrics['channel_utilization'] = channel_utilization
        
        # 2. 平均利用率
        metrics['average_utilization'] = (
            sum(self.channel_busy_time) / 
            (self.num_channels * self.total_simulation_time)
        )
        
        # 3. 利用率方差（衡量负载均衡）
        avg_util = metrics['average_utilization']
        variance = sum((u - avg_util)**2 for u in channel_utilization) / self.num_channels
        metrics['utilization_variance'] = variance
        
        # 4. 并行效率 (实际吞吐量 / 理论吞吐量)
        # 理论吞吐量 = 如果没有竞争，所有通道独立运行
        theoretical_throughput = self.num_channels
        actual_throughput = sum(self.channel_busy_time) / self.total_simulation_time
        metrics['parallel_efficiency'] = actual_throughput / theoretical_throughput
        
        # 5. 串行化程度
        # 如果完全串行：并行效率 = 1/num_channels
        # 如果完全并行：并行效率 = 1
        serialization = 1.0 - metrics['parallel_efficiency']
        metrics['serialization_degree'] = serialization
        
        return metrics
    
    def print_report(self):
        """打印分析报告"""
        metrics = self.calculate_metrics()
        
        print(f"\n{'='*60}")
        print(f"并行效率分析报告")
        print(f"{'='*60}")
        
        print(f"\n总统计:")
        print(f"  通道数: {self.num_channels}")
        print(f"  总传输数: {self.total_transfers}")
        print(f"  仿真时间: {self.total_simulation_time}周期")
        
        print(f"\n各通道利用率:")
        for i, util in enumerate(metrics['channel_utilization']):
            bar_length = int(util * 50)
            bar = '█' * bar_length + '░' * (50 - bar_length)
            print(f"  Ch{i}: {util*100:5.1f}% {bar}")
        
        print(f"\n综合指标:")
        print(f"  平均利用率: {metrics['average_utilization']*100:.1f}%")
        print(f"  利用率方差: {metrics['utilization_variance']:.4f}")
        print(f"  并行效率: {metrics['parallel_efficiency']*100:.1f}%")
        print(f"  串行化程度: {metrics['serialization_degree']*100:.1f}%")
        
        # 诊断
        print(f"\n诊断:")
        if metrics['parallel_efficiency'] > 0.9:
            print(f"  ✓ 优秀：并行效率很高，通道利用充分")
        elif metrics['parallel_efficiency'] > 0.7:
            print(f"  ⚠ 良好：有一定串行化，可能存在资源竞争")
        elif metrics['parallel_efficiency'] > 0.5:
            print(f"  ⚠ 中等：明显的串行化，建议检查共享资源")
        else:
            print(f"  ✗ 较差：严重串行化，通道间竞争激烈")
        
        if metrics['utilization_variance'] > 0.1:
            print(f"  ⚠ 负载不均衡：某些通道过载，某些空闲")
        else:
            print(f"  ✓ 负载均衡良好")

# 使用示例
analyzer = ParallelEfficiencyAnalyzer(num_channels=4)

# 运行仿真，记录每个传输
for transfer in completed_transfers:
    analyzer.record_transfer(
        channel_id=transfer.channel_id,
        duration=transfer.duration
    )

# 完成后分析
analyzer.finalize(total_time=simulation_time)
analyzer.print_report()

# 输出示例:
# ============================================================
# 并行效率分析报告
# ============================================================
# 
# 总统计:
#   通道数: 4
#   总传输数: 100
#   仿真时间: 10000周期
# 
# 各通道利用率:
#   Ch0: 85.3% ████████████████████████████████████████████░░░░░░
#   Ch1: 82.1% █████████████████████████████████████████░░░░░░░░░
#   Ch2: 78.9% ███████████████████████████████████████░░░░░░░░░░░
#   Ch3: 80.5% ████████████████████████████████████████░░░░░░░░░░
# 
# 综合指标:
#   平均利用率: 81.7%
#   利用率方差: 0.0065
#   并行效率: 81.7%
#   串行化程度: 18.3%
# 
# 诊断:
#   ⚠ 良好：有一定串行化，可能存在资源竞争
#   ✓ 负载均衡良好
```

---

#### 11.6 完整的多通道仿真示例

```python
class MultiChannelDMASimulator:
    """完整的多通道DMA仿真器"""
    
    def __init__(self, config):
        self.num_channels = config['num_channels']
        self.channels = [Channel(i) for i in range(self.num_channels)]
        self.port_manager = SharedPortManager(config['num_ports'])
        self.dep_manager = ChannelDependencyManager()
        self.analyzer = ParallelEfficiencyAnalyzer(self.num_channels)
        
        self.event_queue = PriorityQueue()
        self.current_time = 0
        self.pending_transfers = []
        
        # 设置端口共享组
        self.setup_port_sharing(config)
    
    def setup_port_sharing(self, config):
        """设置端口共享配置"""
        for group in config['port_groups']:
            self.port_manager.setup_sharing_group(
                group_id=group['id'],
                port_ids=group['port_ids']
            )
    
    def add_transfer(self, transfer):
        """添加传输任务"""
        self.pending_transfers.append(transfer)
    
    def add_dependency(self, from_transfer_id, to_transfer_id):
        """添加传输依赖"""
        self.dep_manager.add_dependency(from_transfer_id, to_transfer_id)
    
    def run(self):
        """运行仿真"""
        print(f"\n{'='*60}")
        print(f"多通道DMA仿真开始")
        print(f"通道数: {self.num_channels}")
        print(f"{'='*60}\n")
        
        # 初始化：调度所有无依赖的传输
        for transfer in self.pending_transfers:
            if not self.dep_manager.dependencies[transfer.id]:
                self.try_schedule_transfer(transfer)
        
        # 主循环
        while not self.event_queue.empty():
            event = self.event_queue.get()
            self.current_time = event.time
            
            print(f"\n[时间{self.current_time}] 处理Event: {event.type}")
            
            if event.type == EventType.TRANSFER_START:
                self.handle_transfer_start(event)
            elif event.type == EventType.TRANSFER_COMPLETE:
                self.handle_transfer_complete(event)
            elif event.type == EventType.SCHEDULE_ATTEMPT:
                self.handle_schedule_attempt(event)
        
        # 完成统计
        self.analyzer.finalize(self.current_time)
        self.analyzer.print_report()
    
    def try_schedule_transfer(self, transfer):
        """尝试调度传输"""
        # 1. 选择通道
        channel = self.select_channel(transfer)
        if channel is None:
            print(f"  传输{transfer.id}: 通道不可用，加入等待")
            return False
        
        # 2. 检查端口
        port_id, port_ok = self.port_manager.acquire_port(
            group_id=transfer.port_group,
            channel_id=channel.id,
            transfer=transfer,
            start_time=self.current_time,
            duration=transfer.duration
        )
        if not port_ok:
            print(f"  传输{transfer.id}: 端口不可用，加入等待")
            return False
        
        # 3. 获取通道
        channel.acquire(transfer, self.current_time, transfer.duration)
        
        # 4. 创建START event
        start_event = Event(
            time=self.current_time,
            type=EventType.TRANSFER_START,
            transfer_id=transfer.id,
            channel_id=channel.id,
            port_id=port_id
        )
        self.event_queue.enqueue(start_event)
        
        print(f"  传输{transfer.id}: 调度到Ch{channel.id}, Port{port_id}")
        return True
    
    def handle_transfer_start(self, event):
        """处理传输开始"""
        transfer = self.get_transfer(event.transfer_id)
        channel = self.channels[event.channel_id]
        
        print(f"  Ch{channel.id}: 开始传输{transfer.id}")
        
        # 创建COMPLETE event
        complete_event = Event(
            time=self.current_time + transfer.duration,
            type=EventType.TRANSFER_COMPLETE,
            transfer_id=transfer.id,
            channel_id=event.channel_id,
            port_id=event.port_id
        )
        self.event_queue.enqueue(complete_event)
    
    def handle_transfer_complete(self, event):
        """处理传输完成"""
        transfer = self.get_transfer(event.transfer_id)
        channel = self.channels[event.channel_id]
        
        print(f"  Ch{channel.id}: 完成传输{transfer.id}")
        
        # 1. 释放资源
        channel.release()
        self.port_manager.release_port(
            group_id=transfer.port_group,
            port_id=event.port_id
        )
        
        # 2. 记录统计
        self.analyzer.record_transfer(channel.id, transfer.duration)
        
        # 3. Notify依赖
        ready_transfers = self.dep_manager.mark_complete(
            transfer_id=transfer.id,
            complete_time=self.current_time
        )
        
        # 4. 调度就绪的传输
        for transfer_id in ready_transfers:
            self.try_schedule_transfer(self.get_transfer(transfer_id))
    
    def select_channel(self, transfer):
        """选择可用通道"""
        if transfer.channel_id is not None:
            # 指定了通道
            channel = self.channels[transfer.channel_id]
            if channel.is_available(self.current_time):
                return channel
            return None
        
        # 选择最早可用的通道
        best_channel = None
        best_time = float('inf')
        for channel in self.channels:
            if channel.busy_until < best_time:
                best_time = channel.busy_until
                best_channel = channel
        
        if best_time <= self.current_time:
            return best_channel
        return None

# 使用示例
config = {
    'num_channels': 4,
    'num_ports': 8,
    'port_groups': [
        {'id': 'UB_READ', 'port_ids': [0, 1, 2, 3]},
        {'id': 'MC_WRITE', 'port_ids': [4, 5, 6, 7]}
    ]
}

simulator = MultiChannelDMASimulator(config)

# 添加传输（Pipeline模式）
for i in range(4):
    transfer = Transfer(
        id=i,
        channel_id=i,
        port_group='UB_READ',
        duration=100
    )
    simulator.add_transfer(transfer)
    
    # 建立pipeline依赖
    if i > 0:
        simulator.add_dependency(from_transfer_id=i-1, to_transfer_id=i)

# 运行仿真
simulator.run()
```

---

### 12. 调度策略与优化 {#scheduling}

#### 12.1 调度策略的影响

**问题：** 多个传输就绪时，选择哪个先执行？

```
场景: 3个传输同时就绪，但只有1个通道可用

传输A: 大数据量，低优先级
传输B: 小数据量，高优先级
传输C: 中等数据量，中优先级

不同策略的结果:
1. FIFO (先来先服务) → A先执行
2. 优先级 (Priority) → B先执行
3. 最短作业优先 (SJF) → B先执行
4. 公平调度 (Fair) → 轮流执行
```

**调度策略实现：**

```python
class Scheduler:
    """调度器基类"""
    
    def select_next_transfer(self, ready_transfers, resources):
        """
        从就绪队列中选择下一个要执行的传输
        
        参数:
            ready_transfers: 就绪的传输列表
            resources: 当前资源状态
        
        返回:
            选中的传输，或None
        """
        raise NotImplementedError

class FIFOScheduler(Scheduler):
    """先来先服务调度器"""
    
    def select_next_transfer(self, ready_transfers, resources):
        if not ready_transfers:
            return None
        # 返回最早加入队列的
        return ready_transfers[0]

class PriorityScheduler(Scheduler):
    """优先级调度器"""
    
    def select_next_transfer(self, ready_transfers, resources):
        if not ready_transfers:
            return None
        # 返回优先级最高的
        return max(ready_transfers, key=lambda t: t.priority)

class ShortestJobFirstScheduler(Scheduler):
    """最短作业优先调度器"""
    
    def select_next_transfer(self, ready_transfers, resources):
        if not ready_transfers:
            return None
        # 返回预计时间最短的
        return min(ready_transfers, key=lambda t: self.estimate_duration(t))
    
    def estimate_duration(self, transfer):
        """估算传输时间"""
        return transfer.data_size / transfer.estimated_bandwidth

class ResourceAwareScheduler(Scheduler):
    """资源感知调度器"""
    
    def select_next_transfer(self, ready_transfers, resources):
        """
        选择最适合当前资源状态的传输
        """
        if not ready_transfers:
            return None
        
        # 评分：综合考虑资源可用性、传输大小、优先级
        scores = []
        for transfer in ready_transfers:
            score = self.calculate_score(transfer, resources)
            scores.append((score, transfer))
        
        # 返回得分最高的
        return max(scores, key=lambda x: x[0])[1]
    
    def calculate_score(self, transfer, resources):
        """
        计算传输的调度得分
        
        考虑因素:
        1. 资源冲突程度（越低越好）
        2. 预计等待时间（越短越好）
        3. 传输优先级（越高越好）
        4. 传输大小（SJF倾向，越小越好）
        """
        # 因素1: 资源可用性
        resource_delay = 0
        for resource_type in transfer.required_resources:
            avail_time = resources.get_available_time(resource_type)
            resource_delay += max(0, avail_time - resources.current_time)
        
        # 因素2: 优先级
        priority_weight = transfer.priority * 1000
        
        # 因素3: 传输大小（倒数，小的得分高）
        size_weight = 1.0 / (transfer.duration + 1)
        
        # 综合得分
        score = (
            priority_weight +
            size_weight * 100 -
            resource_delay * 0.1
        )
        
        return score
```

**调度策略对比：**

```python
def compare_scheduling_strategies():
    """对比不同调度策略的效果"""
    
    # 相同的workload
    workload = generate_workload(num_transfers=100)
    
    strategies = [
        ('FIFO', FIFOScheduler()),
        ('Priority', PriorityScheduler()),
        ('SJF', ShortestJobFirstScheduler()),
        ('ResourceAware', ResourceAwareScheduler())
    ]
    
    results = []
    
    for name, scheduler in strategies:
        simulator = MultiChannelDMASimulator(config)
        simulator.set_scheduler(scheduler)
        
        # 运行仿真
        metrics = simulator.run(workload)
        
        results.append({
            'strategy': name,
            'total_time': metrics['total_time'],
            'average_latency': metrics['average_latency'],
            'throughput': metrics['throughput'],
            'utilization': metrics['utilization']
        })
    
    # 打印对比
    print(f"\n{'='*70}")
    print(f"调度策略对比")
    print(f"{'='*70}")
    print(f"{'策略':<15} {'总时间':<10} {'平均延迟':<12} {'吞吐量':<12} {'利用率':<10}")
    print(f"{'-'*70}")
    
    for result in results:
        print(f"{result['strategy']:<15} "
              f"{result['total_time']:<10} "
              f"{result['average_latency']:<12.1f} "
              f"{result['throughput']:<12.2f} "
              f"{result['utilization']:<10.1%}")
    
    # 输出示例:
    # ======================================================================
    # 调度策略对比
    # ======================================================================
    # 策略            总时间     平均延迟      吞吐量        利用率    
    # ----------------------------------------------------------------------
    # FIFO            12500      125.0        8.00         80.0%     
    # Priority        11800      98.3         8.47         84.7%     
    # SJF             11200      89.5         8.93         89.3%     
    # ResourceAware   10900      85.2         9.17         91.7%     
```

---

#### 12.2 死锁检测与避免

**问题：** 循环依赖导致所有传输都在等待

```
死锁场景:
传输A: 需要资源R1, R2
  持有R1, 等待R2
  
传输B: 需要资源R2, R3
  持有R2, 等待R3
  
传输C: 需要资源R3, R1
  持有R3, 等待R1
  
结果: A→B→C→A 循环等待，死锁！
```

**死锁检测：**

```python
class DeadlockDetector:
    """死锁检测器"""
    
    def __init__(self):
        self.resource_graph = defaultdict(set)  # resource → holders
        self.wait_graph = defaultdict(set)      # transfer → waiting_for_resources
    
    def check_deadlock(self):
        """
        检测是否存在死锁
        
        方法: 检测资源等待图中是否有环
        """
        # 构建等待图: transfer → waiting_for_transfers
        wait_for_transfer = defaultdict(set)
        
        for transfer_id, resources in self.wait_graph.items():
            for resource in resources:
                # 找到持有这个资源的transfer
                holders = self.resource_graph[resource]
                wait_for_transfer[transfer_id].update(holders)
        
        # 检测环
        visited = set()
        rec_stack = set()
        
        def has_cycle(transfer_id):
            visited.add(transfer_id)
            rec_stack.add(transfer_id)
            
            for next_transfer in wait_for_transfer[transfer_id]:
                if next_transfer not in visited:
                    if has_cycle(next_transfer):
                        return True
                elif next_transfer in rec_stack:
                    return True  # 找到环！
            
            rec_stack.remove(transfer_id)
            return False
        
        # 检查所有传输
        for transfer_id in wait_for_transfer:
            if transfer_id not in visited:
                if has_cycle(transfer_id):
                    return True
        
        return False
    
    def get_deadlock_cycle(self):
        """获取死锁环"""
        # 如果检测到死锁，找出具体的环
        # (实现省略，类似DFS找环)
        pass

# 使用示例
detector = DeadlockDetector()

# 记录资源持有
detector.resource_graph['R1'].add('TransferA')
detector.resource_graph['R2'].add('TransferB')
detector.resource_graph['R3'].add('TransferC')

# 记录等待
detector.wait_graph['TransferA'].add('R2')
detector.wait_graph['TransferB'].add('R3')
detector.wait_graph['TransferC'].add('R1')

# 检测死锁
if detector.check_deadlock():
    print("⚠️ 检测到死锁!")
    cycle = detector.get_deadlock_cycle()
    print(f"死锁环: {' → '.join(cycle)}")
```

**死锁避免策略：**

```python
class ResourceOrderingPolicy:
    """资源顺序策略（避免死锁）"""
    
    def __init__(self):
        # 为所有资源分配全局顺序
        self.resource_order = {
            'Channel0': 0,
            'Channel1': 1,
            'Port0': 10,
            'Port1': 11,
            'FIFO0': 20,
            'FIFO1': 21,
            'OB': 30
        }
    
    def acquire_resources(self, transfer):
        """
        按顺序获取资源
        
        关键: 所有传输都按相同顺序获取资源 → 避免循环等待
        """
        # 1. 对需要的资源排序
        required = transfer.required_resources
        sorted_resources = sorted(
            required,
            key=lambda r: self.resource_order[r.name]
        )
        
        # 2. 按顺序尝试获取
        acquired = []
        for resource in sorted_resources:
            if resource.is_available(current_time):
                resource.acquire(transfer.id)
                acquired.append(resource)
            else:
                # 无法获取，释放已获取的资源
                for r in acquired:
                    r.release()
                return False
        
        # 3. 成功获取所有资源
        return True

# 原理:
# - 所有transfer都按 Channel → Port → FIFO → OB 的顺序获取
# - 不可能出现 A持有Port等Channel, B持有Channel等Port 的情况
# - 因此不会有循环等待，避免死锁
```

---

### 13. 性能分析与优化 {#performance-analysis}

#### 13.1 性能瓶颈识别

**系统化方法：**

```python
class PerformanceProfiler:
    """性能剖析器"""
    
    def __init__(self):
        self.resource_busy_time = defaultdict(int)
        self.resource_wait_time = defaultdict(int)
        self.transfer_wait_time = {}
        self.contention_events = []
    
    def record_resource_usage(self, resource_name, duration):
        """记录资源使用时间"""
        self.resource_busy_time[resource_name] += duration
    
    def record_wait_event(self, transfer_id, resource_name, wait_duration):
        """记录等待事件"""
        self.resource_wait_time[resource_name] += wait_duration
        if transfer_id not in self.transfer_wait_time:
            self.transfer_wait_time[transfer_id] = 0
        self.transfer_wait_time[transfer_id] += wait_duration
        
        # 记录竞争事件
        self.contention_events.append({
            'time': current_time,
            'transfer': transfer_id,
            'resource': resource_name,
            'wait_duration': wait_duration
        })
    
    def analyze(self, total_time):
        """分析性能瓶颈"""
        print(f"\n{'='*60}")
        print(f"性能瓶颈分析")
        print(f"{'='*60}\n")
        
        # 1. 资源利用率分析
        print("1. 资源利用率:")
        sorted_resources = sorted(
            self.resource_busy_time.items(),
            key=lambda x: x[1],
            reverse=True
        )
        
        for resource, busy_time in sorted_resources:
            utilization = busy_time / total_time
            wait_time = self.resource_wait_time.get(resource, 0)
            
            bar_length = int(utilization * 40)
            bar = '█' * bar_length + '░' * (40 - bar_length)
            
            print(f"  {resource:<20} {utilization*100:5.1f}% {bar}")
            if wait_time > 0:
                print(f"    ↳ 累计等待时间: {wait_time}周期")
        
        # 2. 识别瓶颈资源
        print(f"\n2. 瓶颈资源识别:")
        bottlenecks = []
        for resource, busy_time in self.resource_busy_time.items():
            utilization = busy_time / total_time
            wait_time = self.resource_wait_time.get(resource, 0)
            
            if utilization > 0.9:
                bottlenecks.append((resource, utilization, wait_time))
        
        if bottlenecks:
            for resource, util, wait in sorted(bottlenecks, key=lambda x: x[1], reverse=True):
                print(f"  ⚠️ {resource}: 利用率{util*100:.1f}%, "
                      f"累计等待{wait}周期")
                print(f"     建议: 增加{resource}数量或带宽")
        else:
            print(f"  ✓ 无严重瓶颈资源")
        
        # 3. 传输等待时间分析
        print(f"\n3. 传输等待时间分析:")
        if self.transfer_wait_time:
            sorted_transfers = sorted(
                self.transfer_wait_time.items(),
                key=lambda x: x[1],
                reverse=True
            )[:10]  # Top 10
            
            for transfer_id, wait_time in sorted_transfers:
                print(f"  传输{transfer_id}: 等待{wait_time}周期")
        else:
            print(f"  ✓ 所有传输无需等待")
        
        # 4. 竞争热点分析
        print(f"\n4. 资源竞争热点:")
        contention_by_resource = defaultdict(int)
        for event in self.contention_events:
            contention_by_resource[event['resource']] += 1
        
        sorted_contention = sorted(
            contention_by_resource.items(),
            key=lambda x: x[1],
            reverse=True
        )
        
        for resource, count in sorted_contention[:5]:
            print(f"  {resource}: {count}次竞争")
        
        # 5. 时间线分析（找出竞争高峰期）
        print(f"\n5. 竞争时间线分析:")
        self.analyze_contention_timeline(total_time)
    
    def analyze_contention_timeline(self, total_time):
        """分析竞争在时间上的分布"""
        # 将时间分成10个区间
        num_bins = 10
        bin_size = total_time / num_bins
        contention_bins = [0] * num_bins
        
        for event in self.contention_events:
            bin_idx = min(int(event['time'] / bin_size), num_bins - 1)
            contention_bins[bin_idx] += 1
        
        max_contention = max(contention_bins) if contention_bins else 1
        
        for i, count in enumerate(contention_bins):
            start = int(i * bin_size)
            end = int((i + 1) * bin_size)
            bar_length = int(count / max_contention * 40) if max_contention > 0 else 0
            bar = '█' * bar_length
            
            print(f"  [{start:6d}-{end:6d}]: {count:3d}次 {bar}")

# 使用示例
profiler = PerformanceProfiler()

# 在仿真过程中记录
def handle_transfer_start(event):
    # ... 传输开始逻辑
    
    # 记录资源使用
    profiler.record_resource_usage(
        resource_name=f"Channel{event.channel_id}",
        duration=transfer.duration
    )

def handle_resource_wait(transfer_id, resource_name, wait_duration):
    # 记录等待
    profiler.record_wait_event(transfer_id, resource_name, wait_duration)

# 仿真结束后分析
profiler.analyze(total_time=simulation_time)
```

---

#### 13.2 优化建议生成

```python
class PerformanceOptimizer:
    """性能优化建议生成器"""
    
    def __init__(self, profiler, config):
        self.profiler = profiler
        self.config = config
    
    def generate_recommendations(self, total_time):
        """生成优化建议"""
        recommendations = []
        
        # 1. 资源扩展建议
        for resource, busy_time in self.profiler.resource_busy_time.items():
            utilization = busy_time / total_time
            
            if utilization > 0.95:
                # 严重瓶颈
                current_count = self.get_resource_count(resource)
                recommended_count = int(current_count * utilization / 0.8)
                
                recommendations.append({
                    'priority': 'HIGH',
                    'type': 'RESOURCE_EXPANSION',
                    'resource': resource,
                    'current': current_count,
                    'recommended': recommended_count,
                    'reason': f'利用率{utilization*100:.1f}%，严重瓶颈',
                    'expected_improvement': f'吞吐量提升{(recommended_count/current_count - 1)*100:.1f}%'
                })
            
            elif utilization > 0.85:
                # 轻微瓶颈
                recommendations.append({
                    'priority': 'MEDIUM',
                    'type': 'RESOURCE_EXPANSION',
                    'resource': resource,
                    'reason': f'利用率{utilization*100:.1f}%，接近饱和',
                    'suggestion': '考虑增加资源或优化调度'
                })
        
        # 2. 调度策略建议
        avg_wait_time = (
            sum(self.profiler.transfer_wait_time.values()) /
            len(self.profiler.transfer_wait_time)
            if self.profiler.transfer_wait_time else 0
        )
        
        if avg_wait_time > total_time * 0.1:
            recommendations.append({
                'priority': 'MEDIUM',
                'type': 'SCHEDULING',
                'reason': f'平均等待时间{avg_wait_time:.0f}周期，占比{avg_wait_time/total_time*100:.1f}%',
                'suggestion': '尝试使用ResourceAware调度策略'
            })
        
        # 3. 竞争模式分析
        contention_count = len(self.profiler.contention_events)
        if contention_count > len(self.profiler.transfer_wait_time) * 2:
            recommendations.append({
                'priority': 'HIGH',
                'type': 'CONTENTION_REDUCTION',
                'reason': f'检测到{contention_count}次资源竞争',
                'suggestions': [
                    '增加共享资源数量',
                    '优化传输分配策略',
                    '考虑时间复用机制'
                ]
            })
        
        # 4. 负载均衡建议
        channel_utils = self.get_channel_utilizations(total_time)
        util_variance = self.calculate_variance(channel_utils)
        
        if util_variance > 0.05:
            recommendations.append({
                'priority': 'MEDIUM',
                'type': 'LOAD_BALANCING',
                'reason': f'通道利用率方差{util_variance:.3f}，负载不均',
                'suggestion': '优化传输到通道的分配算法'
            })
        
        return recommendations
    
    def print_recommendations(self, total_time):
        """打印优化建议"""
        recommendations = self.generate_recommendations(total_time)
        
        print(f"\n{'='*60}")
        print(f"性能优化建议")
        print(f"{'='*60}\n")
        
        if not recommendations:
            print("✓ 系统性能良好，无需优化")
            return
        
        # 按优先级分组
        high_priority = [r for r in recommendations if r.get('priority') == 'HIGH']
        medium_priority = [r for r in recommendations if r.get('priority') == 'MEDIUM']
        low_priority = [r for r in recommendations if r.get('priority') == 'LOW']
        
        if high_priority:
            print("🔴 高优先级建议:")
            for i, rec in enumerate(high_priority, 1):
                self.print_recommendation(i, rec)
        
        if medium_priority:
            print("\n🟡 中优先级建议:")
            for i, rec in enumerate(medium_priority, 1):
                self.print_recommendation(i, rec)
        
        if low_priority:
            print("\n🟢 低优先级建议:")
            for i, rec in enumerate(low_priority, 1):
                self.print_recommendation(i, rec)
    
    def print_recommendation(self, index, rec):
        """打印单条建议"""
        print(f"\n  {index}. {rec['type']}")
        print(f"     原因: {rec['reason']}")
        
        if 'suggestion' in rec:
            print(f"     建议: {rec['suggestion']}")
        
        if 'suggestions' in rec:
            print(f"     建议:")
            for s in rec['suggestions']:
                print(f"       - {s}")
        
        if 'current' in rec and 'recommended' in rec:
            print(f"     当前配置: {rec['current']}")
            print(f"     推荐配置: {rec['recommended']}")
        
        if 'expected_improvement' in rec:
            print(f"     预期改进: {rec['expected_improvement']}")

# 使用示例
optimizer = PerformanceOptimizer(profiler, config)
optimizer.print_recommendations(total_time=simulation_time)

# 输出示例:
# ============================================================
# 性能优化建议
# ============================================================
# 
# 🔴 高优先级建议:
# 
#   1. RESOURCE_EXPANSION
#      原因: 利用率96.5%，严重瓶颈
#      当前配置: 4
#      推荐配置: 5
#      预期改进: 吞吐量提升25.0%
# 
#   2. CONTENTION_REDUCTION
#      原因: 检测到245次资源竞争
#      建议:
#        - 增加共享资源数量
#        - 优化传输分配策略
#        - 考虑时间复用机制
# 
# 🟡 中优先级建议:
# 
#   1. SCHEDULING
#      原因: 平均等待时间150周期，占比12.5%
#      建议: 尝试使用ResourceAware调度策略
# 
#   2. LOAD_BALANCING
#      原因: 通道利用率方差0.082，负载不均
#      建议: 优化传输到通道的分配算法
```

---

#### 13.3 What-If分析

```python
class WhatIfAnalyzer:
    """假设分析工具"""
    
    def __init__(self, base_config, base_workload):
        self.base_config = base_config
        self.base_workload = base_workload
        self.base_results = None
    
    def run_baseline(self):
        """运行基线配置"""
        print("运行基线配置...")
        simulator = MultiChannelDMASimulator(self.base_config)
        self.base_results = simulator.run(self.base_workload)
        return self.base_results
    
    def test_scenario(self, scenario_name, config_modifier):
        """
        测试假设场景
        
        参数:
            scenario_name: 场景名称
            config_modifier: 配置修改函数
        """
        print(f"\n测试场景: {scenario_name}")
        
        # 修改配置
        modified_config = config_modifier(self.base_config.copy())
        
        # 运行仿真
        simulator = MultiChannelDMASimulator(modified_config)
        results = simulator.run(self.base_workload)
        
        # 对比结果
        self.compare_results(scenario_name, self.base_results, results)
        
        return results
    
    def compare_results(self, scenario_name, baseline, modified):
        """对比结果"""
        print(f"\n  对比基线:")
        
        metrics = ['total_time', 'throughput', 'average_latency', 'utilization']
        
        for metric in metrics:
            base_val = baseline[metric]
            mod_val = modified[metric]
            
            if metric in ['total_time', 'average_latency']:
                # 越小越好
                improvement = (base_val - mod_val) / base_val * 100
                symbol = '▼' if improvement > 0 else '▲'
            else:
                # 越大越好
                improvement = (mod_val - base_val) / base_val * 100
                symbol = '▲' if improvement > 0 else '▼'
            
            print(f"    {metric:<20}: {base_val:>8.2f} → {mod_val:>8.2f} "
                  f"({symbol}{abs(improvement):>5.1f}%)")
    
    def run_what_if_study(self):
        """运行完整的What-If研究"""
        print(f"\n{'='*60}")
        print(f"What-If分析")
        print(f"{'='*60}\n")
        
        # 运行基线
        baseline = self.run_baseline()
        
        # 场景1: 增加通道数
        def add_channels(config):
            config['num_channels'] += 2
            return config
        
        self.test_scenario("增加2个通道", add_channels)
        
        # 场景2: 增加端口数
        def add_ports(config):
            config['num_ports'] += 4
            for group in config['port_groups']:
                if group['id'] == 'UB_READ':
                    group['port_ids'].extend([8, 9, 10, 11])
            return config
        
        self.test_scenario("增加4个UB读端口", add_ports)
        
        # 场景3: 增加带宽
        def increase_bandwidth(config):
            config['port_bandwidth'] *= 1.5
            return config
        
        self.test_scenario("端口带宽提升50%", increase_bandwidth)
        
        # 场景4: 更改调度策略
        def change_scheduler(config):
            config['scheduler'] = 'ResourceAware'
            return config
        
        self.test_scenario("使用ResourceAware调度", change_scheduler)
        
        # 场景5: 组合优化
        def combined_optimization(config):
            config['num_channels'] += 1
            config['num_ports'] += 2
            config['scheduler'] = 'ResourceAware'
            return config
        
        self.test_scenario("组合优化（通道+端口+调度）", combined_optimization)

# 使用示例
analyzer = WhatIfAnalyzer(base_config, workload)
analyzer.run_what_if_study()

# 输出示例:
# ============================================================
# What-If分析
# ============================================================
# 
# 运行基线配置...
# 基线结果: 总时间=12500, 吞吐量=8.0, 平均延迟=125, 利用率=80%
# 
# 测试场景: 增加2个通道
# 
#   对比基线:
#     total_time          : 12500.00 → 10200.00 (▼ 18.4%)
#     throughput          :     8.00 →    9.80 (▲ 22.5%)
#     average_latency     :   125.00 →   102.00 (▼ 18.4%)
#     utilization         :     0.80 →     0.82 (▲  2.5%)
# 
# 测试场景: 增加4个UB读端口
# 
#   对比基线:
#     total_time          : 12500.00 → 11800.00 (▼  5.6%)
#     throughput          :     8.00 →    8.47 (▲  5.9%)
#     average_latency     :   125.00 →   118.00 (▼  5.6%)
#     utilization         :     0.80 →     0.85 (▲  6.3%)
# 
# ... (其他场景)
```

---

### 14. 调试技巧与验证 {#debugging}

#### 14.1 Event追踪

```python
class EventTracer:
    """Event追踪工具"""
    
    def __init__(self, enabled=True):
        self.enabled = enabled
        self.events = []
        self.verbose_mode = False
    
    def trace_event(self, event, action):
        """
        追踪event
        
        参数:
            event: Event对象
            action: 'CREATE', 'ENQUEUE', 'DEQUEUE', 'PROCESS'
        """
        if not self.enabled:
            return
        
        trace_entry = {
            'action': action,
            'time': event.time,
            'event_type': event.type,
            'event_id': id(event),
            'details': self.extract_details(event),
            'timestamp': current_time  # 实际时间
        }
        
        self.events.append(trace_entry)
        
        if self.verbose_mode:
            self.print_trace(trace_entry)
    
    def extract_details(self, event):
        """提取event详细信息"""
        details = {}
        for attr in ['transfer_id', 'channel_id', 'resource_id', 'operation_id']:
            if hasattr(event, attr):
                details[attr] = getattr(event, attr)
        return details
    
    def print_trace(self, entry):
        """打印追踪信息"""
        print(f"[{entry['timestamp']:6d}] {entry['action']:<8} "
              f"Event@{entry['time']:6d} {entry['event_type']:<15} "
              f"{entry['details']}")
    
    def analyze_event_flow(self, event_id):
        """分析特定event的完整流程"""
        flow = [e for e in self.events if e['event_id'] == event_id]
        
        print(f"\nEvent流程分析 (ID: {event_id}):")
        for entry in flow:
            print(f"  [{entry['timestamp']:6d}] {entry['action']:<8} @ "
                  f"时间{entry['time']}")
    
    def find_anomalies(self):
        """查找异常"""
        anomalies = []
        
        # 检查1: Event时间倒退
        last_time = -1
        for entry in self.events:
            if entry['action'] == 'DEQUEUE':
                if entry['time'] < last_time:
                    anomalies.append({
                        'type': 'TIME_REGRESSION',
                        'message': f"时间倒退: {last_time} → {entry['time']}"
                    })
                last_time = entry['time']
        
        # 检查2: Event未被处理
        created = {e['event_id'] for e in self.events if e['action'] == 'CREATE'}
        processed = {e['event_id'] for e in self.events if e['action'] == 'PROCESS'}
        unprocessed = created - processed
        
        if unprocessed:
            anomalies.append({
                'type': 'UNPROCESSED_EVENTS',
                'count': len(unprocessed),
                'message': f"{len(unprocessed)}个event未被处理"
            })
        
        # 检查3: 重复处理
        from collections import Counter
        process_counts = Counter(
            e['event_id'] for e in self.events if e['action'] == 'PROCESS'
        )
        duplicates = {eid: count for eid, count in process_counts.items() if count > 1}
        
        if duplicates:
            anomalies.append({
                'type': 'DUPLICATE_PROCESSING',
                'count': len(duplicates),
                'message': f"{len(duplicates)}个event被重复处理"
            })
        
        return anomalies

# 使用示例
tracer = EventTracer(enabled=True)

# 在仿真过程中追踪
def create_event(event):
    tracer.trace_event(event, 'CREATE')
    event_queue.enqueue(event)
    tracer.trace_event(event, 'ENQUEUE')

def process_event():
    event = event_queue.dequeue()
    tracer.trace_event(event, 'DEQUEUE')
    
    # 处理event
    handle_event(event)
    
    tracer.trace_event(event, 'PROCESS')

# 仿真结束后检查
anomalies = tracer.find_anomalies()
if anomalies:
    print("\n⚠️ 发现异常:")
    for anomaly in anomalies:
        print(f"  - {anomaly['type']}: {anomaly['message']}")
else:
    print("\n✓ Event流程正常")
```

---

#### 14.2 状态快照与回放

```python
class StateSnapshot:
    """状态快照"""
    
    def __init__(self, time):
        self.time = time
        self.resources = {}
        self.operations = {}
        self.statistics = {}
    
    def capture(self, simulator):
        """捕获当前状态"""
        self.time = simulator.current_time
        
        # 捕获资源状态
        for resource_name, resource in simulator.resources.items():
            self.resources[resource_name] = {
                'busy_until': resource.busy_until,
                'current_user': resource.current_user
            }
        
        # 捕获操作状态
        for op_id, op in simulator.operations.items():
            self.operations[op_id] = {
                'state': op.state,
                'start_time': op.start_time,
                'end_time': op.end_time
            }
        
        # 捕获统计
        self.statistics = simulator.get_statistics().copy()
    
    def compare(self, other):
        """对比两个快照"""
        print(f"\n快照对比: 时间{self.time} vs 时间{other.time}")
        
        # 对比资源变化
        print(f"\n资源变化:")
        all_resources = set(self.resources.keys()) | set(other.resources.keys())
        for resource_name in sorted(all_resources):
            old = self.resources.get(resource_name, {})
            new = other.resources.get(resource_name, {})
            
            if old != new:
                print(f"  {resource_name}:")
                if old.get('busy_until') != new.get('busy_until'):
                    print(f"    busy_until: {old.get('busy_until')} → "
                          f"{new.get('busy_until')}")
                if old.get('current_user') != new.get('current_user'):
                    print(f"    current_user: {old.get('current_user')} → "
                          f"{new.get('current_user')}")

class SnapshotManager:
    """快照管理器"""
    
    def __init__(self):
        self.snapshots = []
        self.auto_snapshot_interval = 100
    
    def take_snapshot(self, simulator, label=None):
        """拍摄快照"""
        snapshot = StateSnapshot(simulator.current_time)
        snapshot.capture(simulator)
        snapshot.label = label
        
        self.snapshots.append(snapshot)
        print(f"[快照] 时间{simulator.current_time} ({label or 'auto'})")
    
    def auto_snapshot(self, simulator):
        """自动快照"""
        if len(self.snapshots) == 0:
            self.take_snapshot(simulator, 'initial')
            return
        
        last_snapshot = self.snapshots[-1]
        if simulator.current_time - last_snapshot.time >= self.auto_snapshot_interval:
            self.take_snapshot(simulator, 'auto')
    
    def get_snapshot(self, time=None, label=None):
        """获取快照"""
        if label:
            for snapshot in self.snapshots:
                if snapshot.label == label:
                    return snapshot
        
        if time is not None:
            # 找到最接近的快照
            closest = min(self.snapshots, key=lambda s: abs(s.time - time))
            return closest
        
        return None
    
    def replay_to_snapshot(self, simulator, target_snapshot):
        """回放到某个快照"""
        print(f"\n回放到时间{target_snapshot.time}...")
        
        # 恢复状态
        for resource_name, state in target_snapshot.resources.items():
            resource = simulator.resources[resource_name]
            resource.busy_until = state['busy_until']
            resource.current_user = state['current_user']
        
        for op_id, state in target_snapshot.operations.items():
            op = simulator.operations[op_id]
            op.state = state['state']
            op.start_time = state['start_time']
            op.end_time = state['end_time']
        
        simulator.current_time = target_snapshot.time
        print(f"✓ 状态已恢复到时间{target_snapshot.time}")

# 使用示例
snapshot_mgr = SnapshotManager()

# 在仿真循环中
def run_with_snapshots():
    while not event_queue.empty():
        event = event_queue.get()
        current_time = event.time
        
        # 自动快照
        snapshot_mgr.auto_snapshot(simulator)
        
        # 处理event
        handle_event(event)
        
        # 关键点手动快照
        if event.type == EventType.IMPORTANT:
            snapshot_mgr.take_snapshot(simulator, label='important_event')

# 调试时回放
snapshot = snapshot_mgr.get_snapshot(label='important_event')
snapshot_mgr.replay_to_snapshot(simulator, snapshot)

# 从这个点重新运行
simulator.continue_from_current_state()
```

---

#### 14.3 验证检查清单

```python
class ModelValidator:
    """模型验证器"""
    
    def __init__(self, simulator):
        self.simulator = simulator
        self.errors = []
        self.warnings = []
    
    def validate_all(self):
        """运行所有验证"""
        print(f"\n{'='*60}")
        print(f"模型验证")
        print(f"{'='*60}\n")
        
        self.check_time_monotonicity()
        self.check_resource_consistency()
        self.check_dependency_satisfaction()
        self.check_conservation_laws()
        self.check_event_causality()
        
        self.print_results()
    
    def check_time_monotonicity(self):
        """检查时间单调性"""
        print("1. 检查时间单调性...")
        
        # 检查event queue中的时间
        times = [event.time for event in self.simulator.event_queue.queue]
        for i in range(len(times) - 1):
            if times[i] > times[i+1]:
                self.errors.append(
                    f"时间非单调: Event@{times[i]} 在 Event@{times[i+1]} 之前"
                )
        
        if not any('时间非单调' in e for e in self.errors):
            print("  ✓ 通过")
    
    def check_resource_consistency(self):
        """检查资源一致性"""
        print("2. 检查资源一致性...")
        
        for resource_name, resource in self.simulator.resources.items():
            # 检查: busy_until应该 >= current_time
            if resource.busy_until < self.simulator.current_time:
                if resource.current_user is not None:
                    self.errors.append(
                        f"{resource_name}: busy_until({resource.busy_until}) < "
                        f"current_time({self.simulator.current_time}), "
                        f"但仍有用户{resource.current_user}"
                    )
            
            # 检查: 如果busy_until > current_time, 应该有用户
            if resource.busy_until > self.simulator.current_time:
                if resource.current_user is None:
                    self.warnings.append(
                        f"{resource_name}: 资源标记为忙但无当前用户"
                    )
        
        if not any(resource_name in e for e in self.errors):
            print("  ✓ 通过")
    
    def check_dependency_satisfaction(self):
        """检查依赖满足"""
        print("3. 检查依赖满足...")
        
        for op_id, op in self.simulator.operations.items():
            if op.state in [OperationState.RUNNING, OperationState.COMPLETED]:
                # 检查所有依赖是否都已完成
                for dep_id in op.dependencies:
                    dep_op = self.simulator.operations[dep_id]
                    if dep_op.state != OperationState.COMPLETED:
                        self.errors.append(
                            f"操作{op_id}(状态:{op.state})的依赖{dep_id}"
                            f"未完成(状态:{dep_op.state})"
                        )
                    
                    if dep_op.end_time > op.start_time:
                        self.errors.append(
                            f"操作{op_id}(开始:{op.start_time})早于其依赖"
                            f"{dep_id}(结束:{dep_op.end_time})"
                        )
        
        if not any('依赖' in e for e in self.errors):
            print("  ✓ 通过")
    
    def check_conservation_laws(self):
        """检查守恒律"""
        print("4. 检查守恒律...")
        
        # 示例: 数据量守恒
        total_input = sum(
            op.input_data_size
            for op in self.simulator.operations.values()
            if op.state == OperationState.COMPLETED
        )
        
        total_output = sum(
            op.output_data_size
            for op in self.simulator.operations.values()
            if op.state == OperationState.COMPLETED
        )
        
        if abs(total_input - total_output) > 0.01:
            self.warnings.append(
                f"数据量不守恒: 输入{total_input}, 输出{total_output}"
            )
        else:
            print("  ✓ 通过")
    
    def check_event_causality(self):
        """检查event因果关系"""
        print("5. 检查event因果关系...")
        
        # 检查: COMPLETE event 应该在 START event 之后
        for op_id, op in self.simulator.operations.items():
            if op.state == OperationState.COMPLETED:
                if op.end_time <= op.start_time:
                    self.errors.append(
                        f"操作{op_id}: end_time({op.end_time}) <= "
                        f"start_time({op.start_time})"
                    )
        
        if not any('因果' in e or 'end_time' in e for e in self.errors):
            print("  ✓ 通过")
    
    def print_results(self):
        """打印验证结果"""
        print(f"\n{'='*60}")
        print(f"验证结果")
        print(f"{'='*60}\n")
        
        if not self.errors and not self.warnings:
            print("✓ 所有检查通过，模型正确")
            return
        
        if self.errors:
            print(f"❌ 发现{len(self.errors)}个错误:\n")
            for i, error in enumerate(self.errors, 1):
                print(f"  {i}. {error}")
        
        if self.warnings:
            print(f"\n⚠️ 发现{len(self.warnings)}个警告:\n")
            for i, warning in enumerate(self.warnings, 1):
                print(f"  {i}. {warning}")

# 使用示例
validator = ModelValidator(simulator)
validator.validate_all()
```

---

*第3部分完成，包含多通道并行、调度优化、性能分析和调试技巧*
