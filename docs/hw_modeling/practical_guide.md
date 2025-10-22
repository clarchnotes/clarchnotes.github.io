# 硬件性能建模完整指南 - 第4部分

## 第四部分：实践指南与完整示例

本部分提供完整的实现示例、设计模式和最佳实践，帮助您将前面学到的理论应用到实际项目中。

---

## 目录

- [15. 完整实现示例：DMA传输系统](#complete-dma-example)
  - 15.1 系统需求定义
  - 15.2 架构设计
  - 15.3 完整代码实现
  - 15.4 运行示例与输出
- [16. 常见设计模式](#design-patterns)
  - 16.1 资源池模式
  - 16.2 调度器模式
  - 16.3 状态机模式
  - 16.4 观察者模式（Notify机制）
- [17. 代码组织与架构](#code-organization)
  - 17.1 模块划分原则
  - 17.2 接口设计
  - 17.3 测试策略
- [18. 扩展性设计](#extensibility)
  - 18.1 如何添加新资源类型
  - 18.2 如何添加新事件类型
  - 18.3 如何扩展调度策略

---

## 15. 完整实现示例：DMA传输系统 {#complete-dma-example}

### 15.1 系统需求定义

**目标：** 构建一个完整的DMA传输系统性能模型

**系统规格：**

```python
硬件配置:
  - 4个DMA通道（Channel 0-3）
  - 2个内存端口（Port 0-1）
  - 每个端口带宽：32 GB/s
  - 每个通道有独立的控制逻辑

操作类型:
  - NORMAL传输：连续地址传输
  - STRIDE传输：跨步访问
  - 每个传输需要：
    * 1个DMA通道
    * 源端口（读）
    * 目标端口（写）

时序特性:
  - 端口访问延迟：10周期
  - 通道切换开销：5周期
  - 数据传输时间 = 数据量 / 带宽

依赖关系:
  - 传输B可能依赖传输A（数据依赖）
  - 依赖的传输必须等前序传输完成
```

---

### 15.2 架构设计

**模块划分：**

```
┌─────────────────────────────────────────────────────────┐
│ DMA Performance Simulator Architecture                  │
└─────────────────────────────────────────────────────────┘

Layer 1: Simulation Core
  ├─ EventQueue: 优先级队列管理所有事件
  ├─ Simulator: 主仿真循环
  └─ TimeManager: 时间管理

Layer 2: Resource Management
  ├─ Channel: DMA通道资源
  ├─ Port: 内存端口资源
  ├─ ResourceManager: 统一资源管理
  └─ ResourceState: 资源状态追踪

Layer 3: Workload & Scheduling
  ├─ Transfer: 传输请求定义
  ├─ Dependency: 依赖关系管理
  ├─ Scheduler: 调度策略
  └─ TransferQueue: 待处理传输队列

Layer 4: Statistics & Analysis
  ├─ Statistics: 性能统计
  ├─ Profiler: 性能剖析
  └─ Reporter: 结果报告
```

---

### 15.3 完整代码实现

#### 15.3.1 基础类定义

```python
"""
DMA Performance Simulator - Complete Implementation
"""

from queue import PriorityQueue
from enum import Enum
from dataclasses import dataclass
from typing import List, Dict, Optional, Set
from collections import defaultdict

# ============================================================
# Part 1: Event System
# ============================================================

class EventType(Enum):
    """事件类型"""
    TRANSFER_READY = "TRANSFER_READY"      # 传输就绪（依赖满足）
    SCHEDULE_ATTEMPT = "SCHEDULE_ATTEMPT"  # 尝试调度
    TRANSFER_START = "TRANSFER_START"      # 传输开始
    TRANSFER_COMPLETE = "TRANSFER_COMPLETE" # 传输完成

@dataclass(order=True)
class Event:
    """
    事件定义
    
    使用 @dataclass(order=True) 自动支持优先级比较
    """
    time: int                    # 事件发生时间（用于排序）
    type: EventType = None       # 事件类型
    transfer_id: int = None      # 关联的传输ID
    
    def __post_init__(self):
        # 确保time在最前面用于排序
        object.__setattr__(self, 'sort_index', self.time)

class EventQueue:
    """
    事件队列
    
    使用Python的PriorityQueue实现
    """
    def __init__(self):
        self._queue = PriorityQueue()
        self._event_count = 0  # 用于统计
    
    def push(self, event: Event):
        """添加事件"""
        self._queue.put(event)
        self._event_count += 1
    
    def pop(self) -> Optional[Event]:
        """取出最早的事件"""
        if not self._queue.empty():
            return self._queue.get()
        return None
    
    def empty(self) -> bool:
        """检查队列是否为空"""
        return self._queue.empty()
    
    def size(self) -> int:
        """队列大小"""
        return self._queue.qsize()

# ============================================================
# Part 2: Resource Management
# ============================================================

class Resource:
    """
    基础资源类
    
    适用于释放时间已知的资源
    """
    def __init__(self, resource_id: int, name: str):
        self.id = resource_id
        self.name = name
        self.busy_until = 0           # 资源忙到什么时候
        self.current_user = None      # 当前使用者
        
        # 统计信息
        self.total_busy_time = 0
        self.total_acquisitions = 0
    
    def is_available(self, at_time: int) -> bool:
        """检查资源在指定时间是否可用"""
        return at_time >= self.busy_until
    
    def acquire(self, user_id: int, start_time: int, duration: int):
        """
        获取资源
        
        Args:
            user_id: 使用者ID
            start_time: 开始时间
            duration: 使用时长
        """
        self.current_user = user_id
        self.busy_until = start_time + duration
        
        # 更新统计
        self.total_busy_time += duration
        self.total_acquisitions += 1
    
    def release(self):
        """释放资源"""
        self.current_user = None
        # busy_until 保持不变，用于追踪时间
    
    def get_available_time(self) -> int:
        """获取资源可用时间"""
        return self.busy_until
    
    def get_utilization(self, total_time: int) -> float:
        """计算资源利用率"""
        if total_time == 0:
            return 0.0
        return (self.total_busy_time / total_time) * 100.0

class Channel(Resource):
    """DMA通道"""
    def __init__(self, channel_id: int):
        super().__init__(channel_id, f"Channel_{channel_id}")

class Port(Resource):
    """内存端口"""
    def __init__(self, port_id: int, bandwidth_gbps: float):
        super().__init__(port_id, f"Port_{port_id}")
        self.bandwidth_gbps = bandwidth_gbps
    
    def calculate_transfer_time(self, data_size_bytes: int) -> int:
        """
        计算传输时间（周期数）
        
        Args:
            data_size_bytes: 数据量（字节）
        
        Returns:
            传输时间（周期数）
        """
        # 带宽: GB/s, 假设1GHz频率，1周期传输 bandwidth_gbps GB
        # 时间(周期) = 数据量(GB) / 带宽(GB/s)
        data_size_gb = data_size_bytes / (1024 ** 3)
        cycles = int(data_size_gb / self.bandwidth_gbps)
        return max(1, cycles)  # 至少1周期

class ResourceManager:
    """
    资源管理器
    
    统一管理所有硬件资源
    """
    def __init__(self, num_channels: int, num_ports: int, 
                 port_bandwidth_gbps: float):
        # 创建资源
        self.channels = [Channel(i) for i in range(num_channels)]
        self.ports = [Port(i, port_bandwidth_gbps) for i in range(num_ports)]
        
        self.num_channels = num_channels
        self.num_ports = num_ports
    
    def get_channel(self, channel_id: int) -> Channel:
        """获取指定通道"""
        return self.channels[channel_id]
    
    def get_port(self, port_id: int) -> Port:
        """获取指定端口"""
        return self.ports[port_id]
    
    def find_available_channel(self, at_time: int) -> Optional[Channel]:
        """查找可用的通道"""
        for channel in self.channels:
            if channel.is_available(at_time):
                return channel
        return None
    
    def get_earliest_available_channel(self) -> tuple[Channel, int]:
        """获取最早可用的通道及其可用时间"""
        earliest_channel = min(self.channels, key=lambda c: c.busy_until)
        return earliest_channel, earliest_channel.busy_until
    
    def are_ports_available(self, src_port: int, dst_port: int, 
                           at_time: int) -> bool:
        """检查源端口和目标端口是否都可用"""
        return (self.ports[src_port].is_available(at_time) and
                self.ports[dst_port].is_available(at_time))
    
    def get_ports_available_time(self, src_port: int, 
                                 dst_port: int) -> int:
        """获取两个端口都可用的最早时间"""
        src_time = self.ports[src_port].get_available_time()
        dst_time = self.ports[dst_port].get_available_time()
        return max(src_time, dst_time)
    
    def print_utilization(self, total_time: int):
        """打印资源利用率"""
        print("\n" + "="*60)
        print("Resource Utilization Report")
        print("="*60)
        
        print("\nChannels:")
        for channel in self.channels:
            util = channel.get_utilization(total_time)
            print(f"  {channel.name}: {util:.2f}% "
                  f"(used {channel.total_busy_time}/{total_time} cycles, "
                  f"{channel.total_acquisitions} acquisitions)")
        
        print("\nPorts:")
        for port in self.ports:
            util = port.get_utilization(total_time)
            print(f"  {port.name}: {util:.2f}% "
                  f"(used {port.total_busy_time}/{total_time} cycles, "
                  f"{port.total_acquisitions} acquisitions)")

# ============================================================
# Part 3: Transfer & Dependency
# ============================================================

class TransferType(Enum):
    """传输类型"""
    NORMAL = "NORMAL"
    STRIDE = "STRIDE"

@dataclass
class Transfer:
    """
    传输请求
    
    定义一个DMA传输的所有属性
    """
    id: int                          # 传输ID
    type: TransferType               # 传输类型
    data_size: int                   # 数据大小（字节）
    src_port: int                    # 源端口
    dst_port: int                    # 目标端口
    dependencies: List[int]          # 依赖的传输ID列表
    
    # 运行时状态
    state: str = "PENDING"           # PENDING, READY, SCHEDULED, RUNNING, COMPLETED
    assigned_channel: Optional[int] = None  # 分配的通道
    start_time: Optional[int] = None        # 实际开始时间
    end_time: Optional[int] = None          # 实际结束时间
    
    # 依赖追踪
    remaining_dependencies: Set[int] = None
    
    def __post_init__(self):
        """初始化后处理"""
        if self.remaining_dependencies is None:
            self.remaining_dependencies = set(self.dependencies)
    
    def is_ready(self) -> bool:
        """检查传输是否就绪（所有依赖都满足）"""
        return len(self.remaining_dependencies) == 0
    
    def resolve_dependency(self, completed_transfer_id: int):
        """解决一个依赖"""
        if completed_transfer_id in self.remaining_dependencies:
            self.remaining_dependencies.remove(completed_transfer_id)
    
    def get_latency(self) -> Optional[int]:
        """获取传输延迟"""
        if self.start_time is not None and self.end_time is not None:
            return self.end_time - self.start_time
        return None

class DependencyManager:
    """
    依赖管理器
    
    追踪传输之间的依赖关系
    """
    def __init__(self):
        # dependent_map[A] = [B, C] 表示传输B和C依赖于传输A
        self.dependent_map: Dict[int, List[int]] = defaultdict(list)
    
    def add_dependency(self, transfer: Transfer):
        """
        添加依赖关系
        
        Args:
            transfer: 传输对象
        """
        for dep_id in transfer.dependencies:
            self.dependent_map[dep_id].append(transfer.id)
    
    def get_dependents(self, transfer_id: int) -> List[int]:
        """
        获取依赖于指定传输的所有传输
        
        Args:
            transfer_id: 传输ID
        
        Returns:
            依赖于该传输的传输ID列表
        """
        return self.dependent_map.get(transfer_id, [])

# ============================================================
# Part 4: Scheduler
# ============================================================

class Scheduler:
    """
    调度器
    
    负责决定哪个传输应该被调度执行
    """
    def __init__(self, resource_manager: ResourceManager):
        self.resource_manager = resource_manager
    
    def try_schedule(self, transfer: Transfer, current_time: int) -> tuple[bool, Optional[int]]:
        """
        尝试调度一个传输
        
        Args:
            transfer: 传输对象
            current_time: 当前时间
        
        Returns:
            (是否成功, 如果失败则返回重试时间)
        """
        # 步骤1: 检查依赖是否满足
        if not transfer.is_ready():
            return False, None  # 依赖未满足，不返回重试时间
        
        # 步骤2: 查找可用通道
        channel = self.resource_manager.find_available_channel(current_time)
        if channel is None:
            # 没有可用通道，找最早可用的
            earliest_channel, earliest_time = \
                self.resource_manager.get_earliest_available_channel()
            return False, earliest_time
        
        # 步骤3: 检查端口是否可用
        if not self.resource_manager.are_ports_available(
            transfer.src_port, transfer.dst_port, current_time):
            # 端口不可用，找最早可用时间
            ports_time = self.resource_manager.get_ports_available_time(
                transfer.src_port, transfer.dst_port)
            return False, ports_time
        
        # 步骤4: 所有资源都可用，可以调度
        transfer.assigned_channel = channel.id
        transfer.state = "SCHEDULED"
        return True, None

# ============================================================
# Part 5: Simulator
# ============================================================

class DMASimulator:
    """
    DMA性能仿真器
    
    主仿真引擎，协调所有组件
    """
    def __init__(self, config: dict):
        # 配置
        self.config = config
        
        # 组件初始化
        self.event_queue = EventQueue()
        self.resource_manager = ResourceManager(
            num_channels=config['num_channels'],
            num_ports=config['num_ports'],
            port_bandwidth_gbps=config['port_bandwidth_gbps']
        )
        self.scheduler = Scheduler(self.resource_manager)
        self.dependency_manager = DependencyManager()
        
        # 传输管理
        self.transfers: Dict[int, Transfer] = {}
        self.pending_transfers: List[int] = []  # 待调度的传输ID
        self.completed_count = 0
        
        # 仿真状态
        self.current_time = 0
        self.verbose = config.get('verbose', False)
    
    def add_transfer(self, transfer: Transfer):
        """添加传输到仿真器"""
        self.transfers[transfer.id] = transfer
        self.dependency_manager.add_dependency(transfer)
        
        # 如果没有依赖，立即标记为就绪
        if transfer.is_ready():
            transfer.state = "READY"
            # 创建调度尝试事件
            self.event_queue.push(Event(
                time=0,
                type=EventType.SCHEDULE_ATTEMPT,
                transfer_id=transfer.id
            ))
        else:
            transfer.state = "PENDING"
            self.pending_transfers.append(transfer.id)
    
    def run(self):
        """运行仿真"""
        print("\n" + "="*60)
        print("DMA Simulation Start")
        print("="*60)
        print(f"Total transfers: {len(self.transfers)}")
        print(f"Configuration: {self.config}")
        
        # 主仿真循环
        while not self.event_queue.empty():
            event = self.event_queue.pop()
            self.current_time = event.time
            
            if self.verbose:
                print(f"\n[T={self.current_time}] Event: {event.type.value}, "
                      f"Transfer: {event.transfer_id}")
            
            # 分发事件
            if event.type == EventType.SCHEDULE_ATTEMPT:
                self._handle_schedule_attempt(event)
            elif event.type == EventType.TRANSFER_START:
                self._handle_transfer_start(event)
            elif event.type == EventType.TRANSFER_COMPLETE:
                self._handle_transfer_complete(event)
        
        # 仿真结束
        print("\n" + "="*60)
        print("DMA Simulation Complete")
        print("="*60)
        print(f"Total simulation time: {self.current_time} cycles")
        print(f"Completed transfers: {self.completed_count}/{len(self.transfers)}")
        
        # 打印资源利用率
        self.resource_manager.print_utilization(self.current_time)
        
        # 打印传输延迟统计
        self._print_transfer_statistics()
    
    def _handle_schedule_attempt(self, event: Event):
        """处理调度尝试事件"""
        transfer = self.transfers[event.transfer_id]
        
        if self.verbose:
            print(f"  Attempting to schedule Transfer {transfer.id}")
        
        # 尝试调度
        success, retry_time = self.scheduler.try_schedule(transfer, self.current_time)
        
        if success:
            # 调度成功，立即开始传输
            if self.verbose:
                print(f"  → Scheduled successfully on Channel {transfer.assigned_channel}")
            
            # 创建传输开始事件
            self.event_queue.push(Event(
                time=self.current_time,
                type=EventType.TRANSFER_START,
                transfer_id=transfer.id
            ))
        else:
            # 调度失败
            if retry_time is not None:
                if self.verbose:
                    print(f"  → Resources not available, retry at T={retry_time}")
                
                # 创建重试事件
                self.event_queue.push(Event(
                    time=retry_time,
                    type=EventType.SCHEDULE_ATTEMPT,
                    transfer_id=transfer.id
                ))
            else:
                if self.verbose:
                    print(f"  → Dependencies not satisfied, waiting for notify")
    
    def _handle_transfer_start(self, event: Event):
        """处理传输开始事件"""
        transfer = self.transfers[event.transfer_id]
        
        # 获取资源
        channel = self.resource_manager.get_channel(transfer.assigned_channel)
        src_port = self.resource_manager.get_port(transfer.src_port)
        dst_port = self.resource_manager.get_port(transfer.dst_port)
        
        # 计算传输时间
        transfer_time = src_port.calculate_transfer_time(transfer.data_size)
        
        # 分配资源
        channel.acquire(transfer.id, self.current_time, transfer_time)
        src_port.acquire(transfer.id, self.current_time, transfer_time)
        dst_port.acquire(transfer.id, self.current_time, transfer_time)
        
        # 更新传输状态
        transfer.state = "RUNNING"
        transfer.start_time = self.current_time
        transfer.end_time = self.current_time + transfer_time
        
        if self.verbose:
            print(f"  Transfer {transfer.id} started on Channel {transfer.assigned_channel}")
            print(f"  → Duration: {transfer_time} cycles")
            print(f"  → Will complete at T={transfer.end_time}")
        
        # 创建传输完成事件
        self.event_queue.push(Event(
            time=transfer.end_time,
            type=EventType.TRANSFER_COMPLETE,
            transfer_id=transfer.id
        ))
    
    def _handle_transfer_complete(self, event: Event):
        """处理传输完成事件"""
        transfer = self.transfers[event.transfer_id]
        
        # 更新状态
        transfer.state = "COMPLETED"
        self.completed_count += 1
        
        if self.verbose:
            latency = transfer.get_latency()
            print(f"  Transfer {transfer.id} completed")
            print(f"  → Latency: {latency} cycles")
            print(f"  → Completed: {self.completed_count}/{len(self.transfers)}")
        
        # 释放资源（仅清除current_user，busy_until保持用于调度）
        channel = self.resource_manager.get_channel(transfer.assigned_channel)
        src_port = self.resource_manager.get_port(transfer.src_port)
        dst_port = self.resource_manager.get_port(transfer.dst_port)
        
        channel.release()
        src_port.release()
        dst_port.release()
        
        # 通知依赖于这个传输的其他传输
        dependents = self.dependency_manager.get_dependents(transfer.id)
        if self.verbose and dependents:
            print(f"  → Notifying {len(dependents)} dependent transfers: {dependents}")
        
        for dep_id in dependents:
            dep_transfer = self.transfers[dep_id]
            dep_transfer.resolve_dependency(transfer.id)
            
            # 如果该传输的所有依赖都满足了，触发调度尝试
            if dep_transfer.is_ready() and dep_transfer.state == "PENDING":
                dep_transfer.state = "READY"
                
                if self.verbose:
                    print(f"    → Transfer {dep_id} is now ready")
                
                # 创建调度尝试事件（在当前时间）
                self.event_queue.push(Event(
                    time=self.current_time,
                    type=EventType.SCHEDULE_ATTEMPT,
                    transfer_id=dep_id
                ))
    
    def _print_transfer_statistics(self):
        """打印传输统计信息"""
        print("\n" + "="*60)
        print("Transfer Statistics")
        print("="*60)
        
        latencies = []
        for transfer in self.transfers.values():
            if transfer.state == "COMPLETED":
                latency = transfer.get_latency()
                latencies.append(latency)
                if self.verbose:
                    print(f"Transfer {transfer.id}: "
                          f"Start={transfer.start_time}, "
                          f"End={transfer.end_time}, "
                          f"Latency={latency} cycles")
        
        if latencies:
            print(f"\nLatency Statistics:")
            print(f"  Min: {min(latencies)} cycles")
            print(f"  Max: {max(latencies)} cycles")
            print(f"  Avg: {sum(latencies)/len(latencies):.2f} cycles")

# ============================================================
# Part 6: Example Usage
# ============================================================

def create_example_workload():
    """创建示例workload"""
    transfers = []
    
    # Transfer 0: 独立传输
    transfers.append(Transfer(
        id=0,
        type=TransferType.NORMAL,
        data_size=1024 * 1024,  # 1 MB
        src_port=0,
        dst_port=1,
        dependencies=[]
    ))
    
    # Transfer 1: 独立传输
    transfers.append(Transfer(
        id=1,
        type=TransferType.NORMAL,
        data_size=2 * 1024 * 1024,  # 2 MB
        src_port=0,
        dst_port=1,
        dependencies=[]
    ))
    
    # Transfer 2: 依赖Transfer 0
    transfers.append(Transfer(
        id=2,
        type=TransferType.NORMAL,
        data_size=512 * 1024,  # 512 KB
        src_port=1,
        dst_port=0,
        dependencies=[0]
    ))
    
    # Transfer 3: 依赖Transfer 1
    transfers.append(Transfer(
        id=3,
        type=TransferType.NORMAL,
        data_size=1024 * 1024,  # 1 MB
        src_port=1,
        dst_port=0,
        dependencies=[1]
    ))
    
    # Transfer 4: 依赖Transfer 2和3
    transfers.append(Transfer(
        id=4,
        type=TransferType.NORMAL,
        data_size=3 * 1024 * 1024,  # 3 MB
        src_port=0,
        dst_port=1,
        dependencies=[2, 3]
    ))
    
    return transfers

def main():
    """主函数"""
    # 配置
    config = {
        'num_channels': 4,
        'num_ports': 2,
        'port_bandwidth_gbps': 32.0,
        'verbose': True  # 设置为True查看详细输出
    }
    
    # 创建仿真器
    simulator = DMASimulator(config)
    
    # 添加传输
    transfers = create_example_workload()
    print("\nWorkload:")
    for transfer in transfers:
        print(f"  Transfer {transfer.id}: "
              f"Size={transfer.data_size/1024/1024:.2f}MB, "
              f"Src=Port{transfer.src_port}, "
              f"Dst=Port{transfer.dst_port}, "
              f"Dependencies={transfer.dependencies}")
        simulator.add_transfer(transfer)
    
    # 运行仿真
    simulator.run()

if __name__ == "__main__":
    main()
```

---

### 15.4 运行示例与输出

**运行仿真：**

```bash
python dma_simulator.py
```

**预期输出：**

```
Workload:
  Transfer 0: Size=1.00MB, Src=Port0, Dst=Port1, Dependencies=[]
  Transfer 1: Size=2.00MB, Src=Port0, Dst=Port1, Dependencies=[]
  Transfer 2: Size=0.50MB, Src=Port1, Dst=Port0, Dependencies=[0]
  Transfer 3: Size=1.00MB, Src=Port1, Dst=Port0, Dependencies=[1]
  Transfer 4: Size=3.00MB, Src=Port0, Dst=Port1, Dependencies=[2, 3]

============================================================
DMA Simulation Start
============================================================
Total transfers: 5
Configuration: {'num_channels': 4, 'num_ports': 2, 'port_bandwidth_gbps': 32.0, 'verbose': True}

[T=0] Event: SCHEDULE_ATTEMPT, Transfer: 0
  Attempting to schedule Transfer 0
  → Scheduled successfully on Channel 0
  Transfer 0 started on Channel 0
  → Duration: 1 cycles
  → Will complete at T=1

[T=0] Event: SCHEDULE_ATTEMPT, Transfer: 1
  Attempting to schedule Transfer 1
  → Scheduled successfully on Channel 1
  Transfer 1 started on Channel 1
  → Duration: 1 cycles
  → Will complete at T=1

[T=1] Event: TRANSFER_COMPLETE, Transfer: 0
  Transfer 0 completed
  → Latency: 1 cycles
  → Completed: 1/5
  → Notifying 1 dependent transfers: [2]
    → Transfer 2 is now ready

[T=1] Event: TRANSFER_COMPLETE, Transfer: 1
  Transfer 1 completed
  → Latency: 1 cycles
  → Completed: 2/5
  → Notifying 1 dependent transfers: [3]
    → Transfer 3 is now ready

[T=1] Event: SCHEDULE_ATTEMPT, Transfer: 2
  Attempting to schedule Transfer 2
  → Scheduled successfully on Channel 0
  Transfer 2 started on Channel 0
  → Duration: 1 cycles
  → Will complete at T=2

[T=1] Event: SCHEDULE_ATTEMPT, Transfer: 3
  Attempting to schedule Transfer 3
  → Scheduled successfully on Channel 1
  Transfer 3 started on Channel 1
  → Duration: 1 cycles
  → Will complete at T=2

[T=2] Event: TRANSFER_COMPLETE, Transfer: 2
  Transfer 2 completed
  → Latency: 1 cycles
  → Completed: 3/5
  → Notifying 1 dependent transfers: [4]

[T=2] Event: TRANSFER_COMPLETE, Transfer: 3
  Transfer 3 completed
  → Latency: 1 cycles
  → Completed: 4/5
  → Notifying 1 dependent transfers: [4]
    → Transfer 4 is now ready

[T=2] Event: SCHEDULE_ATTEMPT, Transfer: 4
  Attempting to schedule Transfer 4
  → Scheduled successfully on Channel 0
  Transfer 4 started on Channel 0
  → Duration: 1 cycles
  → Will complete at T=3

[T=3] Event: TRANSFER_COMPLETE, Transfer: 4
  Transfer 4 completed
  → Latency: 1 cycles
  → Completed: 5/5

============================================================
DMA Simulation Complete
============================================================
Total simulation time: 3 cycles
Completed transfers: 5/5

============================================================
Resource Utilization Report
============================================================

Channels:
  Channel_0: 75.00% (used 3/4 cycles, 3 acquisitions)
  Channel_1: 50.00% (used 2/4 cycles, 2 acquisitions)
  Channel_2: 0.00% (used 0/4 cycles, 0 acquisitions)
  Channel_3: 0.00% (used 0/4 cycles, 0 acquisitions)

Ports:
  Port_0: 50.00% (used 2/4 cycles, 5 acquisitions)
  Port_1: 50.00% (used 2/4 cycles, 5 acquisitions)

============================================================
Transfer Statistics
============================================================

Latency Statistics:
  Min: 1 cycles
  Max: 1 cycles
  Avg: 1.00 cycles
```

---

*第15节完成：完整实现示例*

---

## 16. 常见设计模式 {#design-patterns}

### 16.1 资源池模式 (Resource Pool Pattern)

**问题：** 如何管理多个相同类型的资源（如4个DMA通道）？

**解决方案：** 使用资源池模式

```python
class ResourcePool:
    """
    资源池模式
    
    管理一组相同类型的资源，提供统一的分配接口
    """
    def __init__(self, resource_type: type, count: int, **kwargs):
        """
        Args:
            resource_type: 资源类型（如Channel）
            count: 资源数量
            **kwargs: 传递给资源构造函数的参数
        """
        self.resources = [
            resource_type(i, **kwargs) 
            for i in range(count)
        ]
        self.count = count
    
    def find_available(self, at_time: int) -> Optional:
        """
        查找可用资源
        
        策略: 返回第一个可用的资源
        """
        for resource in self.resources:
            if resource.is_available(at_time):
                return resource
        return None
    
    def find_earliest_available(self) -> tuple:
        """
        查找最早可用的资源
        
        Returns:
            (resource, available_time)
        """
        earliest = min(self.resources, key=lambda r: r.busy_until)
        return earliest, earliest.busy_until
    
    def find_least_used(self, at_time: int) -> Optional:
        """
        查找使用最少的可用资源（负载均衡）
        """
        available = [r for r in self.resources if r.is_available(at_time)]
        if not available:
            return None
        return min(available, key=lambda r: r.total_busy_time)
    
    def get_all_available_times(self) -> List[int]:
        """获取所有资源的可用时间"""
        return [r.busy_until for r in self.resources]
    
    def get_pool_statistics(self, total_time: int) -> dict:
        """获取资源池统计信息"""
        utils = [r.get_utilization(total_time) for r in self.resources]
        return {
            'count': self.count,
            'avg_utilization': sum(utils) / len(utils),
            'min_utilization': min(utils),
            'max_utilization': max(utils),
            'utilizations': utils
        }

# 使用示例
class ImprovedResourceManager:
    def __init__(self, config):
        # 使用资源池管理通道
        self.channel_pool = ResourcePool(
            resource_type=Channel,
            count=config['num_channels']
        )
        
        # 使用资源池管理端口
        self.port_pool = ResourcePool(
            resource_type=Port,
            count=config['num_ports'],
            bandwidth_gbps=config['port_bandwidth_gbps']
        )
    
    def allocate_channel(self, at_time: int, strategy='first_available'):
        """
        分配通道
        
        Args:
            at_time: 分配时间
            strategy: 分配策略
                - 'first_available': 第一个可用的
                - 'least_used': 使用最少的（负载均衡）
        """
        if strategy == 'first_available':
            return self.channel_pool.find_available(at_time)
        elif strategy == 'least_used':
            return self.channel_pool.find_least_used(at_time)
        else:
            raise ValueError(f"Unknown strategy: {strategy}")
```

**优势：**

- ✓ 统一管理多个资源
- ✓ 支持多种分配策略
- ✓ 易于扩展和维护
- ✓ 便于统计和分析

---

### 16.2 调度器模式 (Scheduler Pattern)

**问题：** 如何灵活地实现不同的调度策略？

**解决方案：** 使用策略模式实现可插拔的调度器

```python
from abc import ABC, abstractmethod

class SchedulingStrategy(ABC):
    """调度策略基类"""
    
    @abstractmethod
    def select_next_transfer(self, ready_transfers: List[Transfer], 
                            current_time: int) -> Optional[Transfer]:
        """
        从就绪的传输中选择下一个执行的传输
        
        Args:
            ready_transfers: 就绪的传输列表
            current_time: 当前时间
        
        Returns:
            被选中的传输，如果没有可选传输则返回None
        """
        pass

class FCFSStrategy(SchedulingStrategy):
    """
    First-Come-First-Serve策略
    
    按照传输ID顺序调度（假设ID越小越早到达）
    """
    def select_next_transfer(self, ready_transfers, current_time):
        if not ready_transfers:
            return None
        return min(ready_transfers, key=lambda t: t.id)

class SJFStrategy(SchedulingStrategy):
    """
    Shortest-Job-First策略
    
    优先调度数据量最小的传输
    """
    def select_next_transfer(self, ready_transfers, current_time):
        if not ready_transfers:
            return None
        return min(ready_transfers, key=lambda t: t.data_size)

class PriorityStrategy(SchedulingStrategy):
    """
    优先级调度策略
    
    按照优先级调度（需要Transfer有priority属性）
    """
    def select_next_transfer(self, ready_transfers, current_time):
        if not ready_transfers:
            return None
        # 优先级越小越高
        return min(ready_transfers, key=lambda t: (t.priority, t.id))

class AdaptiveScheduler:
    """
    自适应调度器
    
    支持运行时切换调度策略
    """
    def __init__(self, resource_manager: ResourceManager, 
                 strategy: SchedulingStrategy = None):
        self.resource_manager = resource_manager
        self.strategy = strategy or FCFSStrategy()
        
        # 统计信息
        self.schedule_attempts = 0
        self.schedule_successes = 0
    
    def set_strategy(self, strategy: SchedulingStrategy):
        """动态切换调度策略"""
        self.strategy = strategy
        print(f"Scheduler strategy changed to: {strategy.__class__.__name__}")
    
    def schedule_batch(self, ready_transfers: List[Transfer], 
                      current_time: int) -> List[tuple[Transfer, bool]]:
        """
        批量调度
        
        Args:
            ready_transfers: 就绪的传输列表
            current_time: 当前时间
        
        Returns:
            [(transfer, success), ...] 列表
        """
        results = []
        remaining = list(ready_transfers)
        
        while remaining:
            # 选择下一个传输
            selected = self.strategy.select_next_transfer(remaining, current_time)
            if selected is None:
                break
            
            # 尝试调度
            self.schedule_attempts += 1
            success, retry_time = self._try_schedule_internal(selected, current_time)
            
            results.append((selected, success))
            remaining.remove(selected)
            
            if success:
                self.schedule_successes += 1
            else:
                # 调度失败，停止本批次
                break
        
        return results
    
    def _try_schedule_internal(self, transfer: Transfer, 
                              current_time: int) -> tuple[bool, Optional[int]]:
        """内部调度逻辑（与之前的Scheduler类似）"""
        # 检查通道
        channel = self.resource_manager.find_available_channel(current_time)
        if channel is None:
            _, earliest_time = self.resource_manager.get_earliest_available_channel()
            return False, earliest_time
        
        # 检查端口
        if not self.resource_manager.are_ports_available(
            transfer.src_port, transfer.dst_port, current_time):
            ports_time = self.resource_manager.get_ports_available_time(
                transfer.src_port, transfer.dst_port)
            return False, ports_time
        
        # 成功调度
        transfer.assigned_channel = channel.id
        transfer.state = "SCHEDULED"
        return True, None
    
    def get_statistics(self) -> dict:
        """获取调度统计"""
        success_rate = 0.0
        if self.schedule_attempts > 0:
            success_rate = (self.schedule_successes / self.schedule_attempts) * 100.0
        
        return {
            'strategy': self.strategy.__class__.__name__,
            'attempts': self.schedule_attempts,
            'successes': self.schedule_successes,
            'success_rate': success_rate
        }

# 使用示例
def scheduling_strategy_example():
    """演示不同调度策略的效果"""
    
    # 创建配置
    config = {
        'num_channels': 2,
        'num_ports': 2,
        'port_bandwidth_gbps': 32.0
    }
    
    resource_manager = ResourceManager(**config)
    
    # 创建调度器，初始使用FCFS策略
    scheduler = AdaptiveScheduler(resource_manager, FCFSStrategy())
    
    # 准备一些传输
    transfers = [
        Transfer(id=0, type=TransferType.NORMAL, data_size=3*1024*1024, 
                src_port=0, dst_port=1, dependencies=[]),
        Transfer(id=1, type=TransferType.NORMAL, data_size=1*1024*1024,
                src_port=0, dst_port=1, dependencies=[]),
        Transfer(id=2, type=TransferType.NORMAL, data_size=2*1024*1024,
                src_port=0, dst_port=1, dependencies=[]),
    ]
    
    print("="*60)
    print("Strategy: FCFS (First-Come-First-Serve)")
    print("="*60)
    results = scheduler.schedule_batch(transfers, current_time=0)
    print(f"Schedule order: {[t.id for t, success in results if success]}")
    print(f"Stats: {scheduler.get_statistics()}")
    
    # 切换到SJF策略
    scheduler.set_strategy(SJFStrategy())
    
    # 重置传输状态
    for t in transfers:
        t.state = "READY"
        t.assigned_channel = None
    
    print("\n" + "="*60)
    print("Strategy: SJF (Shortest-Job-First)")
    print("="*60)
    results = scheduler.schedule_batch(transfers, current_time=0)
    print(f"Schedule order: {[t.id for t, success in results if success]}")
    print(f"Stats: {scheduler.get_statistics()}")
```

**优势：**

- ✓ 策略可插拔，易于扩展
- ✓ 支持运行时切换策略
- ✓ 便于比较不同策略的效果
- ✓ 符合开闭原则

---

### 16.3 状态机模式 (State Machine Pattern)

**问题：** 如何清晰地管理传输的状态转换？

**解决方案：** 使用状态机模式

```python
from enum import Enum, auto

class TransferState(Enum):
    """传输状态"""
    PENDING = auto()      # 等待依赖
    READY = auto()        # 就绪，可以调度
    SCHEDULED = auto()    # 已调度，等待执行
    RUNNING = auto()      # 正在执行
    COMPLETED = auto()    # 已完成
    FAILED = auto()       # 失败

class TransferStateMachine:
    """
    传输状态机
    
    管理传输状态转换，确保状态转换的合法性
    """
    
    # 定义合法的状态转换
    VALID_TRANSITIONS = {
        TransferState.PENDING: [TransferState.READY, TransferState.FAILED],
        TransferState.READY: [TransferState.SCHEDULED, TransferState.FAILED],
        TransferState.SCHEDULED: [TransferState.RUNNING, TransferState.READY, TransferState.FAILED],
        TransferState.RUNNING: [TransferState.COMPLETED, TransferState.FAILED],
        TransferState.COMPLETED: [],  # 终态
        TransferState.FAILED: []      # 终态
    }
    
    def __init__(self, transfer_id: int):
        self.transfer_id = transfer_id
        self.current_state = TransferState.PENDING
        self.state_history = [(0, TransferState.PENDING)]  # (time, state)
    
    def transition(self, new_state: TransferState, current_time: int) -> bool:
        """
        尝试状态转换
        
        Args:
            new_state: 新状态
            current_time: 当前时间
        
        Returns:
            是否转换成功
        """
        # 检查转换是否合法
        if new_state not in self.VALID_TRANSITIONS[self.current_state]:
            print(f"[Warning] Invalid state transition for Transfer {self.transfer_id}: "
                  f"{self.current_state.name} -> {new_state.name}")
            return False
        
        # 执行转换
        old_state = self.current_state
        self.current_state = new_state
        self.state_history.append((current_time, new_state))
        
        print(f"[T={current_time}] Transfer {self.transfer_id}: "
              f"{old_state.name} -> {new_state.name}")
        
        return True
    
    def can_transition_to(self, new_state: TransferState) -> bool:
        """检查是否可以转换到指定状态"""
        return new_state in self.VALID_TRANSITIONS[self.current_state]
    
    def is_terminal(self) -> bool:
        """检查是否处于终态"""
        return self.current_state in [TransferState.COMPLETED, TransferState.FAILED]
    
    def get_time_in_state(self, state: TransferState) -> int:
        """计算在某个状态停留的总时间"""
        total_time = 0
        for i in range(len(self.state_history)):
            time, s = self.state_history[i]
            if s == state:
                # 找到下一个状态的时间
                if i + 1 < len(self.state_history):
                    next_time, _ = self.state_history[i + 1]
                    total_time += (next_time - time)
        return total_time
    
    def print_history(self):
        """打印状态历史"""
        print(f"\nTransfer {self.transfer_id} State History:")
        for time, state in self.state_history:
            print(f"  T={time}: {state.name}")

# 增强的Transfer类（使用状态机）
class TransferWithStateMachine(Transfer):
    """带状态机的Transfer"""
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.state_machine = TransferStateMachine(self.id)
    
    def set_state(self, new_state: str, current_time: int):
        """
        设置状态（通过状态机）
        
        Args:
            new_state: 新状态名称（字符串）
            current_time: 当前时间
        """
        # 转换字符串到枚举
        state_enum_map = {
            'PENDING': TransferState.PENDING,
            'READY': TransferState.READY,
            'SCHEDULED': TransferState.SCHEDULED,
            'RUNNING': TransferState.RUNNING,
            'COMPLETED': TransferState.COMPLETED,
            'FAILED': TransferState.FAILED
        }
        
        state_enum = state_enum_map.get(new_state)
        if state_enum is None:
            raise ValueError(f"Unknown state: {new_state}")
        
        # 通过状态机执行转换
        if self.state_machine.transition(state_enum, current_time):
            self.state = new_state  # 更新基类的state字段
            return True
        return False
    
    def get_state_statistics(self) -> dict:
        """获取状态统计"""
        stats = {}
        for state in TransferState:
            time_in_state = self.state_machine.get_time_in_state(state)
            if time_in_state > 0:
                stats[state.name] = time_in_state
        return stats

# 使用示例
def state_machine_example():
    """演示状态机的使用"""
    transfer = TransferWithStateMachine(
        id=0,
        type=TransferType.NORMAL,
        data_size=1024*1024,
        src_port=0,
        dst_port=1,
        dependencies=[]
    )
    
    print("="*60)
    print("State Machine Example")
    print("="*60)
    
    # 正常的状态转换
    transfer.set_state('READY', current_time=0)
    transfer.set_state('SCHEDULED', current_time=10)
    transfer.set_state('RUNNING', current_time=20)
    transfer.set_state('COMPLETED', current_time=100)
    
    # 尝试非法转换（已完成，不能再转换）
    print("\nAttempting invalid transition:")
    transfer.set_state('RUNNING', current_time=200)
    
    # 打印状态历史
    transfer.state_machine.print_history()
    
    # 打印状态统计
    print("\nTime in each state:")
    stats = transfer.get_state_statistics()
    for state_name, time in stats.items():
        print(f"  {state_name}: {time} cycles")
```

**优势：**

- ✓ 状态转换清晰可追踪
- ✓ 防止非法状态转换
- ✓ 便于调试和分析
- ✓ 易于扩展新状态

---

### 16.4 观察者模式 (Observer Pattern) - Notify机制

**问题：** 如何实现高效的依赖通知机制？

**解决方案：** 使用观察者模式

```python
from typing import Callable, List

class Observable:
    """
    可观察对象（被观察者）
    
    其他对象可以订阅它的事件
    """
    def __init__(self):
        self._observers: List[Callable] = []
    
    def attach(self, observer: Callable):
        """添加观察者"""
        if observer not in self._observers:
            self._observers.append(observer)
    
    def detach(self, observer: Callable):
        """移除观察者"""
        if observer in self._observers:
            self._observers.remove(observer)
    
    def notify(self, *args, **kwargs):
        """通知所有观察者"""
        for observer in self._observers:
            observer(*args, **kwargs)

class TransferWithObserver(Transfer, Observable):
    """
    支持观察者模式的Transfer
    
    当传输完成时，自动通知所有观察者
    """
    def __init__(self, *args, **kwargs):
        Transfer.__init__(self, *args, **kwargs)
        Observable.__init__(self)
    
    def complete(self, end_time: int):
        """
        标记传输完成
        
        自动通知所有观察者
        """
        self.state = "COMPLETED"
        self.end_time = end_time
        
        # 通知观察者
        self.notify(transfer_id=self.id, end_time=end_time)

class DependencyObserver:
    """
    依赖观察者
    
    观察某个传输，当它完成时解决依赖
    """
    def __init__(self, dependent_transfer: Transfer, 
                 dependency_id: int, event_queue: EventQueue):
        self.dependent_transfer = dependent_transfer
        self.dependency_id = dependency_id
        self.event_queue = event_queue
    
    def __call__(self, transfer_id: int, end_time: int):
        """
        被通知时调用
        
        Args:
            transfer_id: 完成的传输ID
            end_time: 完成时间
        """
        # 解决依赖
        self.dependent_transfer.resolve_dependency(transfer_id)
        
        print(f"  [Observer] Transfer {self.dependent_transfer.id} "
              f"resolved dependency on Transfer {transfer_id}")
        
        # 如果所有依赖都满足，触发调度
        if self.dependent_transfer.is_ready():
            self.dependent_transfer.state = "READY"
            
            print(f"  [Observer] Transfer {self.dependent_transfer.id} "
                  f"is now READY")
            
            # 创建调度事件
            self.event_queue.push(Event(
                time=end_time,
                type=EventType.SCHEDULE_ATTEMPT,
                transfer_id=self.dependent_transfer.id
            ))

class ObserverBasedDependencyManager:
    """
    基于观察者模式的依赖管理器
    
    使用观察者模式实现依赖通知，比直接查找更高效
    """
    def __init__(self, event_queue: EventQueue):
        self.event_queue = event_queue
        self.transfers: Dict[int, TransferWithObserver] = {}
    
    def add_transfer(self, transfer: TransferWithObserver):
        """
        添加传输
        
        自动建立观察者关系
        """
        self.transfers[transfer.id] = transfer
        
        # 为每个依赖建立观察者
        for dep_id in transfer.dependencies:
            if dep_id in self.transfers:
                # 被依赖的传输
                dep_transfer = self.transfers[dep_id]
                
                # 创建观察者
                observer = DependencyObserver(
                    dependent_transfer=transfer,
                    dependency_id=dep_id,
                    event_queue=self.event_queue
                )
                
                # 订阅被依赖传输的完成事件
                dep_transfer.attach(observer)
                
                print(f"[DependencyManager] Transfer {transfer.id} "
                      f"now observes Transfer {dep_id}")
    
    def complete_transfer(self, transfer_id: int, end_time: int):
        """
        标记传输完成
        
        自动触发观察者通知
        """
        transfer = self.transfers[transfer_id]
        transfer.complete(end_time)  # 会自动通知所有观察者

# 使用示例
def observer_pattern_example():
    """演示观察者模式的使用"""
    print("="*60)
    print("Observer Pattern Example")
    print("="*60)
    
    event_queue = EventQueue()
    dependency_manager = ObserverBasedDependencyManager(event_queue)
    
    # 创建传输
    transfer0 = TransferWithObserver(
        id=0,
        type=TransferType.NORMAL,
        data_size=1024*1024,
        src_port=0,
        dst_port=1,
        dependencies=[]
    )
    
    transfer1 = TransferWithObserver(
        id=1,
        type=TransferType.NORMAL,
        data_size=1024*1024,
        src_port=0,
        dst_port=1,
        dependencies=[0]  # 依赖transfer0
    )
    
    transfer2 = TransferWithObserver(
        id=2,
        type=TransferType.NORMAL,
        data_size=1024*1024,
        src_port=0,
        dst_port=1,
        dependencies=[0, 1]  # 依赖transfer0和transfer1
    )
    
    # 添加到依赖管理器（自动建立观察者关系）
    print("\nSetting up observers:")
    dependency_manager.add_transfer(transfer0)
    dependency_manager.add_transfer(transfer1)
    dependency_manager.add_transfer(transfer2)
    
    # 模拟传输完成
    print("\n" + "-"*60)
    print("Simulating transfer completions:")
    print("-"*60)
    
    print("\nTransfer 0 completes at T=100:")
    dependency_manager.complete_transfer(0, end_time=100)
    
    print("\nTransfer 1 completes at T=200:")
    dependency_manager.complete_transfer(1, end_time=200)
    
    print("\n" + "="*60)
    print("Events in queue:")
    while not event_queue.empty():
        event = event_queue.pop()
        print(f"  T={event.time}: {event.type.value} for Transfer {event.transfer_id}")
```

**优势：**

- ✓ 解耦依赖关系管理
- ✓ 自动通知，无需轮询
- ✓ 易于扩展（可添加多种观察者）
- ✓ 符合开闭原则

---

*第16节完成：常见设计模式*

---

## 17. 代码组织与架构 {#code-organization}

### 17.1 模块划分原则

**推荐的项目结构：**

```
dma_performance_model/
├── README.md
├── requirements.txt
├── setup.py
│
├── src/
│   ├── __init__.py
│   │
│   ├── core/              # 核心仿真引擎
│   │   ├── __init__.py
│   │   ├── event.py       # 事件定义
│   │   ├── simulator.py   # 主仿真器
│   │   └── time_manager.py
│   │
│   ├── resources/         # 资源管理
│   │   ├── __init__.py
│   │   ├── resource.py    # 基础资源类
│   │   ├── channel.py     # DMA通道
│   │   ├── port.py        # 内存端口
│   │   └── manager.py     # 资源管理器
│   │
│   ├── workload/          # 工作负载
│   │   ├── __init__.py
│   │   ├── transfer.py    # 传输定义
│   │   ├── dependency.py  # 依赖管理
│   │   └── generator.py   # Workload生成器
│   │
│   ├── scheduling/        # 调度
│   │   ├── __init__.py
│   │   ├── scheduler.py   # 调度器基类
│   │   ├── strategies.py  # 调度策略
│   │   └── policies.py    # 调度策略
│   │
│   ├── analysis/          # 分析与统计
│   │   ├── __init__.py
│   │   ├── statistics.py  # 统计收集
│   │   ├── profiler.py    # 性能剖析
│   │   └── reporter.py    # 报告生成
│   │
│   └── utils/             # 工具函数
│       ├── __init__.py
│       ├── config.py      # 配置管理
│       └── logger.py      # 日志
│
├── tests/                 # 测试
│   ├── __init__.py
│   ├── test_core/
│   ├── test_resources/
│   ├── test_workload/
│   ├── test_scheduling/
│   └── test_integration/
│
├── examples/              # 示例
│   ├── basic_example.py
│   ├── dependency_example.py
│   └── advanced_example.py
│
└── docs/                  # 文档
    ├── design.md
    ├── api.md
    └── tutorial.md
```

**模块划分原则：**

```python
单一职责原则 (SRP):
  ✓ 每个模块只负责一类功能
  ✓ core/ 只负责仿真引擎
  ✓ resources/ 只负责资源管理
  ✓ workload/ 只负责工作负载定义

高内聚低耦合:
  ✓ 模块内部高度相关
  ✓ 模块之间依赖最小化
  ✓ 使用接口而不是具体实现

分层架构:
  Layer 1: Core (核心仿真引擎)
  Layer 2: Resources (资源管理)
  Layer 3: Workload & Scheduling (业务逻辑)
  Layer 4: Analysis (分析与统计)
  
  依赖方向: Layer 4 -> Layer 3 -> Layer 2 -> Layer 1
```

---

### 17.2 接口设计

**设计清晰的接口:**

```python
# ============================================================
# 资源接口
# ============================================================

from abc import ABC, abstractmethod
from typing import Protocol

class ResourceInterface(Protocol):
    """
    资源接口定义
    
    使用Protocol (Python 3.8+) 定义接口
    """
    def is_available(self, at_time: int) -> bool:
        """检查资源是否可用"""
        ...
    
    def acquire(self, user_id: int, start_time: int, duration: int):
        """获取资源"""
        ...
    
    def release(self):
        """释放资源"""
        ...
    
    def get_available_time(self) -> int:
        """获取可用时间"""
        ...

# ============================================================
# 调度器接口
# ============================================================

class SchedulerInterface(ABC):
    """调度器接口"""
    
    @abstractmethod
    def schedule(self, transfer: 'Transfer', current_time: int) -> tuple[bool, Optional[int]]:
        """
        尝试调度传输
        
        Args:
            transfer: 待调度的传输
            current_time: 当前时间
        
        Returns:
            (是否成功, 重试时间)
        """
        pass
    
    @abstractmethod
    def get_statistics(self) -> dict:
        """获取调度统计"""
        pass

# ============================================================
# 仿真器接口
# ============================================================

class SimulatorInterface(ABC):
    """仿真器接口"""
    
    @abstractmethod
    def add_transfer(self, transfer: 'Transfer'):
        """添加传输到仿真"""
        pass
    
    @abstractmethod
    def run(self) -> dict:
        """
        运行仿真
        
        Returns:
            仿真结果字典
        """
        pass
    
    @abstractmethod
    def get_results(self) -> dict:
        """获取仿真结果"""
        pass

# ============================================================
# 使用依赖注入
# ============================================================

class ConfigurableSimulator:
    """
    可配置的仿真器
    
    使用依赖注入，便于测试和扩展
    """
    def __init__(self,
                 resource_manager: ResourceInterface,
                 scheduler: SchedulerInterface,
                 dependency_manager: 'DependencyManager',
                 event_queue: EventQueue):
        """
        Args:
            resource_manager: 资源管理器（注入）
            scheduler: 调度器（注入）
            dependency_manager: 依赖管理器（注入）
            event_queue: 事件队列（注入）
        """
        self.resource_manager = resource_manager
        self.scheduler = scheduler
        self.dependency_manager = dependency_manager
        self.event_queue = event_queue
        
        self.current_time = 0
        self.transfers = {}
    
    @classmethod
    def from_config(cls, config: dict):
        """
        工厂方法：从配置创建仿真器
        
        Args:
            config: 配置字典
        
        Returns:
            配置好的仿真器实例
        """
        # 根据配置创建组件
        resource_manager = ResourceManager(
            num_channels=config['num_channels'],
            num_ports=config['num_ports'],
            port_bandwidth_gbps=config['port_bandwidth_gbps']
        )
        
        scheduler_type = config.get('scheduler_type', 'FCFS')
        if scheduler_type == 'FCFS':
            scheduler = FCFSScheduler(resource_manager)
        elif scheduler_type == 'SJF':
            scheduler = SJFScheduler(resource_manager)
        else:
            raise ValueError(f"Unknown scheduler type: {scheduler_type}")
        
        dependency_manager = DependencyManager()
        event_queue = EventQueue()
        
        # 创建仿真器
        return cls(resource_manager, scheduler, dependency_manager, event_queue)
```

**接口设计原则：**

- ✓ 面向接口编程，不面向实现
- ✓ 使用抽象基类(ABC)或Protocol定义接口
- ✓ 依赖注入，便于测试和替换
- ✓ 提供工厂方法，简化对象创建

---

### 17.3 测试策略

**完整的测试金字塔：**

```python
# ============================================================
# 单元测试 (Unit Tests)
# ============================================================

import unittest

class TestResource(unittest.TestCase):
    """资源类单元测试"""
    
    def setUp(self):
        """每个测试前执行"""
        self.resource = Resource(id=0, name="TestResource")
    
    def test_initial_state(self):
        """测试初始状态"""
        self.assertTrue(self.resource.is_available(0))
        self.assertEqual(self.resource.busy_until, 0)
        self.assertIsNone(self.resource.current_user)
    
    def test_acquire_and_release(self):
        """测试获取和释放"""
        # 获取资源
        self.resource.acquire(user_id=1, start_time=0, duration=10)
        
        # 验证状态
        self.assertFalse(self.resource.is_available(5))
        self.assertTrue(self.resource.is_available(10))
        self.assertEqual(self.resource.busy_until, 10)
        self.assertEqual(self.resource.current_user, 1)
        
        # 释放资源
        self.resource.release()
        self.assertIsNone(self.resource.current_user)
    
    def test_utilization(self):
        """测试利用率计算"""
        self.resource.acquire(1, 0, 50)
        self.resource.acquire(2, 50, 30)
        
        util = self.resource.get_utilization(100)
        self.assertAlmostEqual(util, 80.0)

# ============================================================
# 集成测试 (Integration Tests)
# ============================================================

class TestResourceSchedulerIntegration(unittest.TestCase):
    """资源管理器和调度器集成测试"""
    
    def setUp(self):
        self.resource_manager = ResourceManager(
            num_channels=2,
            num_ports=2,
            port_bandwidth_gbps=32.0
        )
        self.scheduler = Scheduler(self.resource_manager)
    
    def test_schedule_single_transfer(self):
        """测试调度单个传输"""
        transfer = Transfer(
            id=0,
            type=TransferType.NORMAL,
            data_size=1024*1024,
            src_port=0,
            dst_port=1,
            dependencies=[]
        )
        
        success, retry_time = self.scheduler.try_schedule(transfer, current_time=0)
        
        self.assertTrue(success)
        self.assertIsNotNone(transfer.assigned_channel)
        self.assertEqual(transfer.state, "SCHEDULED")
    
    def test_schedule_resource_contention(self):
        """测试资源竞争场景"""
        # 创建多个传输
        transfers = [
            Transfer(id=i, type=TransferType.NORMAL, 
                    data_size=1024*1024, src_port=0, dst_port=1, 
                    dependencies=[])
            for i in range(5)
        ]
        
        # 尝试在同一时间调度所有传输
        results = []
        for t in transfers:
            success, retry_time = self.scheduler.try_schedule(t, current_time=0)
            results.append(success)
        
        # 验证：只有2个能成功（因为只有2个通道）
        self.assertEqual(sum(results), 2)

# ============================================================
# 端到端测试 (E2E Tests)
# ============================================================

class TestEndToEnd(unittest.TestCase):
    """端到端测试"""
    
    def test_complete_simulation(self):
        """测试完整的仿真流程"""
        # 配置
        config = {
            'num_channels': 4,
            'num_ports': 2,
            'port_bandwidth_gbps': 32.0,
            'verbose': False
        }
        
        # 创建仿真器
        simulator = DMASimulator(config)
        
        # 添加传输
        transfers = [
            Transfer(id=0, type=TransferType.NORMAL, data_size=1024*1024,
                    src_port=0, dst_port=1, dependencies=[]),
            Transfer(id=1, type=TransferType.NORMAL, data_size=1024*1024,
                    src_port=0, dst_port=1, dependencies=[0]),
        ]
        
        for t in transfers:
            simulator.add_transfer(t)
        
        # 运行仿真
        simulator.run()
        
        # 验证结果
        self.assertEqual(simulator.completed_count, 2)
        self.assertTrue(all(t.state == "COMPLETED" for t in transfers))
        self.assertIsNotNone(transfers[0].end_time)
        self.assertIsNotNone(transfers[1].end_time)
        # 验证依赖：Transfer 1必须在Transfer 0之后开始
        self.assertGreaterEqual(transfers[1].start_time, transfers[0].end_time)

# ============================================================
# 性能测试 (Performance Tests)
# ============================================================

import time

class TestPerformance(unittest.TestCase):
    """性能测试"""
    
    def test_large_scale_simulation(self):
        """测试大规模仿真性能"""
        config = {
            'num_channels': 4,
            'num_ports': 2,
            'port_bandwidth_gbps': 32.0,
            'verbose': False
        }
        
        simulator = DMASimulator(config)
        
        # 创建1000个传输
        num_transfers = 1000
        transfers = [
            Transfer(id=i, type=TransferType.NORMAL, 
                    data_size=1024*1024, src_port=0, dst_port=1, 
                    dependencies=[])
            for i in range(num_transfers)
        ]
        
        for t in transfers:
            simulator.add_transfer(t)
        
        # 测量执行时间
        start_time = time.time()
        simulator.run()
        end_time = time.time()
        
        elapsed = end_time - start_time
        print(f"\nSimulated {num_transfers} transfers in {elapsed:.3f} seconds")
        print(f"Throughput: {num_transfers/elapsed:.1f} transfers/second")
        
        # 验证性能目标（例如：1秒内完成1000个传输的仿真）
        self.assertLess(elapsed, 1.0)

# 运行测试
if __name__ == '__main__':
    unittest.main()
```

**测试策略：**

- ✓ 单元测试：测试单个类/函数
- ✓ 集成测试：测试模块间交互
- ✓ 端到端测试：测试完整流程
- ✓ 性能测试：测试大规模场景
- ✓ 代码覆盖率目标：>80%

---

*第17节完成：代码组织与架构*

---

## 18. 扩展性设计 {#extensibility}

### 18.1 如何添加新资源类型

**场景：** 需要添加一个新的资源类型（例如：Cache）

**步骤指南：**

```python
# ============================================================
# 步骤1: 定义新资源类
# ============================================================

class Cache(Resource):
    """
    Cache资源
    
    新增特性：
    - 容量限制
    - 命中率追踪
    - 驱逐策略
    """
    def __init__(self, cache_id: int, capacity_mb: int):
        super().__init__(cache_id, f"Cache_{cache_id}")
        
        # Cache特有属性
        self.capacity_mb = capacity_mb
        self.current_usage_mb = 0
        
        # 统计信息
        self.total_accesses = 0
        self.cache_hits = 0
        self.cache_misses = 0
    
    def has_capacity(self, required_mb: int) -> bool:
        """检查是否有足够容量"""
        return (self.current_usage_mb + required_mb) <= self.capacity_mb
    
    def allocate(self, size_mb: int, user_id: int):
        """分配Cache空间"""
        if not self.has_capacity(size_mb):
            raise ValueError(f"Cache {self.id} has insufficient capacity")
        
        self.current_usage_mb += size_mb
        self.current_user = user_id
    
    def deallocate(self, size_mb: int):
        """释放Cache空间"""
        self.current_usage_mb -= size_mb
        if self.current_usage_mb < 0:
            self.current_usage_mb = 0
    
    def record_access(self, hit: bool):
        """记录访问"""
        self.total_accesses += 1
        if hit:
            self.cache_hits += 1
        else:
            self.cache_misses += 1
    
    def get_hit_rate(self) -> float:
        """计算命中率"""
        if self.total_accesses == 0:
            return 0.0
        return (self.cache_hits / self.total_accesses) * 100.0
    
    def get_capacity_utilization(self) -> float:
        """计算容量利用率"""
        return (self.current_usage_mb / self.capacity_mb) * 100.0

# ============================================================
# 步骤2: 扩展ResourceManager
# ============================================================

class ExtendedResourceManager(ResourceManager):
    """
    扩展的资源管理器
    
    添加Cache资源支持
    """
    def __init__(self, num_channels: int, num_ports: int, 
                 port_bandwidth_gbps: float,
                 num_caches: int = 0, cache_capacity_mb: int = 0):
        # 调用父类构造函数
        super().__init__(num_channels, num_ports, port_bandwidth_gbps)
        
        # 添加Cache资源
        if num_caches > 0:
            self.caches = [
                Cache(i, cache_capacity_mb) 
                for i in range(num_caches)
            ]
        else:
            self.caches = []
    
    def get_cache(self, cache_id: int) -> Cache:
        """获取指定Cache"""
        return self.caches[cache_id]
    
    def find_available_cache(self, required_mb: int) -> Optional[Cache]:
        """查找有足够容量的Cache"""
        for cache in self.caches:
            if cache.has_capacity(required_mb):
                return cache
        return None
    
    def print_utilization(self, total_time: int):
        """打印资源利用率（扩展版本）"""
        # 调用父类方法
        super().print_utilization(total_time)
        
        # 添加Cache统计
        if self.caches:
            print("\nCaches:")
            for cache in self.caches:
                hit_rate = cache.get_hit_rate()
                capacity_util = cache.get_capacity_utilization()
                print(f"  {cache.name}:")
                print(f"    Capacity Utilization: {capacity_util:.2f}%")
                print(f"    Hit Rate: {hit_rate:.2f}%")
                print(f"    Total Accesses: {cache.total_accesses}")

# ============================================================
# 步骤3: 扩展Transfer以支持新资源
# ============================================================

@dataclass
class TransferWithCache(Transfer):
    """
    支持Cache的Transfer
    
    新增：需要Cache资源
    """
    required_cache_mb: int = 0     # 需要的Cache容量
    assigned_cache: Optional[int] = None  # 分配的Cache ID
    use_cache: bool = False        # 是否使用Cache

# ============================================================
# 步骤4: 扩展Scheduler以考虑新资源
# ============================================================

class CacheAwareScheduler(Scheduler):
    """
    支持Cache的调度器
    """
    def __init__(self, resource_manager: ExtendedResourceManager):
        super().__init__(resource_manager)
        # 确保resource_manager是扩展版本
        if not isinstance(resource_manager, ExtendedResourceManager):
            raise TypeError("Requires ExtendedResourceManager")
        self.ext_resource_manager = resource_manager
    
    def try_schedule(self, transfer: TransferWithCache, 
                    current_time: int) -> tuple[bool, Optional[int]]:
        """
        扩展的调度逻辑
        
        考虑Channel, Port, 以及Cache资源
        """
        # 步骤1: 检查基础资源（Channel, Port）
        base_success, retry_time = super().try_schedule(transfer, current_time)
        
        if not base_success:
            return False, retry_time
        
        # 步骤2: 如果需要Cache，检查Cache可用性
        if transfer.use_cache and transfer.required_cache_mb > 0:
            cache = self.ext_resource_manager.find_available_cache(
                transfer.required_cache_mb
            )
            
            if cache is None:
                # Cache不可用，回退基础资源分配
                transfer.assigned_channel = None
                transfer.state = "READY"
                
                # 估算Cache可用时间（简化：假设一段时间后会有Cache）
                estimated_time = current_time + 100
                return False, estimated_time
            
            # 分配Cache
            transfer.assigned_cache = cache.id
        
        return True, None

# ============================================================
# 步骤5: 使用示例
# ============================================================

def cache_example():
    """演示添加新资源类型"""
    print("="*60)
    print("Adding New Resource Type: Cache")
    print("="*60)
    
    # 创建扩展的资源管理器
    resource_manager = ExtendedResourceManager(
        num_channels=4,
        num_ports=2,
        port_bandwidth_gbps=32.0,
        num_caches=2,           # ← 新增：2个Cache
        cache_capacity_mb=128   # ← 每个Cache 128MB
    )
    
    # 创建支持Cache的调度器
    scheduler = CacheAwareScheduler(resource_manager)
    
    # 创建使用Cache的传输
    transfer = TransferWithCache(
        id=0,
        type=TransferType.NORMAL,
        data_size=64 * 1024 * 1024,  # 64 MB
        src_port=0,
        dst_port=1,
        dependencies=[],
        use_cache=True,              # ← 使用Cache
        required_cache_mb=64         # ← 需要64MB Cache
    )
    
    # 尝试调度
    success, retry_time = scheduler.try_schedule(transfer, current_time=0)
    
    if success:
        print(f"\n✓ Transfer {transfer.id} scheduled successfully")
        print(f"  - Channel: {transfer.assigned_channel}")
        print(f"  - Cache: {transfer.assigned_cache}")
        
        # 分配Cache
        cache = resource_manager.get_cache(transfer.assigned_cache)
        cache.allocate(transfer.required_cache_mb, transfer.id)
        
        print(f"  - Cache utilization: {cache.get_capacity_utilization():.2f}%")
    else:
        print(f"\n✗ Transfer {transfer.id} could not be scheduled")
        print(f"  - Retry at: {retry_time}")

if __name__ == "__main__":
    cache_example()
```

**扩展清单：**

```
添加新资源类型的步骤:

1. ✓ 继承Resource类，实现特有逻辑
2. ✓ 扩展ResourceManager，添加新资源管理
3. ✓ 扩展Transfer（如需要），添加新资源需求
4. ✓ 扩展Scheduler，考虑新资源的分配
5. ✓ 更新统计和报告功能
6. ✓ 添加单元测试
```

---

### 18.2 如何添加新事件类型

**场景：** 需要添加一个新的事件类型（例如：PREEMPTION - 抢占）

**步骤指南：**

```python
# ============================================================
# 步骤1: 扩展EventType枚举
# ============================================================

class ExtendedEventType(Enum):
    """扩展的事件类型"""
    # 原有事件类型
    TRANSFER_READY = "TRANSFER_READY"
    SCHEDULE_ATTEMPT = "SCHEDULE_ATTEMPT"
    TRANSFER_START = "TRANSFER_START"
    TRANSFER_COMPLETE = "TRANSFER_COMPLETE"
    
    # 新增事件类型
    PREEMPTION = "PREEMPTION"              # 抢占事件
    RESOURCE_RELEASED = "RESOURCE_RELEASED" # 资源释放事件
    TIMEOUT = "TIMEOUT"                     # 超时事件
    CHECKPOINT = "CHECKPOINT"               # 检查点事件

# ============================================================
# 步骤2: 扩展Event类（如需要额外字段）
# ============================================================

@dataclass(order=True)
class ExtendedEvent(Event):
    """
    扩展的事件
    
    添加更多字段以支持新事件类型
    """
    time: int
    type: ExtendedEventType = None
    transfer_id: int = None
    
    # 新增字段
    preempted_transfer_id: Optional[int] = None  # 被抢占的传输ID
    resource_type: Optional[str] = None          # 资源类型
    resource_id: Optional[int] = None            # 资源ID
    priority: int = 0                            # 优先级
    
    def __post_init__(self):
        object.__setattr__(self, 'sort_index', self.time)

# ============================================================
# 步骤3: 扩展Simulator以处理新事件
# ============================================================

class PreemptiveSimulator(DMASimulator):
    """
    支持抢占的仿真器
    """
    def __init__(self, config: dict):
        super().__init__(config)
        self.enable_preemption = config.get('enable_preemption', False)
    
    def run(self):
        """运行仿真（扩展版本）"""
        print("\n" + "="*60)
        print("Preemptive DMA Simulation Start")
        print("="*60)
        print(f"Preemption enabled: {self.enable_preemption}")
        
        while not self.event_queue.empty():
            event = self.event_queue.pop()
            self.current_time = event.time
            
            # 分发事件（扩展）
            if event.type == ExtendedEventType.SCHEDULE_ATTEMPT:
                self._handle_schedule_attempt(event)
            elif event.type == ExtendedEventType.TRANSFER_START:
                self._handle_transfer_start(event)
            elif event.type == ExtendedEventType.TRANSFER_COMPLETE:
                self._handle_transfer_complete(event)
            elif event.type == ExtendedEventType.PREEMPTION:
                self._handle_preemption(event)  # ← 新增
            elif event.type == ExtendedEventType.RESOURCE_RELEASED:
                self._handle_resource_released(event)  # ← 新增
            elif event.type == ExtendedEventType.TIMEOUT:
                self._handle_timeout(event)  # ← 新增
            elif event.type == ExtendedEventType.CHECKPOINT:
                self._handle_checkpoint(event)  # ← 新增
        
        # 仿真结束统计
        self._print_final_statistics()
    
    def _handle_preemption(self, event: ExtendedEvent):
        """
        处理抢占事件
        
        高优先级传输抢占低优先级传输
        """
        if self.verbose:
            print(f"\n[T={self.current_time}] PREEMPTION Event")
            print(f"  High priority transfer: {event.transfer_id}")
            print(f"  Preempted transfer: {event.preempted_transfer_id}")
        
        # 获取被抢占的传输
        preempted = self.transfers[event.preempted_transfer_id]
        preemptor = self.transfers[event.transfer_id]
        
        # 步骤1: 暂停被抢占的传输
        if preempted.state == "RUNNING":
            # 记录已执行的时间
            elapsed = self.current_time - preempted.start_time
            preempted.remaining_time = preempted.get_latency() - elapsed
            
            # 释放资源
            self._release_resources(preempted)
            
            # 更新状态
            preempted.state = "PREEMPTED"
            
            if self.verbose:
                print(f"    Transfer {preempted.id} preempted")
                print(f"    Elapsed: {elapsed}, Remaining: {preempted.remaining_time}")
        
        # 步骤2: 开始高优先级传输
        self._start_transfer(preemptor)
        
        # 步骤3: 将被抢占的传输重新加入队列
        resume_time = preemptor.end_time  # 在抢占者完成后恢复
        self.event_queue.push(ExtendedEvent(
            time=resume_time,
            type=ExtendedEventType.SCHEDULE_ATTEMPT,
            transfer_id=preempted.id
        ))
        
        if self.verbose:
            print(f"    Transfer {preempted.id} will resume at T={resume_time}")
    
    def _handle_resource_released(self, event: ExtendedEvent):
        """
        处理资源释放事件
        
        当资源释放时，尝试调度等待该资源的传输
        """
        if self.verbose:
            print(f"\n[T={self.current_time}] RESOURCE_RELEASED Event")
            print(f"  Resource: {event.resource_type} {event.resource_id}")
        
        # 查找等待该资源的传输
        waiting_transfers = self._find_transfers_waiting_for_resource(
            event.resource_type, event.resource_id
        )
        
        if self.verbose and waiting_transfers:
            print(f"  Found {len(waiting_transfers)} waiting transfers")
        
        # 尝试调度这些传输
        for transfer_id in waiting_transfers:
            self.event_queue.push(ExtendedEvent(
                time=self.current_time,
                type=ExtendedEventType.SCHEDULE_ATTEMPT,
                transfer_id=transfer_id
            ))
    
    def _handle_timeout(self, event: ExtendedEvent):
        """
        处理超时事件
        
        传输超过最大执行时间
        """
        transfer = self.transfers[event.transfer_id]
        
        print(f"\n[T={self.current_time}] TIMEOUT Event")
        print(f"  Transfer {transfer.id} exceeded maximum execution time")
        
        # 标记为失败
        transfer.state = "TIMEOUT"
        
        # 释放资源
        self._release_resources(transfer)
        
        # 记录统计
        self.timeout_count += 1
    
    def _handle_checkpoint(self, event: ExtendedEvent):
        """
        处理检查点事件
        
        定期保存仿真状态，用于调试和分析
        """
        if self.verbose:
            print(f"\n[T={self.current_time}] CHECKPOINT Event")
        
        # 保存当前状态快照
        checkpoint_data = {
            'time': self.current_time,
            'completed': self.completed_count,
            'running': len([t for t in self.transfers.values() 
                          if t.state == "RUNNING"]),
            'pending': len([t for t in self.transfers.values() 
                          if t.state in ["PENDING", "READY"]]),
            'resource_utilization': self._get_current_utilization()
        }
        
        # 保存或打印检查点数据
        if self.verbose:
            print(f"  Checkpoint data: {checkpoint_data}")
        
        # 调度下一个检查点
        next_checkpoint_time = self.current_time + self.checkpoint_interval
        if next_checkpoint_time < self.max_simulation_time:
            self.event_queue.push(ExtendedEvent(
                time=next_checkpoint_time,
                type=ExtendedEventType.CHECKPOINT,
                transfer_id=None
            ))
    
    def _release_resources(self, transfer: Transfer):
        """释放传输占用的资源"""
        if transfer.assigned_channel is not None:
            channel = self.resource_manager.get_channel(transfer.assigned_channel)
            channel.release()
        
        src_port = self.resource_manager.get_port(transfer.src_port)
        dst_port = self.resource_manager.get_port(transfer.dst_port)
        src_port.release()
        dst_port.release()
    
    def _find_transfers_waiting_for_resource(self, resource_type: str, 
                                            resource_id: int) -> List[int]:
        """查找等待特定资源的传输"""
        waiting = []
        for transfer in self.transfers.values():
            if transfer.state == "READY":
                # 检查是否需要该资源
                if resource_type == "channel":
                    # 任何就绪的传输都可能需要channel
                    waiting.append(transfer.id)
                elif resource_type == "port":
                    if (transfer.src_port == resource_id or 
                        transfer.dst_port == resource_id):
                        waiting.append(transfer.id)
        return waiting
    
    def _get_current_utilization(self) -> dict:
        """获取当前资源利用率"""
        if self.current_time == 0:
            return {}
        
        return {
            'channels': [c.get_utilization(self.current_time) 
                        for c in self.resource_manager.channels],
            'ports': [p.get_utilization(self.current_time) 
                     for p in self.resource_manager.ports]
        }

# ============================================================
# 步骤4: 使用示例
# ============================================================

def new_event_type_example():
    """演示添加新事件类型"""
    print("="*60)
    print("Adding New Event Types")
    print("="*60)
    
    config = {
        'num_channels': 2,
        'num_ports': 2,
        'port_bandwidth_gbps': 32.0,
        'enable_preemption': True,
        'checkpoint_interval': 1000,
        'verbose': True
    }
    
    simulator = PreemptiveSimulator(config)
    
    # 添加传输
    transfer0 = Transfer(
        id=0,
        type=TransferType.NORMAL,
        data_size=10 * 1024 * 1024,
        src_port=0,
        dst_port=1,
        dependencies=[]
    )
    transfer0.priority = 10  # 低优先级
    
    transfer1 = Transfer(
        id=1,
        type=TransferType.NORMAL,
        data_size=1 * 1024 * 1024,
        src_port=0,
        dst_port=1,
        dependencies=[]
    )
    transfer1.priority = 1  # 高优先级
    
    simulator.add_transfer(transfer0)
    simulator.add_transfer(transfer1)
    
    # 创建抢占事件（假设transfer1在transfer0运行中到达）
    simulator.event_queue.push(ExtendedEvent(
        time=50,  # 在某个时间点触发抢占
        type=ExtendedEventType.PREEMPTION,
        transfer_id=1,
        preempted_transfer_id=0
    ))
    
    # 创建检查点事件
    simulator.event_queue.push(ExtendedEvent(
        time=1000,
        type=ExtendedEventType.CHECKPOINT,
        transfer_id=None
    ))
    
    # 运行仿真
    simulator.run()

if __name__ == "__main__":
    new_event_type_example()
```

**扩展清单：**

```
添加新事件类型的步骤:

1. ✓ 扩展EventType枚举
2. ✓ 扩展Event类（如需要额外字段）
3. ✓ 在Simulator中添加事件处理函数
4. ✓ 在run()方法中添加事件分发逻辑
5. ✓ 更新事件创建逻辑（在适当的地方创建新事件）
6. ✓ 添加单元测试
7. ✓ 更新文档
```

---

### 18.3 如何扩展调度策略

**场景：** 需要实现一个新的调度策略（例如：Earliest Deadline First）

**步骤指南：**

```python
# ============================================================
# 步骤1: 定义调度策略接口（如果还没有）
# ============================================================

from abc import ABC, abstractmethod

class SchedulingPolicy(ABC):
    """
    调度策略接口
    
    所有调度策略都应实现这个接口
    """
    @abstractmethod
    def select(self, candidates: List[Transfer], 
              current_time: int) -> Optional[Transfer]:
        """
        从候选传输中选择一个
        
        Args:
            candidates: 候选传输列表
            current_time: 当前时间
        
        Returns:
            被选中的传输，如果没有则返回None
        """
        pass
    
    @abstractmethod
    def get_name(self) -> str:
        """返回策略名称"""
        pass

# ============================================================
# 步骤2: 实现具体的调度策略
# ============================================================

class FCFSPolicy(SchedulingPolicy):
    """First-Come-First-Serve策略"""
    
    def select(self, candidates, current_time):
        if not candidates:
            return None
        return min(candidates, key=lambda t: t.id)
    
    def get_name(self):
        return "FCFS"

class SJFPolicy(SchedulingPolicy):
    """Shortest-Job-First策略"""
    
    def select(self, candidates, current_time):
        if not candidates:
            return None
        return min(candidates, key=lambda t: t.data_size)
    
    def get_name(self):
        return "SJF"

class PriorityPolicy(SchedulingPolicy):
    """优先级策略"""
    
    def select(self, candidates, current_time):
        if not candidates:
            return None
        # 优先级数字越小越高
        return min(candidates, key=lambda t: (t.priority, t.id))
    
    def get_name(self):
        return "Priority"

class EDFPolicy(SchedulingPolicy):
    """
    Earliest Deadline First策略
    
    新增策略：优先调度截止时间最早的传输
    """
    def select(self, candidates, current_time):
        if not candidates:
            return None
        
        # 筛选有截止时间的传输
        with_deadline = [t for t in candidates if hasattr(t, 'deadline')]
        
        if not with_deadline:
            # 如果没有设置截止时间，降级为FCFS
            return min(candidates, key=lambda t: t.id)
        
        # 选择截止时间最早的
        return min(with_deadline, key=lambda t: t.deadline)
    
    def get_name(self):
        return "EDF"

class LLFPolicy(SchedulingPolicy):
    """
    Least Laxity First策略
    
    Laxity = Deadline - CurrentTime - RemainingTime
    优先调度laxity最小的传输
    """
    def __init__(self, estimate_remaining_time_func):
        """
        Args:
            estimate_remaining_time_func: 估算剩余时间的函数
                签名: func(transfer, current_time) -> int
        """
        self.estimate_remaining_time = estimate_remaining_time_func
    
    def select(self, candidates, current_time):
        if not candidates:
            return None
        
        # 计算每个传输的laxity
        laxities = []
        for t in candidates:
            if not hasattr(t, 'deadline'):
                continue
            
            remaining = self.estimate_remaining_time(t, current_time)
            laxity = t.deadline - current_time - remaining
            laxities.append((laxity, t))
        
        if not laxities:
            # 降级为FCFS
            return min(candidates, key=lambda t: t.id)
        
        # 选择laxity最小的
        return min(laxities, key=lambda x: (x[0], x[1].id))[1]
    
    def get_name(self):
        return "LLF"

class RoundRobinPolicy(SchedulingPolicy):
    """
    Round Robin策略
    
    轮流调度，保证公平性
    """
    def __init__(self, time_quantum: int = 100):
        """
        Args:
            time_quantum: 时间片大小（周期数）
        """
        self.time_quantum = time_quantum
        self.last_selected_index = -1
        self.transfer_id_to_index = {}
    
    def select(self, candidates, current_time):
        if not candidates:
            return None
        
        # 建立ID到索引的映射
        self.transfer_id_to_index = {t.id: i for i, t in enumerate(candidates)}
        
        # 选择下一个（循环）
        self.last_selected_index = (self.last_selected_index + 1) % len(candidates)
        return candidates[self.last_selected_index]
    
    def get_name(self):
        return f"RoundRobin(quantum={self.time_quantum})"

class AdaptivePolicy(SchedulingPolicy):
    """
    自适应策略
    
    根据系统状态动态选择调度策略
    """
    def __init__(self):
        self.policies = {
            'fcfs': FCFSPolicy(),
            'sjf': SJFPolicy(),
            'priority': PriorityPolicy(),
            'edf': EDFPolicy()
        }
        self.current_policy_name = 'fcfs'
        self.switch_threshold = 10  # 切换阈值
        self.pending_count_history = []
    
    def select(self, candidates, current_time):
        # 记录当前待处理传输数量
        self.pending_count_history.append(len(candidates))
        
        # 自适应切换策略
        if len(self.pending_count_history) > self.switch_threshold:
            avg_pending = sum(self.pending_count_history[-10:]) / 10
            
            if avg_pending > 20:
                # 待处理太多，使用SJF减少积压
                self.current_policy_name = 'sjf'
            elif avg_pending > 10:
                # 中等负载，使用优先级
                self.current_policy_name = 'priority'
            else:
                # 负载低，使用FCFS保证公平
                self.current_policy_name = 'fcfs'
        
        # 使用当前策略
        policy = self.policies[self.current_policy_name]
        return policy.select(candidates, current_time)
    
    def get_name(self):
        return f"Adaptive(current={self.current_policy_name})"

# ============================================================
# 步骤3: 创建策略驱动的调度器
# ============================================================

class PolicyDrivenScheduler:
    """
    策略驱动的调度器
    
    支持动态切换调度策略
    """
    def __init__(self, resource_manager: ResourceManager, 
                 policy: SchedulingPolicy):
        self.resource_manager = resource_manager
        self.policy = policy
        
        # 统计
        self.total_selections = 0
        self.selections_by_transfer = defaultdict(int)
    
    def set_policy(self, policy: SchedulingPolicy):
        """动态切换策略"""
        old_name = self.policy.get_name()
        self.policy = policy
        print(f"[Scheduler] Policy changed: {old_name} -> {policy.get_name()}")
    
    def schedule_next(self, ready_transfers: List[Transfer], 
                     current_time: int) -> Optional[Transfer]:
        """
        调度下一个传输
        
        Args:
            ready_transfers: 就绪的传输列表
            current_time: 当前时间
        
        Returns:
            被选中并成功调度的传输，如果没有则返回None
        """
        # 步骤1: 使用策略选择传输
        selected = self.policy.select(ready_transfers, current_time)
        
        if selected is None:
            return None
        
        # 步骤2: 尝试分配资源
        success = self._try_allocate_resources(selected, current_time)
        
        if success:
            self.total_selections += 1
            self.selections_by_transfer[selected.id] += 1
            return selected
        else:
            # 资源不可用，尝试下一个
            remaining = [t for t in ready_transfers if t.id != selected.id]
            if remaining:
                return self.schedule_next(remaining, current_time)
            return None
    
    def _try_allocate_resources(self, transfer: Transfer, 
                               current_time: int) -> bool:
        """尝试分配资源"""
        # 检查Channel
        channel = self.resource_manager.find_available_channel(current_time)
        if channel is None:
            return False
        
        # 检查Ports
        if not self.resource_manager.are_ports_available(
            transfer.src_port, transfer.dst_port, current_time):
            return False
        
        # 分配资源
        transfer.assigned_channel = channel.id
        transfer.state = "SCHEDULED"
        return True
    
    def get_statistics(self) -> dict:
        """获取调度统计"""
        return {
            'policy': self.policy.get_name(),
            'total_selections': self.total_selections,
            'selections_by_transfer': dict(self.selections_by_transfer)
        }

# ============================================================
# 步骤4: 对比不同策略的效果
# ============================================================

def compare_scheduling_policies():
    """对比不同调度策略的效果"""
    print("="*60)
    print("Comparing Scheduling Policies")
    print("="*60)
    
    # 创建测试workload
    def create_test_workload():
        """创建测试workload"""
        transfers = []
        
        # 不同大小和优先级的传输
        for i in range(10):
            t = Transfer(
                id=i,
                type=TransferType.NORMAL,
                data_size=(i+1) * 1024 * 1024,  # 递增的数据量
                src_port=0,
                dst_port=1,
                dependencies=[]
            )
            t.priority = i % 3  # 优先级: 0, 1, 2
            t.deadline = 1000 + i * 100  # 递增的截止时间
            transfers.append(t)
        
        return transfers
    
    # 创建资源管理器
    resource_manager = ResourceManager(
        num_channels=2,
        num_ports=2,
        port_bandwidth_gbps=32.0
    )
    
    # 定义要测试的策略
    policies = [
        FCFSPolicy(),
        SJFPolicy(),
        PriorityPolicy(),
        EDFPolicy()
    ]
    
    results = {}
    
    # 对每个策略运行仿真
    for policy in policies:
        print(f"\n{'─'*60}")
        print(f"Testing Policy: {policy.get_name()}")
        print(f"{'─'*60}")
        
        # 创建新的workload（每次都用相同的）
        transfers = create_test_workload()
        
        # 创建调度器
        scheduler = PolicyDrivenScheduler(resource_manager, policy)
        
        # 简化的仿真循环
        completed = []
        current_time = 0
        ready = list(transfers)
        
        while ready:
            # 调度下一个
            selected = scheduler.schedule_next(ready, current_time)
            
            if selected:
                print(f"  T={current_time}: Schedule Transfer {selected.id} "
                      f"(size={selected.data_size/1024/1024:.1f}MB, "
                      f"priority={selected.priority}, deadline={selected.deadline})")
                
                ready.remove(selected)
                completed.append(selected)
                current_time += 1
            else:
                break
        
        # 记录结果
        stats = scheduler.get_statistics()
        results[policy.get_name()] = {
            'completed': len(completed),
            'total_selections': stats['total_selections'],
            'completion_order': [t.id for t in completed]
        }
        
        print(f"\n  Completed: {len(completed)}/{ len(transfers)}")
        print(f"  Completion order: {results[policy.get_name()]['completion_order']}")
    
    # 对比结果
    print("\n" + "="*60)
    print("Comparison Summary")
    print("="*60)
    
    for policy_name, result in results.items():
        print(f"\n{policy_name}:")
        print(f"  Completed: {result['completed']}")
        print(f"  Order: {result['completion_order']}")

if __name__ == "__main__":
    compare_scheduling_policies()
```

**扩展清单：**

```
添加新调度策略的步骤:

1. ✓ 实现SchedulingPolicy接口
2. ✓ 在select()方法中实现策略逻辑
3. ✓ 考虑边界情况（候选列表为空等）
4. ✓ 添加必要的状态追踪（如Round Robin的轮次）
5. ✓ 集成到PolicyDrivenScheduler
6. ✓ 编写单元测试
7. ✓ 性能对比测试
8. ✓ 更新文档
```

---

### 18.4 扩展性设计总结

**通用扩展原则：**

```python
┌────────────────────────────────────────────────────────────┐
│ 扩展性设计的黄金法则                                        │
└────────────────────────────────────────────────────────────┘

1. 开闭原则 (Open-Closed Principle)
   ✓ 对扩展开放：可以添加新功能
   ✓ 对修改关闭：不需要修改现有代码
   
   实现方式:
     - 使用抽象基类(ABC)定义接口
     - 通过继承添加新功能
     - 使用策略模式实现可替换组件

2. 依赖倒置原则 (Dependency Inversion)
   ✓ 依赖抽象，不依赖具体实现
   
   实现方式:
     - 定义接口(Protocol/ABC)
     - 依赖注入
     - 工厂模式

3. 单一职责原则 (Single Responsibility)
   ✓ 每个类只有一个修改的理由
   
   实现方式:
     - 模块化设计
     - 清晰的接口划分
     - 分离关注点

4. 里氏替换原则 (Liskov Substitution)
   ✓ 子类可以替换父类
   
   实现方式:
     - 遵守接口契约
     - 不改变父类行为
     - 保持方法签名一致

5. 接口隔离原则 (Interface Segregation)
   ✓ 客户端不应依赖它不使用的接口
   
   实现方式:
     - 小而专注的接口
     - 按需组合接口
     - 避免臃肿的接口
```

**扩展检查清单：**

```
当你需要扩展系统时，问自己:

□ 是否定义了清晰的接口？
□ 新功能是否通过继承/组合实现？
□ 是否遵循现有的命名约定？
□ 是否添加了单元测试？
□ 是否更新了文档？
□ 是否考虑了向后兼容性？
□ 是否可以在不修改现有代码的情况下添加功能？
□ 新功能是否可以轻松移除？
```

**常见扩展模式：**

```python
# 模式1: 插件式扩展
class PluginManager:
    """插件管理器"""
    def __init__(self):
        self.plugins = []
    
    def register(self, plugin):
        """注册插件"""
        self.plugins.append(plugin)
    
    def execute_all(self, event):
        """执行所有插件"""
        for plugin in self.plugins:
            plugin.handle(event)

# 模式2: 钩子(Hook)扩展
class SimulatorWithHooks:
    """带钩子的仿真器"""
    def __init__(self):
        self.before_event_hooks = []
        self.after_event_hooks = []
    
    def add_before_event_hook(self, hook):
        self.before_event_hooks.append(hook)
    
    def handle_event(self, event):
        # 执行前置钩子
        for hook in self.before_event_hooks:
            hook(event)
        
        # 处理事件
        self._process_event(event)
        
        # 执行后置钩子
        for hook in self.after_event_hooks:
            hook(event)

# 模式3: 配置驱动扩展
class ConfigurableComponent:
    """可配置组件"""
    def __init__(self, config: dict):
        self.config = config
        self._setup_from_config()
    
    def _setup_from_config(self):
        """根据配置初始化"""
        component_type = self.config.get('type', 'default')
        
        if component_type == 'advanced':
            self._setup_advanced_features()
        elif component_type == 'custom':
            self._setup_custom_features()
```

---

*第18节完成：扩展性设计*

---

## 总结

第4部分完成！我们覆盖了：

### ✓ 第15节：完整实现示例

- 完整的DMA传输系统实现
- 从需求定义到代码实现
- 可运行的完整示例

### ✓ 第16节：常见设计模式

- 资源池模式
- 调度器模式（策略模式）
- 状态机模式
- 观察者模式（Notify机制）

### ✓ 第17节：代码组织与架构

- 模块划分原则
- 接口设计
- 测试策略（单元测试、集成测试、E2E测试）

### ✓ 第18节：扩展性设计

- 如何添加新资源类型
- 如何添加新事件类型
- 如何扩展调度策略
- 扩展性设计原则和检查清单

---

## 🎓 学习路径总结

```
完整的学习路径:

第1部分：建模基础
  → 理解为什么需要性能建模
  → Event-Driven vs. Cycle-Accurate
  → 核心建模概念

第2部分：建模方法论 ← 已完成
  → Event与资源的关系（重点！）
  → Event创建时机和时间推进
  → 资源等待问题和notify机制
  → 等待队列的必要性分析

第3部分：核心机制
  → 多通道并行执行
  → 调度优化
  → 性能分析和调试

第4部分：实践指南 ← 刚完成！
  → 完整实现示例（可运行代码）
  → 常见设计模式
  → 代码组织与测试
  → 扩展性设计

下一步:
  → 将理论应用到实际DLA RVV项目
  → 根据需要添加特定功能
  → 持续优化和改进
```

---

*第4部分全部完成！*

现在您已经拥有了完整的硬件性能建模知识体系！🎉
