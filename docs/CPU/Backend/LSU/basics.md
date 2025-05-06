# LSU Basics
# Load Store Unit (LSU) Responsibilities

- Generate address (not fully encoded by instruction)
- Translate address (virtual to physical)
- Resolve address conflicts (i.e., dependencies through memory)
- Execute access (actual load/store)

# Challenges in Memory Access

## Challenge #1: Timing of Memory Access by Store Instructions

- When can a store actually write to the memory?
- How does it affect the order of stores?

## Challenge #2: Dependencies Through Memory

- A.k.a., memory disambiguation
- load(a) should return the value written by the latest store(a, v)
  - Will discuss multi-core issues in a later lecture
- Same set of dependencies as registers:
  - RAW: store(a, v); load(a);
  - WAW (only with OoO): store(a, v); store(a, v');
  - WAR (only with OoO): load(a); store(a, v);

## Why Dependencies Are Hard

- Memory addresses are much wider than register names
  - 5 bits vs. 64 bits
- Memory dependencies are not static
  - Address of a load (or store) instruction may change (e.g., loop)
- Addresses need to be calculated and translated first
  - Cannot do much too early
- Load/stores take longer relative to other instructions
  - Cache/TLB misses can take 100s of cycles
  - Higher cost of stalling

# Load/Store Lifetime

- Ordering between loads/stores is about the timing of accessing memory
- We call a load/store "accessed" if it has accessed the memory
  - Loads access before commit

![](attachments/Pasted%20image%2020250429203130.png)

# Options of Memory Disambiguation

| Scheme                        | Speculative? | Notes                                                                                                                                                             |
| ----------------------------- | ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Total Ordering                | No           | All loads/stores access in program order.                                                                                                                         |
| Load Ordering, Store Ordering | No           | All stores access in order. All loads access in order. But between loads and stores accesses are out of order, as long as older stores have addresses calculated. |
| Partial Ordering              | No           | All stores access in order. Loads can access out of order, as long as older stores have addresses calculated.                                                     |
| Store Ordering                | Yes          | All stores access in order. Loads access completely out of order.                                                                                                 |

# Load Ordering, Store Ordering

- Decoupled in-order pipelines for loads/stores
- Sync between loads and stores when addresses are available
  - Loads compared to older stores
  - Loads may bypass older stores if no address conflicts

![](attachments/Pasted%20image%2020250429203515.png)

> Note: This requires tracking AGE. LOAD should wait until STORE with greater AGE before accessing DCACHE.

# Partial Ordering

- Loads go Out-of-Order if older loads/stores have addresses
  - Indetermination matrix tracks readiness of address registers
 	- When to issue
  - Dependency matrix tracks dependencies
    - When to access memory

![](attachments/Pasted%20image%2020250429203659.png)

# Load Bypassing and Store Forwarding

![](attachments/Pasted%20image%2020250429204643.png)

- If loads can access memory OoO w.r.t. stores:
	- With no address conflicts:
		- stall (in-order), or
		- load bypassing (OoO)
	  - With address conflicts:
		- stall (in-order), or
		- store forwarding (OoO)
		- Store forwarding is critical for performance; otherwise conflicting loads must wait
		- Implementing store forwarding is tricky due to size and alignment concerns

## Load-Store Queue Implementation Details

- **Physical Structure**: Typically implemented as circular buffers or CAMs (Content Addressable Memory)
- **Capacity**: 32-64 entries in modern processors
- **Tracking Fields**:
	- PC value
	- Memory address (virtual and physical)
	- Data size (byte, half-word, word)
	- Execution status flags
	- Age counter for ordering

# Address Speculation

Bypassing & forwarding are still not good enough:

- Need to wait for the addresses of ALL older stores to avoid RAW hazards

Solution: Speculate lack of RAW hazard

- Predict a load to be independent of stores, without knowing exact addresses
- Proceed with the load, as well as all dependent instructions
	- Significant improvement of IPC
- If speculation found to be wrong, squash the load and all dependent instructions
	- Similar to branch misprediction recovery

## Address Prediction Techniques

- **Last Value Prediction**: Use the previous address for the same load instruction
- **Stride Prediction**: Predict based on patterns in address changes
- **Context-based Prediction**: Use history of recent addresses to predict next one

# Speculative Load Issuing

Record all speculatively issued loads in a buffer, to match with stores

- Finished = address calculated
- Completed = committed

![](attachments/Pasted%20image%2020250429205345.png)

# Selective Speculation: Motivation

- We'd better speculate wisely:
	- Difficult to predict: locality leads to non-trivial amount of conflicts
	- Difficult to recover: hard to identify only dependent instructions, usually flush all
- Selective speculation: only select profitable loads to speculate

## Store Set Algorithm

- For each load, track all stores with which it has conflicted in the past
	- These stores form the store set of this load
	- Assumption: previously encountered dependencies are likely to repeat
	- A load does not issue if any member in its store set has not resolved the address
- Store set algorithm (ideal):
	- Initially, all loads have empty store sets → naïve speculation
	- When a load and a store cause a violation, the store PC is added to the load's store set
	- When a load is encountered, it must be delayed if any store in its store set is still on-the-fly

## Replay vs. Squash Recovery

- **Replay**: Discard just the violating load and re-execute it (lightweight)
- **Squash**: Cancel the load and all dependent instructions (heavyweight but necessary for ordering)
- **Hybrid Approach**: Use replay for certain violations and squash for others


# References

- https://safari.ethz.ch/ddca/spring2025/lib/exe/fetch.php?media=onur-ddca-2025-lecture15c-load-store-handling-in-out-of-order-execution.pdf
- Chrysos, G. Z., & Emer, J. S. (1998). Memory dependence prediction using store sets. ACM SIGARCH Computer Architecture News, 26(3), 142-153.
- Yoaz, A., Erez, M., Ronen, R., & Jourdan, S. (1999). Speculation techniques for improving load related instruction scheduling. ISCA '99.
