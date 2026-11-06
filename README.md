# L1-Cache: Non-Blocking Level-1 Data Cache Subsystem

This L1 Cache is a synthesizable, 4-way set-associative non-blocking Level-1 Data Cache IP core designed for modern high-performance microprocessors (such as RISC-V or ARM cores). Written in synthesizable SystemVerilog/Verilog, the core implements **Hit-Under-Miss** and **Miss-Under-Miss** execution using a 4-entry Miss Status Holding Register (MSHR) table, reducing memory stall penalties by allowing independent cache hits to complete while main memory fetches missed cache lines over an **AMBA AXI4** bus.

---

## 1. Why Non-Blocking Caching is Critical

In traditional university processor projects, caches are strictly **blocking**: when a cache miss occurs, the entire processor pipeline is stalled for 40 to 100 clock cycles until main memory responds with the requested data. 

In real-world workloads, memory instructions often exhibit spatial and temporal independence:
- A program may miss on an array in function $A$, but immediately read local variables or stack pointers that are already cached.
- A blocking cache halts all execution on the first miss.
- **This non-blocking architecture eliminates this bottleneck** by buffering the outstanding miss in hardware (MSHR), allowing subsequent instructions to access the cache concurrently with **zero stall cycles**.

---

## 2. Microarchitecture & System Diagram

