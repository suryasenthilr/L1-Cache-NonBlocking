"""
Apex-L1Cache EDA Control Center
Graphical User Interface for Simulation, Synthesis, and Waveform Analysis
Targeting High-Performance Non-Blocking L1 Data Cache IP Core.
"""

import sys
import os
import subprocess
import threading
import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox

ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
OSS_CAD_DIR = r"C:\Users\surya\.oss-cad-suite\oss-cad-suite"
ENV_BAT = os.path.join(OSS_CAD_DIR, "environment.bat")

class ApexCacheEDAApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Apex-L1Cache EDA Control Center - Silicon Workbench")
        self.geometry("980x720")
        self.minsize(800, 600)
        self.configure(bg="#1e1e2e")

        self.style = ttk.Style(self)
        self.style.theme_use("clam")
        self._configure_styles()

        self._build_header()
        self._build_main_layout()
        self._build_status_bar()

        self.log("Apex-L1Cache EDA Workbench Initialized.")
        self.log(f"Project Directory : {ROOT_DIR}")
        self.log(f"OSS CAD Suite Path: {OSS_CAD_DIR}")
        self.log("Architecture: 4-Way Set-Associative (4KB), Tree-PLRU, 4-Entry MSHR, Hit-Under-Miss, AMBA AXI4.")
        self.log("="*80)

    def _configure_styles(self):
        self.style.configure(".", background="#1e1e2e", foreground="#cdd6f4", font=("Segoe UI", 10))
        self.style.configure("Header.TLabel", font=("Segoe UI Semibold", 16), foreground="#89b4fa", background="#181825")
        self.style.configure("SubHeader.TLabel", font=("Segoe UI", 9), foreground="#a6adc8", background="#181825")
        self.style.configure("Card.TFrame", background="#181825", relief="flat")
        self.style.configure("Section.TLabel", font=("Segoe UI Semibold", 11), foreground="#f9e2af", background="#181825")

        self.style.configure("Primary.TButton", font=("Segoe UI Semibold", 10), background="#89b4fa", foreground="#11111b", padding=6)
        self.style.map("Primary.TButton", background=[("active", "#b4befe")])

        self.style.configure("Green.TButton", font=("Segoe UI Semibold", 10), background="#a6e3a1", foreground="#11111b", padding=6)
        self.style.map("Green.TButton", background=[("active", "#94e2d5")])

        self.style.configure("Accent.TButton", font=("Segoe UI Semibold", 10), background="#cba6f7", foreground="#11111b", padding=6)
        self.style.map("Accent.TButton", background=[("active", "#f5c2e7")])

    def _build_header(self):
        hdr_frame = tk.Frame(self, bg="#181825", padx=20, pady=12)
        hdr_frame.pack(fill=tk.X, side=tk.TOP)

        title = ttk.Label(hdr_frame, text="Apex-L1Cache Silicon Engineering Workbench", style="Header.TLabel")
        title.pack(anchor=tk.W)

        subtitle = ttk.Label(
            hdr_frame,
            text="4-Way Set-Associative Non-Blocking L1 Data Cache with 4-Entry MSHR, Hit-Under-Miss & AMBA AXI4",
            style="SubHeader.TLabel"
        )
        subtitle.pack(anchor=tk.W)

    def _build_main_layout(self):
        container = tk.Frame(self, bg="#1e1e2e", padx=15, pady=10)
        container.pack(fill=tk.BOTH, expand=True)

        left_panel = tk.Frame(container, bg="#181825", width=340, padx=15, pady=15, relief="ridge", bd=1)
        left_panel.pack(side=tk.LEFT, fill=tk.Y, padx=(0, 10))
        left_panel.pack_propagate(False)

        right_panel = tk.Frame(container, bg="#11111b")
        right_panel.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True)

        self._populate_left_panel(left_panel)
        self._populate_right_panel(right_panel)

    def _populate_left_panel(self, parent):
        lbl_v = ttk.Label(parent, text="1. Verification & Simulation", style="Section.TLabel")
        lbl_v.pack(anchor=tk.W, pady=(0, 6))

        btn_py = ttk.Button(
            parent,
            text="▶ Run Python Golden Model",
            style="Primary.TButton",
            command=lambda: self._run_command_threaded(
                ["python", os.path.join(ROOT_DIR, "sim", "golden_cache_model.py")],
                "Running Python Reference Architectural Simulator..."
            )
        )
        btn_py.pack(fill=tk.X, pady=4)

        btn_tb = ttk.Button(
            parent,
            text="▶ Run Verilog Testbench (Icarus)",
            style="Primary.TButton",
            command=self._run_verilog_sim
        )
        btn_tb.pack(fill=tk.X, pady=4)

        lbl_w = ttk.Label(parent, text="2. Waveform Visualization", style="Section.TLabel")
        lbl_w.pack(anchor=tk.W, pady=(16, 6))

        btn_wave = ttk.Button(
            parent,
            text="📈 Launch GTKWave GUI Viewer",
            style="Green.TButton",
            command=self._launch_gtkwave
        )
        btn_wave.pack(fill=tk.X, pady=4)

        lbl_s = ttk.Label(parent, text="3. Silicon EDA Synthesis", style="Section.TLabel")
        lbl_s.pack(anchor=tk.W, pady=(16, 6))

        btn_asic = ttk.Button(
            parent,
            text="🔬 45nm ASIC Synthesis (Yosys)",
            style="Accent.TButton",
            command=self._run_asic_synth
        )
        btn_asic.pack(fill=tk.X, pady=4)

        lbl_u = ttk.Label(parent, text="4. Verilog Code & RTL", style="Section.TLabel")
        lbl_u.pack(anchor=tk.W, pady=(16, 6))

        btn_vscode = ttk.Button(
            parent,
            text="📝 Open in VS Code (RTL Editor)",
            command=self._open_vscode
        )
        btn_vscode.pack(fill=tk.X, pady=4)

        btn_folder = ttk.Button(
            parent,
            text="📁 Open RTL Folder (Explorer)",
            command=self._open_rtl_folder
        )
        btn_folder.pack(fill=tk.X, pady=4)

        btn_clear = ttk.Button(
            parent,
            text="🧹 Clear Console Output",
            command=self._clear_console
        )
        btn_clear.pack(fill=tk.X, pady=4)

    def _populate_right_panel(self, parent):
        lbl = ttk.Label(parent, text="Execution Logs & Console Output", style="Section.TLabel")
        lbl.pack(anchor=tk.W, pady=(0, 6))

        self.console = scrolledtext.ScrolledText(
            parent,
            bg="#11111b",
            fg="#cdd6f4",
            insertbackground="#f5e0dc",
            font=("Consolas", 10),
            padx=10,
            pady=10,
            wrap=tk.WORD,
            relief="ridge",
            bd=1
        )
        self.console.pack(fill=tk.BOTH, expand=True)

    def _build_status_bar(self):
        self.status_bar = tk.Label(
            self,
            text="Status: Ready",
            bg="#11111b",
            fg="#a6adc8",
            font=("Segoe UI", 9),
            anchor=tk.W,
            padx=15,
            pady=4
        )
        self.status_bar.pack(fill=tk.X, side=tk.BOTTOM)

    def log(self, text):
        self.console.insert(tk.END, text + "\n")
        self.console.see(tk.END)

    def _clear_console(self):
        self.console.delete("1.0", tk.END)

    def _set_status(self, text):
        self.status_bar.config(text=f"Status: {text}")

    def _run_command_threaded(self, cmd, desc):
        threading.Thread(target=self._execute_command, args=(cmd, desc), daemon=True).start()

    def _execute_command(self, cmd, desc):
        self._set_status(desc)
        self.log(f"\n[EXEC] {desc}")
        self.log(f"Command: {' '.join(cmd) if isinstance(cmd, list) else cmd}")
        self.log("-" * 80)
        try:
            p = subprocess.Popen(
                cmd,
                cwd=ROOT_DIR,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                shell=isinstance(cmd, str)
            )
            for line in iter(p.stdout.readline, ''):
                self.log(line.rstrip())
            p.stdout.close()
            p.wait()
            if p.returncode == 0:
                self.log(f"[SUCCESS] Command finished with exit code 0.\n")
                self._set_status("Ready (Last command succeeded)")
            else:
                self.log(f"[FAILURE] Command failed with exit code {p.returncode}.\n")
                self._set_status(f"Error (Exit code {p.returncode})")
        except Exception as e:
            self.log(f"[EXCEPTION] Failed to execute: {e}\n")
            self._set_status("Execution failed")

    def _run_verilog_sim(self):
        def task():
            self._set_status("Compiling & running Verilog simulation...")
            self.log("\n[EXEC] Non-Blocking Cache Verilog Simulation (Icarus Verilog)")
            self.log("-" * 80)
            compile_cmd = (
                f'call "{ENV_BAT}" && '
                f'iverilog -g2012 -o sim\\tb_cache.vvp rtl\\tag_array.v rtl\\plru_replacement.v '
                f'rtl\\data_array.v rtl\\mshr_table.v rtl\\writeback_buffer.v '
                f'rtl\\axi4_master_interface.v rtl\\apex_cache_top.v sim\\tb_nonblocking_cache.v && '
                f'vvp sim\\tb_cache.vvp'
            )
            self._execute_command(compile_cmd, "Running Verilog Hardware Simulation")
        threading.Thread(target=task, daemon=True).start()

    def _launch_gtkwave(self):
        vcd_path = os.path.join(ROOT_DIR, "sim", "apex_cache.vcd")
        gtkw_path = os.path.join(ROOT_DIR, "sim", "apex_cache.gtkw")
        if not os.path.exists(vcd_path):
            messagebox.showwarning("VCD Not Found", "Waveform file (sim/apex_cache.vcd) not found.\nPlease run simulation first.")
            return

        self.log("\n[LAUNCH] Launching GTKWave GUI Waveform Viewer...")
        bat_cmd = f'call "{ENV_BAT}" && start "" gtkwave "{vcd_path}" "{gtkw_path}"'
        subprocess.Popen(bat_cmd, cwd=ROOT_DIR, shell=True)
        self.log(f"[OPEN] GTKWave opened with pre-loaded cache signals ({gtkw_path}).")
        self._set_status("GTKWave GUI running")

    def _run_asic_synth(self):
        def task():
            self._set_status("Synthesizing for 45nm ASIC via Yosys...")
            self.log("\n[EXEC] Running 45nm Nangate Standard-Cell Synthesis (Yosys)")
            self.log("-" * 80)
            cmd = f'call "{ENV_BAT}" && yosys synth\\run_synth_asic.ys'
            self._execute_command(cmd, "ASIC Nangate 45nm Synthesis")
        threading.Thread(target=task, daemon=True).start()

    def _open_vscode(self):
        try:
            subprocess.Popen(["code", ROOT_DIR], shell=True)
            self.log(f"[OPEN] Opened project in Visual Studio Code: {ROOT_DIR}")
        except Exception as e:
            self.log(f"[ERROR] Could not open VS Code: {e}")

    def _open_rtl_folder(self):
        rtl_dir = os.path.join(ROOT_DIR, "rtl")
        try:
            os.startfile(rtl_dir)
            self.log(f"[OPEN] Opened RTL folder in File Explorer: {rtl_dir}")
        except Exception as e:
            self.log(f"[ERROR] Could not open folder: {e}")

if __name__ == "__main__":
    app = ApexCacheEDAApp()
    app.mainloop()
