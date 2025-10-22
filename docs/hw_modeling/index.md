# 硬件性能建模完整指南 - 总览

## 📚 文档体系

本学习资料提供了 **完整的、系统的硬件性能建模方法论**  。

---

## 🎯 学习目标

学完本系列文档后，您将能够：

✓ 理解event-driven建模的核心原理  
✓ 掌握资源竞争和依赖建模  
✓ 实现完整的性能模拟器  
✓ 分析和优化硬件性能  
✓ 扩展模型以支持新功能  

---

## 📖 文档结构

### 核心指南（推荐按顺序阅读）

#### Fundamentals (677行)

**文件** ：`fundamentals.md`

**内容** ：

- 为什么需要性能建模
- Event-Driven vs. Cycle-Accurate仿真
- 核心建模概念（Event, Resource, Dependency）

**适合** ：初学者，了解基本概念

---

#### Methodology: 建模方法论 ⭐️

掌握event-driven建模的核心方法，拆分为5个独立章节便于学习：

-  **Event Lifecycle**  - `event_lifecycle.md` (692行)
  - Event的6个阶段，完整示例追踪

-  **Resource Contention**  - `resource_contention.md` (566行)
  - 资源状态模型，3种竞争策略

-  **Dependency & Notify**  - `dependency_notify.md` (610行)
  - 依赖图，Notify机制，Fork-Join

-  **Event Creation & Time**  - `event_creation_time.md` (1,574行)
  - Event创建时机，时间推进机制

-  **Event-Resource Relationship**  - `event_resource_relationship.md` (1,804行) ⭐
  - Event与资源解耦（最重要！必读）

**关键概念** ：

- Event时间 ≠ 资源时间（解耦）
- Event.time = "检查时机"，不是"执行时机"
- 资源释放时间已知：直接创建 Event@busy_until
- 等待队列用于：优先级调度或动态竞争场景

---

#### Advanced Topics (1,949行)

**文件** ：`advanced_topics.md`

**内容** ：

1. 多通道并行执行
2. 调度优化策略
3.  **性能分析**  - 瓶颈识别、利用率分析
4.  **调试技巧**  - Event追踪、状态快照
5.  **模型验证**  - 时间单调性、资源一致性

**适合** ：进阶学习，优化和调试

---

#### Practical Guide (3,277行)

**文件** ：`practical_guide.md`

**内容** ：

1.  **完整实现示例**  - 完整可运行的DMA仿真器代码
2.  **常见设计模式** 
    - 资源池模式
    - 调度器模式（策略模式）
    - 状态机模式
    - 观察者模式（Notify机制）
3.  **代码组织与架构** 
    - 模块划分原则
    - 接口设计
    - 测试策略
4.  **扩展性设计** 
    - 如何添加新资源类型
    - 如何添加新事件类型
    - 如何扩展调度策略

**适合** ：实际项目开发，代码实现

---

## 🚀 学习路径

### 路径1: 快速入门（2-3小时）

```
1. 阅读 Fundamentals (30分钟)
   → 理解基本概念

2. 阅读 Event-Resource Relationship (1小时)
   → 理解Event与资源的关系（最重要！）

3. 浏览 Practical Guide 的完整示例 (30-60分钟)
   → 看完整的代码实现

4. 阅读 Event Lifecycle (30分钟)
   → 理解Event如何工作
```

### 路径2: 系统学习（1-2天）

```
Day 1:
  上午: Fundamentals
  下午: Methodology (5个章节)
  
Day 2:
  上午: Advanced Topics（性能分析与调试）
  下午: Practical Guide（实践指南）
```

### 路径3: 深度掌握（1周）

```
Week 1:
  Day 1: Fundamentals，做笔记
  Day 2-3: Methodology (5个章节)，逐章学习
  Day 4: Advanced Topics，跑示例代码
  Day 5-6: Practical Guide，实现自己的小模型
  Day 7: 应用到实际项目
```

---

## 🔑 核心要点速查

### Event与资源的关系（最易混淆）

```python
问题: Event@200，但资源在300才可用，怎么办？

答案: 解耦！
  - Event.time = "检查时机"，不是"执行时机"
  - Event@200到达 → 检查资源 → 发现不可用
  - 创建新Event@300 → Event@200消失
  - Event@300到达 → 检查资源 → 可用 → 开始执行

心智模型: Event = 闹钟 ⏰
  - 闹钟响 = 提醒检查
  - 条件不满足 = 设新闹钟
```

### 资源调度策略选择

```python
问题: 如何调度竞争同一资源的多个操作？

场景1: FIFO调度（简单，推荐）
  - 资源释放时间已知：resource.busy_until
  - 操作到达时检查资源
  - 如果被占用：创建 Event@busy_until
  - ✓ 不需要等待队列
  - ✓ 简单高效

场景2: 优先级调度（复杂）
  - 高优先级操作可以"插队"
  - 需要等待队列维护所有等待者
  - 资源释放时，从队列选择最高优先级
  - notify机制：通知被选中的操作
  
场景3: 动态调度（最复杂）
  - 调度决策依赖运行时状态
  - 需要等待队列 + 复杂调度器
  
建议: 90%的场景用FIFO，直接创建Event@busy_until即可
```

### Event创建时机

```python
原则1: 有意义的时刻才创建Event
  ✓ 资源可用时
  ✓ 操作完成时
  ✓ 依赖满足时

原则2: 一个Event = 一个原子操作
  ✓ START Event: 开始传输
  ✓ COMPLETE Event: 完成传输
  ✗ 不要: 一个Event既开始又完成

原则3: 时间推进 = Event.time
  simulator.current_time = event.time
  总是由Event驱动时间前进
```

---

## 💡 关键洞察

### 1. Event-Driven的本质

```
不是预先知道所有事情
而是在适当的时机做适当的检查

不是每个周期都检查
而是有意义的时刻才检查

不是轮询资源状态
而是等待资源通知
```

### 2. 两个时间维度

```
Event时间（虚拟时间）:
  - Event.time
  - 表示"检查时机"
  - 可以自由设置

资源时间（状态时间）:
  - Resource.busy_until
  - 表示"真实约束"
  - 反映实际占用

它们是独立的，通过"检查-决策"机制协调
```

### 3. 何时需要Notify机制

```
问题: 什么时候需要notify机制？

错误理解: 因为"不知道资源何时可用" ❌
  - 实际上，resource.busy_until 总是已知的
  - 直接创建 Event@busy_until 即可

正确理解: 因为需要"优先级调度" ✓
  例子: 
    - 资源@300释放
    - 等待队列: [Op1(低优), Op2(高优), Op3(中优)]
    - 资源释放时notify → 选择Op2(高优)
    - 创建 Event@300 for Op2
    
  关键: Notify用于"从多个等待者中选择"，不是因为"不知道时间"
  
FIFO场景不需要notify:
  - Op1占用资源 [0, 100)
  - Op2到达@50 → 检查资源 → 被占用
  - 直接创建 Event@100 for Op2 ✓
  - 不需要等待队列，不需要notify
```