```
                              apex_cache_top (IP Core)
   ┌────────────────────────────────────────────────────────────────────────┐
   │                                                                        │
   │   CPU Core Interface                                                   │
   │   (Req Valid, Ready, Addr, WData, RData, ID)                           │
   │        │                               ▲                               │
   │        ▼                               │ 1-Cycle Hit Data Forwarding   │
   │   ┌─────────────┐             ┌────────┴────────┐                      │
   │   │  Tag Array  │             │   Data Array    │                      │
   │   │ 32 Sets x 4 │             │  4 KB (32B Line)│                      │
   │   └──────┬──────┘             └────────▲────────┘                      │
   │          │ (Hit/Miss)                  │ (Refill Line)                 │
   │          ▼                             │                               │
   │   ┌─────────────┐             ┌────────┴────────┐                      │
   │   │  Tree-PLRU  │             │   4-Entry MSHR  │                      │
   │   │ Replacement │             │ (Hit-Under-Miss)│                      │
   │   └──────┬──────┘             └────────▲────────┘                      │
   │          │ (Victim Way)                │                               │
   │          ▼                             │                               │
   │   ┌─────────────┐                      │                               │
   │   │  Writeback  │                      │                               │
   │   │ Evict Buffer│                      │                               │
   │   └──────┬──────┘                      │                               │
   │          │                             │                               │
   └──────────┼─────────────────────────────┼───────────────────────────────┘
              ▼ (Writeback Burst)           ▼ (Line Fill Burst)
   ┌────────────────────────────────────────────────────────────────────────┐
   │                       AMBA AXI4 Master Interconnect                    │
   └────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Key Hardware Innovations

### A. Non-Blocking MSHR with Secondary Miss Merging
- Implements a **4-entry Miss Status Holding Register (MSHR)** table.
- **Hit-Under-Miss**: If an incoming request hits an existing line while a previous miss is in-flight over the AXI4 bus, it is returned to the core in **1 clock cycle** with zero stall.
- **Secondary Miss Merging**: If the CPU issues subsequent read or write requests to different words within the *same cache line* already being fetched by an active MSHR, the requests are merged into the existing entry, preventing duplicate burst requests on the memory bus.

### B. Tree Pseudo-LRU (Tree-PLRU) Replacement Policy
- Standard True-LRU for 4-way caches requires complex age matrices ($O(N^2)$).
- L1-Cache implements **Tree-PLRU** with a 3-bit binary decision tree per set ($32 \times 3 = 96$ flip-flops total), determining the victim line in $O(1)$ constant time with zero arithmetic multipliers.

### C. Write-Back with Non-Blocking Dirty Eviction Buffer
- Employs a **Write-Back, Write-Allocate** policy: memory writes update cache lines locally and assert a dirty bit.
- On miss eviction, if the victim line is dirty, it is immediately latched into a dedicated **Writeback Eviction Buffer**, allowing the incoming line fill to begin immediately without waiting for the slow memory write to finish.

### D. Full AMBA AXI4 Master Burst Interface
- Issues standard 8-beat INCR bursts (`ARLEN = 7`, 32 bits per beat) for 256-bit cache line refills.
- Issues standard 8-beat INCR bursts (`AWLEN = 7`) for dirty victim writebacks.

---

## 4. Verification Suite

The repository includes a comprehensive, bit-exact verification framework:
- **Python Golden Architectural Reference** (`sim/golden_cache_model.py`):
  - Validates spatial locality (87.5% hit rate on 32-byte line sweeps).
  - Validates temporal loop reuse (100% hit rate).
  - Validates write-back store integrity.
- **Cycle-Accurate Verilog Testbench** (`sim/tb_nonblocking_cache.v`):
  - Verifies cold line fills with simulated AXI memory slave latency.
  - Verifies 1-cycle read hits and write hits.
  - **Verifies Hit-Under-Miss concurrency**: core executes hit to Address B while Address A is in-flight over AXI.
  - Verifies secondary miss merging and dirty line writebacks.

---

## 5. Physical Design & ASIC Synthesis Benchmarks

The cache controller was synthesized targeting the standard academic **Nangate 45nm Open Cell Library** ($V_{DD} = 1.1\text{ V}, T = 25^\circ\text{C}$) via the **Yosys Open Synthesis Suite**:

| Metric | Measured Silicon Value | Engineering Significance |
| :--- | :--- | :--- |
| **Total Standard Cells** | **20,497 cells** | Complete gate-level mapped controller |
| **Total Chip Silicon Area** | **$53,568.14\ \mu m^2$** | $0.0536\text{ mm}^2$ chip area on 45nm |
| **Sequential Flip-Flop Area** | **$33,165.41\ \mu m^2$** | 6,286 FFs (MSHR entries, tags, PLRU bits) |
| **Gate Equivalents (GE)** | **67,128 NAND2-X1** | Industrial-grade control complexity |
| **Max Clock Frequency ($f_{max}$)** | **400.0 MHz** | Zero critical-path arithmetic bottlenecks |

---

## 6. Project Directory Structure

```
apex-cache/
├── docs/
│   └── ARCHITECTURE.md              # Detailed microarchitecture & MSHR state machine
├── rtl/
│   ├── apex_cache_top.v             # Top-level non-blocking cache (Controller + Data SRAM)
│   ├── apex_cache_controller.v      # Standalone synthesizable ASIC controller core
│   ├── tag_array.v                  # 4-way set-associative Tag SRAM array
│   ├── data_array.v                 # 4-way 32-byte line Data SRAM array
│   ├── plru_replacement.v           # Tree Pseudo-LRU replacement logic
│   ├── mshr_table.v                 # 4-entry MSHR with hit-under-miss & secondary merging
│   ├── writeback_buffer.v           # Dirty victim line buffer for non-blocking writeback
│   └── axi4_master_interface.v      # AMBA AXI4 Master burst controller
├── sim/
│   ├── golden_cache_model.py        # Bit-exact Python reference simulator
│   ├── tb_nonblocking_cache.v       # Full Verilog testbench covering Hit-Under-Miss
│   └── apex_cache.gtkw              # Pre-loaded GTKWave waveform layout
├── synth/
│   ├── run_synth_asic.ys            # Yosys 45nm ASIC synthesis script
│   ├── run_synth_fpga.ys            # Yosys FPGA synthesis script
│   ├── nangate45.lib                # Nangate 45nm Open Cell Library
│   └── apex_cache_controller_nangate45_netlist.v # Synthesized 45nm gate netlist
├── gui_app.py                       # Native Graphical EDA Workbench
├── Launch_EDA_Workbench.bat         # 1-click launcher for GUI Workbench
├── view_waves.bat                   # 1-click GTKWave waveform launcher
└── README.md                        # Project documentation
```

---

## 7. How to Run & Verify

### Quick Start: Graphical Desktop Workbench (GUI)
Double-click [`Launch_EDA_Workbench.bat`](file:///Launch_EDA_Workbench.bat) *(or double-click the **"L1-Cache - EDA Workbench"** desktop shortcut)* to open the native graphical dashboard where you can run simulations, view waveforms, and launch synthesis with one click.

### Command Line Verification
#### 1. Run Python Reference Model
```bash
python sim/golden_cache_model.py
```

#### 2. Run Verilog Hardware Simulation
```bash
cmd /c "call C:\Users\surya\.oss-cad-suite\oss-cad-suite\environment.bat && iverilog -g2012 -o sim/tb_cache.vvp rtl/*.v sim/tb_nonblocking_cache.v && vvp sim/tb_cache.vvp"
```

#### 3. Inspect Waveforms in GTKWave
Double-click `view_waves.bat` to launch GTKWave with all core signals, MSHR status, and AXI4 transactions pre-loaded. Click **Time → Zoom → Zoom Best Fit** to view the full execution timeline.
