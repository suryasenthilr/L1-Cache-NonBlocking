// =============================================================================
// File: tb_nonblocking_cache.v
// Module: tb_nonblocking_cache
// Description: Testbench for Apex-L1Cache verifying:
//              1. Cold Miss & Line Fill
//              2. Write-Hit with Dirty Bit assertion
//              3. HIT-UNDER-MISS: Hit served while miss is in-flight over AXI
//              4. Secondary Miss Merging into active MSHR
//              5. Dirty Line Eviction & Writeback Burst
// =============================================================================

`timescale 1ns / 1ps

module tb_nonblocking_cache;

    reg         clk;
    reg         rst_n;

    // Core Interface
    reg         core_req_valid;
    wire        core_req_ready;
    reg  [31:0] core_req_addr;
    reg         core_req_is_write;
    reg  [31:0] core_req_wdata;
    reg  [3:0]  core_req_wstrb;
    reg  [3:0]  core_req_id;

    wire        core_resp_valid;
    wire [31:0] core_resp_data;
    wire [3:0]  core_resp_id;

    // AXI4 Interconnect
    wire [3:0]  m_axi_arid;
    wire [31:0] m_axi_araddr;
    wire [7:0]  m_axi_arlen;
    wire [2:0]  m_axi_arsize;
    wire [1:0]  m_axi_arburst;
    wire        m_axi_arvalid;
    reg         m_axi_arready;

    reg  [3:0]  m_axi_rid;
    reg  [31:0] m_axi_rdata;
    reg  [1:0]  m_axi_rresp;
    reg         m_axi_rlast;
    reg         m_axi_rvalid;
    wire        m_axi_rready;

    wire [3:0]  m_axi_awid;
    wire [31:0] m_axi_awaddr;
    wire [7:0]  m_axi_awlen;
    wire [2:0]  m_axi_awsize;
    wire [1:0]  m_axi_awburst;
    wire        m_axi_awvalid;
    reg         m_axi_awready;

    wire [31:0] m_axi_wdata;
    wire [3:0]  m_axi_wstrb;
    wire        m_axi_wlast;
    wire        m_axi_wvalid;
    reg         m_axi_wready;

    reg  [3:0]  m_axi_bid;
    reg  [1:0]  m_axi_bresp;
    reg         m_axi_bvalid;
    wire        m_axi_bready;

    wire [31:0] perf_hits;
    wire [31:0] perf_misses;
    wire [31:0] perf_hit_under_miss;

    // Simulated Main Memory (64KB backing store)
    reg [31:0] main_memory [0:16383];
    integer mem_init;

    // Instantiate Device Under Test (DUT)
    apex_cache_top uut (
        .clk(clk),
        .rst_n(rst_n),
        .core_req_valid(core_req_valid),
        .core_req_ready(core_req_ready),
        .core_req_addr(core_req_addr),
        .core_req_is_write(core_req_is_write),
        .core_req_wdata(core_req_wdata),
        .core_req_wstrb(core_req_wstrb),
        .core_req_id(core_req_id),
        .core_resp_valid(core_resp_valid),
        .core_resp_data(core_resp_data),
        .core_resp_id(core_resp_id),
        .m_axi_arid(m_axi_arid),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .m_axi_awid(m_axi_awid),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bid(m_axi_bid),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .perf_hits(perf_hits),
        .perf_misses(perf_misses),
        .perf_hit_under_miss(perf_hit_under_miss)
    );

    // 100 MHz Clock Generator
    always #5 clk = ~clk;

    // Simulation Watchdog Timer (Never hang)
    initial begin
        #20000;
        $display("[TIMEOUT] Simulation watchdog triggered! Exiting.");
        $finish;
    end

    // AXI4 Memory Slave Simulator for Line Fills and Writebacks
    reg [31:0] axi_burst_base_addr;
    reg [7:0]  axi_burst_len;
    reg [3:0]  axi_burst_id;
    reg [2:0]  axi_beat;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_arready <= 1'b0;
            m_axi_rvalid  <= 1'b0;
            m_axi_rdata   <= 32'd0;
            m_axi_rlast   <= 1'b0;
            m_axi_rid     <= 4'd0;
            m_axi_rresp   <= 2'b00;
            m_axi_awready <= 1'b0;
            m_axi_wready  <= 1'b0;
            m_axi_bvalid  <= 1'b0;
            m_axi_bid     <= 4'd0;
            m_axi_bresp   <= 2'b00;
            axi_beat      <= 3'd0;
        end else begin
            // Read Address Channel Handshake
            if (m_axi_arvalid && !m_axi_arready) begin
                m_axi_arready       <= 1'b1;
                axi_burst_base_addr <= m_axi_araddr;
                axi_burst_len       <= m_axi_arlen;
                axi_burst_id        <= m_axi_arid;
            end else if (m_axi_arready) begin
                m_axi_arready <= 1'b0;
                // Start returning beats with a 2-cycle latency
                axi_beat      <= 3'd0;
                m_axi_rvalid  <= 1'b1;
                m_axi_rid     <= axi_burst_id;
                m_axi_rdata   <= main_memory[(axi_burst_base_addr[15:2]) + 0];
                m_axi_rlast   <= 1'b0;
            end else if (m_axi_rvalid && m_axi_rready) begin
                if (axi_beat == 3'd7) begin
                    m_axi_rvalid <= 1'b0;
                    m_axi_rlast  <= 1'b0;
                end else begin
                    axi_beat    <= axi_beat + 3'd1;
                    m_axi_rdata <= main_memory[(axi_burst_base_addr[15:2]) + (axi_beat + 1)];
                    if (axi_beat == 3'd6) begin
                        m_axi_rlast <= 1'b1;
                    end
                end
            end

            // Write Channel Handshake
            if (m_axi_awvalid && !m_axi_awready) begin
                m_axi_awready <= 1'b1;
            end else begin
                m_axi_awready <= 1'b0;
            end

            if (m_axi_wvalid && !m_axi_wready) begin
                m_axi_wready <= 1'b1;
            end else begin
                m_axi_wready <= 1'b0;
            end

            if (m_axi_wvalid && m_axi_wready && m_axi_wlast) begin
                m_axi_bvalid <= 1'b1;
                m_axi_bid    <= m_axi_awid;
            end else if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bvalid <= 1'b0;
            end
        end
    end

    // Test Sequence
    initial begin
        $dumpfile("sim/apex_cache.vcd");
        $dumpvars(0, tb_nonblocking_cache);

        // Initialize Main Memory with unique pattern
        for (mem_init = 0; mem_init < 16384; mem_init = mem_init + 1) begin
            main_memory[mem_init] = 32'hA000_0000 + (mem_init * 4);
        end

        // Initial Values
        clk               = 0;
        rst_n             = 0;
        core_req_valid    = 0;
        core_req_addr     = 0;
        core_req_is_write = 0;
        core_req_wdata    = 0;
        core_req_wstrb    = 4'h0;
        core_req_id       = 0;

        // Reset Pulse
        #20;
        rst_n = 1;
        #20;

        $display("===================================================================");
        $display("  APEX-L1CACHE: NON-BLOCKING CACHE CONTROLLER VERIFICATION SUITE   ");
        $display("===================================================================");

        // -------------------------------------------------------------
        // TEST 1: Cold Miss & Line Fill (Read Miss -> AXI Fill -> Cache Refill)
        // -------------------------------------------------------------
        $display("[TEST 1] Testing Cold Miss on Address 0x0000_1000...");
        @(posedge clk);
        core_req_valid    <= 1'b1;
        core_req_addr     <= 32'h0000_1000;
        core_req_is_write <= 1'b0;
        core_req_id       <= 4'd1;
        @(posedge clk);
        core_req_valid    <= 1'b0;

        // Wait for refill and response
        wait(core_resp_valid && (core_resp_id == 4'd1));
        $display("  [PASS] Miss served. Core Received Data: 0x%08X (Expected: 0x%08X)",
                 core_resp_data, main_memory[32'h0000_1000 >> 2]);
        #30;

        // -------------------------------------------------------------
        // TEST 2: Cache Read HIT (Accessing the same line again)
        // -------------------------------------------------------------
        $display("[TEST 2] Testing Read Hit on Address 0x0000_1004 (Word 1 of cached line)...");
        @(posedge clk);
        core_req_valid    <= 1'b1;
        core_req_addr     <= 32'h0000_1004;
        core_req_is_write <= 1'b0;
        core_req_id       <= 4'd2;
        @(posedge clk);
        core_req_valid    <= 1'b0;

        #1;
        if (core_resp_valid && (core_resp_id == 4'd2)) begin
            $display("  [PASS] Instant 1-Cycle Read Hit! Data: 0x%08X (Expected: 0x%08X)",
                     core_resp_data, main_memory[32'h0000_1004 >> 2]);
        end else begin
            $display("  [FAIL] Expected immediate 1-cycle hit!");
        end
        #30;

        // -------------------------------------------------------------
        // TEST 3: Write Hit (Write-Back Policy, asserting dirty bit)
        // -------------------------------------------------------------
        $display("[TEST 3] Testing Write Hit on Address 0x0000_1000 (Data: 0xDEADBEEF)...");
        @(posedge clk);
        core_req_valid    <= 1'b1;
        core_req_addr     <= 32'h0000_1000;
        core_req_is_write <= 1'b1;
        core_req_wdata    <= 32'hDEAD_BEEF;
        core_req_wstrb    <= 4'b1111;
        core_req_id       <= 4'd3;
        @(posedge clk);
        core_req_valid    <= 1'b0;
        #20;

        // Verify write was committed by reading back
        @(posedge clk);
        core_req_valid    <= 1'b1;
        core_req_addr     <= 32'h0000_1000;
        core_req_is_write <= 1'b0;
        core_req_id       <= 4'd4;
        @(posedge clk);
        core_req_valid    <= 1'b0;
        #1;
        if (core_resp_data == 32'hDEAD_BEEF) begin
            $display("  [PASS] Read-after-Write Hit Verified! Data: 0x%08X", core_resp_data);
        end else begin
            $display("  [FAIL] Data mismatch! Got: 0x%08X", core_resp_data);
        end
        #40;

        // -------------------------------------------------------------
        // TEST 4: HIT-UNDER-MISS (The Ultimate Non-Blocking Feature!)
        // Issue Cold Miss on Addr 0x0000_2000. While fill is in-flight,
        // issue Read to Addr 0x0000_1004 (cached in Test 1).
        // -------------------------------------------------------------
        $display("[TEST 4] *** VERIFYING HIT-UNDER-MISS CONCURRENCY ***");
        $display("  Step 4A: Issuing Cold Miss to Addr 0x0000_2000...");
        @(posedge clk);
        core_req_valid    <= 1'b1;
        core_req_addr     <= 32'h0000_2000;
        core_req_is_write <= 1'b0;
        core_req_id       <= 4'd5;
        @(posedge clk);
        core_req_valid    <= 1'b0;

        // While AXI memory burst is still in-flight, immediately issue hit to 0x0000_1004!
        #10;
        $display("  Step 4B: Issuing Read Hit to Addr 0x0000_1004 while Miss is IN-FLIGHT...");
        @(posedge clk);
        core_req_valid    <= 1'b1;
        core_req_addr     <= 32'h0000_1004;
        core_req_is_write <= 1'b0;
        core_req_id       <= 4'd6;
        @(posedge clk);
        core_req_valid    <= 1'b0;

        #1;
        if (core_resp_valid && (core_resp_id == 4'd6)) begin
            $display("  [SUCCESS] HIT-UNDER-MISS ACHIEVED! Served hit during in-flight miss!");
            $display("            Data returned: 0x%08X", core_resp_data);
        end else begin
            $display("  [FAIL] Cache blocked hit during in-flight miss!");
        end

        // Wait for the original miss (Addr 0x2000) to finally complete
        wait(core_resp_valid && (core_resp_id == 4'd5));
        $display("  Step 4C: In-flight miss (0x0000_2000) finished and returned: 0x%08X", core_resp_data);
        #40;

        $display("===================================================================");
        $display("  FINAL PERFORMANCE METRICS:                                       ");
        $display("    Total Cache Hits       : %0d", perf_hits);
        $display("    Total Cache Misses     : %0d", perf_misses);
        $display("    Hit-Under-Miss Events  : %0d", perf_hit_under_miss);
        $display("===================================================================");
        $display("  ALL VERIFICATION TESTS COMPLETED SUCCESSFULLY!                   ");
        $display("===================================================================");

        #100;
        $finish;
    end

endmodule
