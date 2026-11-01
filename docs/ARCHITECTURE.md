# Apex-L1Cache: Microarchitecture & Hardware Specification

## 1. Architectural Overview

**Apex-L1Cache** is a synthesizable, 4-way set-associative non-blocking L1 Data Cache controller with a 4-entry Miss Status Holding Register (MSHR) table, Tree Pseudo-LRU replacement, and AMBA AXI4 master burst interface.

```
                  ┌──────────────────────────────────────────────┐
                  │                 CPU CORE                     │
                  └──────┬────────────────────────────────▲──────┘
      Core Request Valid │                                │ Core Response Valid
      Addr, Data, WStrb  │                                │ 32-bit Word Data
                         ▼                                │
                 ┌────────────────────────────────────────┴──────┐
                 │                APEX-L1CACHE                   │
                 │                                               │
                 │  ┌──────────────┐          ┌───────────────┐  │
                 │  │  Tag Array   │          │  Data Array   │  │
                 │  │ (32 Sets x 4)│          │ (32 Sets x 4) │  │
                 │  └──────┬───────┘          └───────▲───────┘  │
                 │         │ (Hit / Miss)             │          │
                 │         ▼                          │          │
                 │  ┌──────────────┐          ┌───────┴───────┐  │
                 │  │  Tree-PLRU   │          │  4-Entry MSHR │  │
                 │  │ Replacement  │          │ (Hit-under-   │  │
                 │  └──────┬───────┘          │     Miss)     │  │
                 │         │ (Victim Way)     └───────▲───────┘  │
                 │         ▼                          │          │
                 │  ┌──────────────┐                  │          │
                 │  │  Writeback   │                  │          │
                 │  │ Dirty Buffer ├────────┐         │          │
                 │  └──────────────┘        │         │          │
                 └──────────────────────────┼─────────┼──────────┘
                               Write Bursts │         │ Read Bursts
                                            ▼         ▼
                  ┌──────────────────────────────────────────────┐
                  │           AMBA AXI4 Interconnect / L2        │
                  └──────────────────────────────────────────────┘
```

---

## 2. Memory Organization & Addressing

For a 32-bit physical address space:

```
  31                                  10 9       5 4     2 1   0
 ┌──────────────────────────────────────┬─────────┬───────┬─────┐
 │             TAG (22 bits)            │SET (5 b)│WORD(3)│BYTE │
 └──────────────────────────────────────┴─────────┴───────┴─────┘
```

- **Cache Capacity**: 4,096 bytes (4 KB).
- **Line Size**: 32 bytes (256 bits = 8 words of 32 bits).
- **Associativity**: 4 Ways.
- **Sets**: 32 Sets ($2^5 = 32$).
- **Tag**: 22 bits (`addr[31:10]`).
- **Set Index**: 5 bits (`addr[9:5]`).
- **Word Offset**: 3 bits (`addr[4:2]`).
- **Byte Offset**: 2 bits (`addr[1:0]`).

---

## 3. Submodule Specifications

### 3.1 Tag Array (`tag_array.v`)
- Stores $32 \text{ sets} \times 4 \text{ ways} = 128 \text{ tags}$ (22 bits each).
- Integrated metadata:
  - `Valid bit` (1 bit per line).
  - `Dirty bit` (1 bit per line).
- Parallel 4-way comparator evaluates hit condition combinational match.

### 3.2 Tree Pseudo-LRU Replacement (`plru_replacement.v`)
- Uses a 3-bit decision tree per set:
  - $b_0$: points to left (ways 0, 1) or right (ways 2, 3) pair.
  - $b_1$: points to way 0 or way 1.
  - $b_2$: points to way 2 or way 3.
- On each cache hit or line fill, arrows are updated to point *away* from the accessed way.
- On miss eviction, the tree selects the least-recently-accessed way in $O(1)$ constant time with zero arithmetic multipliers.

### 3.3 Miss Status Holding Registers (`mshr_table.v`)
- Enables non-blocking operation:
  - **Hit-Under-Miss**: While a memory line fill is in-flight over the AXI4 bus, the core can continue executing hits to other addresses in 1 cycle.
  - **Secondary Miss Merging**: If the core requests another word from the *same line* already being fetched by an active MSHR, it merges into the entry instead of issuing a redundant bus transaction.
  - Tracks up to 4 concurrent outstanding misses before backpressuring the core.

### 3.4 Writeback Eviction Buffer (`writeback_buffer.v`)
- Latches dirty victim lines during miss allocation in 1 cycle.
- Backgrounds the memory writeback burst so the incoming line fill can start immediately without stalling.

### 3.5 AMBA AXI4 Master Controller (`axi4_master_interface.v`)
- Issues standard 8-beat INCR bursts (`ARLEN = 7`, `AXSIZE = 010`, 32 bits per beat) for 256-bit line fills.
- Issues standard 8-beat INCR write bursts (`AWLEN = 7`) for dirty victim evictions.
