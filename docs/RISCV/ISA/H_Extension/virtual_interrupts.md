# 虚拟中断处理

中断虚拟化是H扩展的关键功能之一。Hypervisor需要能够拦截物理中断，并根据需要将它们"注入"到相应的Guest OS中。

## 中断处理架构

### 中断类型层次

```
物理中断源 → 物理中断控制器 → Hypervisor (HS-mode)
                                    ↓
                               虚拟中断注入
                                    ↓
                            Guest OS (VS-mode)
```

### 中断控制寄存器

**Hypervisor中断寄存器：**

-  **`hie` (Hypervisor Interrupt Enable):**  Hypervisor自己的中断使能寄存器
-  **`hip` (Hypervisor Interrupt Pending):**  Hypervisor自己的中断挂起寄存器

**Guest虚拟中断寄存器：**

-  **`vsie` (Virtual Supervisor Interrupt Enable):**  Guest OS的虚拟中断使能寄存器
-  **`vsip` (Virtual Supervisor Interrupt Pending):**  Guest OS的虚拟中断挂起寄存器

## 中断委托机制

### hideleg寄存器详解

`hideleg`控制哪些中断可以直接委托给Guest OS处理：

| 位 | 中断类型 | 委托效果 |
|----|----------|----------|
| 1  | Supervisor software interrupt | 委托后Guest可直接处理软件中断 |
| 5  | Supervisor timer interrupt | 委托后Guest可直接处理定时器中断 |
| 9  | Supervisor external interrupt | 委托后Guest可直接处理外部中断 |

### 委托 vs 非委托的区别

**委托的中断 (hideleg相应位=1):**

```
物理中断发生 → 直接路由到Guest VS-mode
              (Hypervisor完全不感知)
```

**非委托的中断 (hideleg相应位=0):**

```
物理中断发生 → 陷入Hypervisor HS-mode
              ↓
          Hypervisor处理并决定
              ↓
          可能注入虚拟中断给Guest
```

## 虚拟中断注入流程

### 完整的中断注入过程

1.  **物理中断发生** 

   ```c
   // 物理定时器中断发生，陷入HS-mode
   void physical_timer_interrupt() {
       // Hypervisor的中断处理程序被调用
   }
   ```

2.  **Hypervisor处理中断** 

   ```c
   void hypervisor_timer_handler() {
       // 确定哪个Guest应该接收这个中断
       guest_id_t target_guest = schedule_timer_interrupt();
       
       // 保存当前上下文
       save_current_context();
       
       // 注入虚拟中断到目标Guest
       inject_virtual_interrupt(target_guest, TIMER_INTERRUPT);
   }
   ```

3.  **虚拟中断注入** 

   ```c
   void inject_virtual_interrupt(guest_id_t guest, int interrupt_type) {
       // 切换到目标Guest的上下文
       switch_to_guest_context(guest);
       
       // 在Guest的vsip寄存器中设置相应的挂起位
       switch(interrupt_type) {
           case TIMER_INTERRUPT:
               csr_set(vsip, STIP_BIT);    // 设置定时器中断挂起
               break;
           case SOFTWARE_INTERRUPT:
               csr_set(vsip, SSIP_BIT);    // 设置软件中断挂起  
               break;
           case EXTERNAL_INTERRUPT:
               csr_set(vsip, SEIP_BIT);    // 设置外部中断挂起
               break;
       }
   }
   ```

4.  **Guest中断处理** 

   ```c
   // 当切换回Guest执行时：
   // 1. 硬件检查 vsip & vsie
   // 2. 发现挂起且使能的虚拟中断
   // 3. 自动触发陷阱到Guest的VS-mode
   // 4. Guest的中断处理程序被调用
   
   void guest_timer_handler() {
       // Guest OS处理定时器中断
       // 例如：进程调度、时间更新等
       
       // 清除中断挂起位
       csr_clear(vsip, STIP_BIT);
   }
   ```

## 中断优先级与仲裁

### 中断检查顺序

当处于VS或VU模式时，硬件按以下顺序检查中断：

1.  **外部中断**  (SEIP位)
2.  **软件中断**  (SSIP位)  
3.  **定时器中断**  (STIP位)

### 中断使能条件

虚拟中断的触发需要满足以下条件：

```c
// 中断触发条件
bool interrupt_enabled = 
    (vsstatus.SIE == 1) &&           // 全局中断使能
    (vsie & vsip & interrupt_mask);  // 特定中断使能且挂起

// 对于定时器中断
bool timer_interrupt_pending = 
    (vsstatus.SIE == 1) &&
    (vsie.STIE == 1) &&              // 定时器中断使能
    (vsip.STIP == 1);                // 定时器中断挂起
```

## 高级中断管理

### VGEIN机制 (Virtual Guest External Interrupt Number)

VGEIN提供了更精细的外部中断管理：

```c
// hstatus寄存器中的VGEIN字段
struct hstatus {
    uint64_t VGEIN : 6;  // 位17:12
    // 其他字段...
};

// 外部中断注入示例
void inject_external_interrupt(guest_id_t guest, int irq_number) {
    // 设置VGEIN指示特定的中断号
    hstatus.VGEIN = irq_number;
    
    // 设置外部中断挂起
    csr_set(vsip, SEIP_BIT);
    
    // 切换到Guest
    switch_to_guest(guest);
}
```

### 中断虚拟化的性能优化

1.  **中断聚合 (Interrupt Coalescing)** 

   ```c
   // 将多个物理中断聚合为单个虚拟中断
   void coalesce_interrupts() {
       if (pending_network_interrupts > THRESHOLD) {
           inject_virtual_interrupt(guest, NETWORK_INTERRUPT);
           clear_pending_network_interrupts();
       }
   }
   ```

2.  **中断负载均衡** 

   ```c
   // 在多个Guest之间均衡中断负载
   guest_id_t select_interrupt_target() {
       return find_least_loaded_guest();
   }
   ```

3.  **延迟中断注入** 

   ```c
   // 延迟注入中断直到Guest实际需要时
   void lazy_interrupt_injection() {
       if (guest_is_about_to_run(target_guest)) {
           inject_pending_interrupts(target_guest);
       }
   }
   ```

## 实际应用示例

### 网络中断处理

```c
// 物理网络中断处理
void physical_network_interrupt() {
    // 1. 读取网络数据包
    packet_t packet = read_network_packet();
    
    // 2. 确定目标Guest（基于包的目的地址）
    guest_id_t target = route_packet_to_guest(packet);
    
    // 3. 将数据包放入Guest的接收队列
    enqueue_packet_to_guest(target, packet);
    
    // 4. 注入虚拟网络中断
    inject_virtual_interrupt(target, NETWORK_INTERRUPT);
}

// Guest中的网络中断处理
void guest_network_interrupt_handler() {
    // 处理接收队列中的数据包
    while (!guest_rx_queue_empty()) {
        packet_t packet = dequeue_packet();
        process_network_packet(packet);
    }
    
    // 清除中断挂起位
    csr_clear(vsip, SEIP_BIT);
}
```

这种精细的中断虚拟化机制确保了Guest OS能够高效地处理各种中断，同时为Hypervisor提供了完整的中断管理和控制能力。
