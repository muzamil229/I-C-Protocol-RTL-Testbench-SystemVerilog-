`timescale 1ns/1ps

// ============================================================
// INTERFACE
// ============================================================
interface i2c_if;
    logic clk;
    logic rst;
    logic newd;
    logic op;
    logic stretch;
    logic [6:0] addr;
    logic [7:0] din;
    logic [7:0] dout;
    logic busy;
    logic ack_err;
    logic done;

    // internal visibility
    logic [3:0] master_state;
endinterface


// ============================================================
// TRANSACTION
// ============================================================
class i2c_txn;
    rand bit [6:0] addr;
    rand bit       op;
    rand bit [7:0] data;
    rand bit       stretch;

    bit ack_err;   // captured by monitor

    constraint c_addr { addr inside {[0:10]}; }

    function void print(string tag);
        $display("[%s] addr=%0d data=%0d op=%0d stretch=%0d ack_err=%0d",
                 tag, addr, data, op, stretch, ack_err);
    endfunction
endclass


// ============================================================
// GENERATOR  (matches your procedural TB)
// ============================================================
class i2c_generator;
    mailbox gen2drv;

    function new(mailbox m);
        gen2drv = m;
    endfunction

    task run();
        i2c_txn t;

        // TRANSACTION 1 : no stretch
        t = new();
        t.addr    = $urandom_range(0,10);
        t.data    = $urandom_range(1,5);
        t.op      = 0;
        t.stretch = 0;
        t.print("GEN");
        gen2drv.put(t);

        // TRANSACTION 2 : with stretch
        t = new();
        t.addr    = $urandom_range(0,10);
        t.data    = $urandom_range(1,5);
        t.op      = 0;
        t.stretch = 1;
        t.print("GEN");
        gen2drv.put(t);
    endtask
endclass


// ============================================================
// DRIVER (TIMING-CORRECT, FSM-AWARE)
// ============================================================
class i2c_driver;
    virtual i2c_if vif;
    mailbox gen2drv;

    function new(virtual i2c_if vif, mailbox m);
        this.vif = vif;
        gen2drv  = m;
    endfunction

    task run();
        i2c_txn t;

        forever begin
            gen2drv.get(t);

            // wait until master idle
            wait (vif.busy == 0);

            vif.addr <= t.addr;
            vif.op   <= t.op;
            vif.din  <= t.data;

            // launch
            @(posedge vif.clk);
            vif.newd <= 1'b1;

            wait (vif.busy == 1);
            @(posedge vif.clk);
            vif.newd <= 1'b0;

            // stretch behavior exactly like original TB
            if (t.stretch) begin
                wait (vif.master_state == 3); // ack_1
                vif.stretch <= 1'b1;
                repeat (1200) @(posedge vif.clk);
                vif.stretch <= 1'b0;
            end
            else begin
                vif.stretch <= 1'b0;
            end

            // wait for completion
            wait (vif.done == 1);
            wait (vif.busy == 0);
            @(posedge vif.clk);
        end
    endtask
endclass


// ============================================================
// MONITOR  (FIXED: edge-accurate sampling)
// ============================================================
class i2c_monitor;
    virtual i2c_if vif;
    mailbox mon2sb;

    function new(virtual i2c_if vif, mailbox m);
        this.vif = vif;
        mon2sb   = m;
    endfunction

    task run();
        bit prev_done = 0;
        i2c_txn t;

        forever begin
            @(posedge vif.clk);

            if (vif.done && !prev_done) begin
                t = new();
                t.addr    = vif.addr;
                t.op      = vif.op;
                t.data    = (vif.op == 0) ? vif.din : vif.dout;
                t.stretch = vif.stretch;

                // CRITICAL FIX
                t.ack_err = vif.ack_err;

                t.print("MON");
                mon2sb.put(t);
            end
            prev_done = vif.done;
        end
    endtask
endclass


// ============================================================
// SCOREBOARD  (NO RACES)
// ============================================================
class i2c_scoreboard;
    mailbox mon2sb;

    function new(mailbox m);
        mon2sb = m;
    endfunction

    task run();
        i2c_txn t;
        forever begin
            mon2sb.get(t);

            if (t.ack_err)
                $error("[SB FAIL] addr=%0d op=%0d", t.addr, t.op);
            else
                $display("[SB PASS] addr=%0d op=%0d data=%0d stretch=%0d",
                         t.addr, t.op, t.data, t.stretch);
        end
    endtask
endclass


// ============================================================
// TOP-LEVEL TESTBENCH
// ============================================================
module tb;

    i2c_if tb_if();

    mailbox gen2drv = new();
    mailbox mon2sb  = new();

    i2c_generator  gen;
    i2c_driver     drv;
    i2c_monitor    mon;
    i2c_scoreboard sb;

    // DUT
    i2c_top dut (
        .clk     (tb_if.clk),
        .rst     (tb_if.rst),
        .newd    (tb_if.newd),
        .op      (tb_if.op),
        .stretch (tb_if.stretch),
        .addr    (tb_if.addr),
        .din     (tb_if.din),
        .dout    (tb_if.dout),
        .busy    (tb_if.busy),
        .ack_err (tb_if.ack_err),
        .done    (tb_if.done)
    );

    assign tb_if.master_state = dut.master.state;

    // clock
    always #5 tb_if.clk = ~tb_if.clk;

    // reset
    initial begin
        tb_if.clk     = 0;
        tb_if.rst     = 1;
        tb_if.newd    = 0;
        tb_if.op      = 0;
        tb_if.addr    = 0;
        tb_if.din     = 0;
        tb_if.stretch = 0;
        repeat (5) @(posedge tb_if.clk);
        tb_if.rst = 0;
    end

    // start environment
    initial begin
        gen = new(gen2drv);
        drv = new(tb_if, gen2drv);
        mon = new(tb_if, mon2sb);
        sb  = new(mon2sb);

        fork
            gen.run();
            drv.run();
            mon.run();
            sb.run();
        join_none
    end

    initial begin
        #200_000;
        $display("=== SIMULATION FINISHED CLEANLY ===");
        $finish;
    end

endmodule
