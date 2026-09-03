`timescale 1ns / 1ps

// ---------------------------------------------------------
// Transaction Class
// ---------------------------------------------------------
class transaction;
    // Randomized inputs
    rand bit        is_write; // 1 for write, 0 for read
    rand bit [31:0] addr;
    rand bit [31:0] data;
    rand bit [3:0]  wstrb;
    rand bit [2:0]  prot;     // Protection/Priority/Privilege
    
    // Outputs captured from DUT
    bit [31:0] rdata;
    bit [1:0]  bresp;
    bit [1:0]  rresp;
    
    // Constraints for edge cases and alignment
    constraint addr_align { addr % 4 == 0; } // Word-aligned addresses
    constraint mem_bounds { addr < 32'h0000_00FF; } // Keep inside small memory space

    function void display(string name="[TRANS]");
        if(is_write)
            $display("%s WRITE: ADDR: %0h \t DATA: %0h \t STRB: %b \t PROT: %0d \t BRESP: %0d", name, addr, data, wstrb, prot, bresp);
        else
            $display("%s READ:  ADDR: %0h \t PROT: %0d \t RDATA: %0h \t RRESP: %0d", name, addr, prot, rdata, rresp);
    endfunction
    
    virtual function transaction copy();   // Deep copy
        copy = new();
        copy.is_write = this.is_write;
        copy.addr  = this.addr;
        copy.data  = this.data;
        copy.wstrb = this.wstrb;
        copy.prot  = this.prot;
        copy.rdata = this.rdata;
        copy.bresp = this.bresp;
        copy.rresp = this.rresp;
    endfunction
endclass

// ---------------------------------------------------------
// Error Class for Fault Injection
// ---------------------------------------------------------
class error extends transaction; 
    // Force misaligned addresses and corrupted strobes to test edge cases
    constraint err { addr % 4 != 0; wstrb == 4'b0000; }
    
    function transaction copy();
        copy = super.copy(); // Call parent copy 
    endfunction
endclass

// ---------------------------------------------------------
// AXI4-Lite Interface (19 signals + clk + resetn)
// ---------------------------------------------------------
interface axi_if;
    logic clk;
    logic resetn;
    
    // Write Address Channel
    logic [31:0] awaddr;
    logic [2:0]  awprot;
    logic        awvalid;
    logic        awready;
    // Write Data Channel
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wvalid;
    logic        wready;
    // Write Response Channel
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;
    
    // Read Address Channel
    logic [31:0] araddr;
    logic [2:0]  arprot;
    logic        arvalid;
    logic        arready;
    // Read Data Channel
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic        rready;

    modport DRV (
        output awaddr, awprot, awvalid, wdata, wstrb, wvalid, bready, araddr, arprot, arvalid, rready,
        input  awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid, clk, resetn
    );
    modport MON (
        input awaddr, awprot, awvalid, wdata, wstrb, wvalid, bready, araddr, arprot, arvalid, rready,
              awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid, clk, resetn
    );
endinterface

// ---------------------------------------------------------
// Generator
// ---------------------------------------------------------
class generator;
    transaction trans;
    mailbox #(transaction) mbx;
    event done;
    
    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
        trans = new();
    endfunction
    
    task run();
        for(int i=0; i<20; i++) begin
            assert(trans.randomize()) else begin
                $display("Randomization failed at time: %0t", $time());
            end
            mbx.put(trans.copy()); 
            $display("[GEN] : DATA SENT TO DRV");
            #20; // Pace the generation
        end
        -> done;
    endtask
endclass

// ---------------------------------------------------------
// Driver (Emulates AXI Master)
// ---------------------------------------------------------
class driver;
    virtual axi_if.DRV aif; 
    mailbox #(transaction) mbx;
    transaction trans;
    
    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction
    
    task run();
        // Initialize Driver Signals
        aif.awvalid <= 0; aif.wvalid <= 0; aif.bready <= 0;
        aif.arvalid <= 0; aif.rready <= 0;
        wait(aif.resetn);
        
        forever begin
            mbx.get(trans);
            if (trans.is_write) begin
                // Write Address Phase
                @(posedge aif.clk);
                aif.awvalid <= 1; aif.awaddr <= trans.addr; aif.awprot <= trans.prot;
                do @(posedge aif.clk); while(!aif.awready);
                aif.awvalid <= 0;
                
                // Write Data Phase
                aif.wvalid <= 1; aif.wdata <= trans.data; aif.wstrb <= trans.wstrb;
                do @(posedge aif.clk); while(!aif.wready);
                aif.wvalid <= 0;
                
                // Write Response Phase
                aif.bready <= 1;
                do @(posedge aif.clk); while(!aif.bvalid);
                trans.bresp = aif.bresp; // Capture Response
                aif.bready <= 0;
                
            end else begin
                // Read Address Phase
                @(posedge aif.clk);
                aif.arvalid <= 1; aif.araddr <= trans.addr; aif.arprot <= trans.prot;
                do @(posedge aif.clk); while(!aif.arready);
                aif.arvalid <= 0;
                
                // Read Data Phase
                aif.rready <= 1;
                do @(posedge aif.clk); while(!aif.rvalid);
                trans.rdata = aif.rdata; // Capture Data
                trans.rresp = aif.rresp; // Capture Response
                aif.rready <= 0;
            end
            $display("[DRV] : Interface triggered" );
            trans.display("[DRV]");
        end
    endtask
endclass

// ---------------------------------------------------------
// Monitor
// ---------------------------------------------------------
class monitor;
    virtual axi_if.MON aif;
    mailbox #(transaction) mbx;
    
    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction
    
    task run();
        fork
            // Thread 1: Monitor Writes
            forever begin
                transaction tr_w = new();
                tr_w.is_write = 1;
                
                do @(posedge aif.clk); while(!(aif.awvalid && aif.awready));
                tr_w.addr = aif.awaddr; tr_w.prot = aif.awprot;
                
                do @(posedge aif.clk); while(!(aif.wvalid && aif.wready));
                tr_w.data = aif.wdata; tr_w.wstrb = aif.wstrb;
                
                do @(posedge aif.clk); while(!(aif.bvalid && aif.bready));
                tr_w.bresp = aif.bresp;
                
                $display("[MON] : WRITE SENT TO SCOREBOARD");
                mbx.put(tr_w);
            end
            
            // Thread 2: Monitor Reads
            forever begin
                transaction tr_r = new();
                tr_r.is_write = 0;
                
                do @(posedge aif.clk); while(!(aif.arvalid && aif.arready));
                tr_r.addr = aif.araddr; tr_r.prot = aif.arprot;
                
                do @(posedge aif.clk); while(!(aif.rvalid && aif.rready));
                tr_r.rdata = aif.rdata; tr_r.rresp = aif.rresp;
                
                $display("[MON] : READ SENT TO SCOREBOARD");
                mbx.put(tr_r);
            end
        join
     endtask
endclass

// ---------------------------------------------------------
// Scoreboard (Reference Memory Model)
// ---------------------------------------------------------
class scoreboard;
    mailbox #(transaction) mbx;
    transaction trans;
    
    bit [31:0] ref_mem [int]; // Associative array mimicking DUT Memory
    
    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction
    
    task run();
        forever begin
            mbx.get(trans);
            $display("[SCR] : DATA RCVD FROM MONITOR");
            
            if (trans.is_write) begin
                ref_mem[trans.addr] = trans.data; 
                $display("[%0t] [SCO] WRITE MAPPED - Addr: %0h Data: %0h", $time, trans.addr, trans.data);
            end else begin
                if (ref_mem.exists(trans.addr)) begin
                    if (ref_mem[trans.addr] == trans.rdata) 
                        $display("[%0t] [SCO] PASS! Addr: %0h matches Data: %0h", $time, trans.addr, trans.rdata);
                    else 
                        $display("[%0t] [SCO] FAIL! Addr: %0h Expected: %0h, Got: %0h", $time, trans.addr, ref_mem[trans.addr], trans.rdata);
                end else begin
                    $display("[%0t] [SCO] INFO! Read from uninitialized Addr %0h (Got: %0h)", $time, trans.addr, trans.rdata);
                end
            end
            $display("---------------------------------------------------");
        end
     endtask
endclass

// ---------------------------------------------------------
// Dummy DUT Memory (To process the AXI Handshake)
// ---------------------------------------------------------
module axi_slave_dummy(axi_if aif);
    logic [31:0] memory [0:255];
    
    // Always Ready for simplest edge-case testing
    assign aif.awready = 1'b1;
    assign aif.wready  = 1'b1;
    assign aif.arready = 1'b1;
    
    // Write Processing
    always_ff @(posedge aif.clk) begin
        if (!aif.resetn) begin
            aif.bvalid <= 0;
        end else begin
            if (aif.awvalid && aif.wvalid) begin
                memory[aif.awaddr[9:2]] <= aif.wdata; // Write memory (ignoring strobes for simplicity)
                aif.bvalid <= 1'b1;
                aif.bresp  <= 2'b00; // OKAY Response
            end else if (aif.bready && aif.bvalid) begin
                aif.bvalid <= 0;
            end
        end
    end
    
    // Read Processing
    always_ff @(posedge aif.clk) begin
        if (!aif.resetn) begin
            aif.rvalid <= 0;
        end else begin
            if (aif.arvalid) begin
                aif.rdata  <= memory[aif.araddr[9:2]];
                aif.rvalid <= 1'b1;
                aif.rresp  <= 2'b00; // OKAY Response
            end else if (aif.rready && aif.rvalid) begin
                aif.rvalid <= 0;
            end
        end
    end
endmodule

// ---------------------------------------------------------
// Top Level Testbench Module
// ---------------------------------------------------------
module tb;
    axi_if aif();
    
    driver drv;
    generator gen;
    monitor mon;
    scoreboard sco;
    mailbox #(transaction) mbx_gen2drv, mbx_mon2sco;
    
    initial begin
        mbx_gen2drv = new();
        mbx_mon2sco = new();
        
        gen = new(mbx_gen2drv);
        drv = new(mbx_gen2drv);
        mon = new(mbx_mon2sco);
        sco = new(mbx_mon2sco);
        
        drv.aif = aif;
        mon.aif = aif;
     end
     
    // Instantiate Dummy DUT
    axi_slave_dummy dut (aif);
    
    // Clock and Reset Generation
    initial begin
        aif.clk = 0;
        aif.resetn = 0;
        #15 aif.resetn = 1;
    end
    always #5 aif.clk = ~aif.clk;
    
    // Run Testbench Components
    initial begin
        fork 
            gen.run();
            drv.run();
            mon.run();
            sco.run();
        join_none
    end
       
    // End of Simulation Control
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
        wait(gen.done.triggered);
        #200; // Allow final handshakes to clear pipelines
        $finish();
    end
        
endmodule
