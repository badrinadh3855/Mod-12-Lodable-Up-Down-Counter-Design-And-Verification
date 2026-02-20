//-------------------------rtl-------------------------
module counter(clock,reset,up_down,load,data_in,data_out);
    input clock,reset,load,up_down;
    input [3:0]data_in;
    output reg [3:0]data_out;

    always@(posedge clock)
    begin
        if(reset)
            data_out <= 4'd0;
        else if(load)
            data_out <= data_in;
        else if(up_down == 0)  // Count up
        begin
            if(data_out == 4'd11)
                data_out <= 4'd0;
            else
                data_out <= data_out + 1;
        end
        else  // Count down
        begin
            if(data_out == 4'd0)
                data_out <= 4'd11;
            else
                data_out <= data_out - 1;
        end
    end
endmodule

//---------------------package--------------------------
package counter_pkg;
    static int number_of_transactions = 1;
endpackage

//----------------------Interface-----------------------
interface counter_if(input bit clock);
    logic [3:0]data_in;
    logic [3:0]data_out;
    logic load;
    logic up_down;
    logic reset;
                
    clocking dr_cb@(posedge clock);
        default input #1 output #1;
        output data_in;
        output load;
        output up_down;
        output reset;
    endclocking
            
    clocking wr_cb@(posedge clock);
        default input #1 output #1;
        input data_in;
        input load;
        input up_down;
        input reset;
    endclocking
    
    clocking rd_cb@(posedge clock);
        default input #1 output #1;
        input data_out;
    endclocking

    modport DRV_MP(clocking dr_cb);
    modport WR_MON_MP(clocking wr_cb);
    modport RD_MON_MP(clocking rd_cb);
endinterface

//-----------------------------Transaction--------------------------
class counter_trans;
    rand logic [3:0]data_in;
    logic [3:0]data_out;
    rand bit load;
    rand bit up_down;
    rand bit reset;

    constraint c1 {data_in inside {[0:11]};}
    constraint c2 {load dist {1 := 30, 0 := 70};}
    constraint c3 {up_down dist {1 := 50,0 := 50};}
    constraint c4 {reset dist {1 := 10,0 := 90};}

    virtual function void display(input string s);
        $display("----------%s----------",s);
        $display("up_down = %0d",up_down);
        $display("load = %0d",load);
        $display("data_in = %0d",data_in);
        $display("data_out = %0d",data_out);
        $display("reset=%0d",reset);
        $display("-----------------------------------");
    endfunction

    function void post_randomize();
        display("randomization completed");
    endfunction
endclass

//----------------------------generator-----------------------------------
import counter_pkg::*;

class counter_gen;
    counter_trans trans_h;
    mailbox #(counter_trans) gen2dr;

    function new(mailbox #(counter_trans) gen2dr);
        this.gen2dr = gen2dr;
        trans_h = new();
    endfunction

    virtual task start();
        for(int i=0;i<number_of_transactions;i++) begin
            trans_h.randomize();
            gen2dr.put(trans_h);
        end
    endtask
endclass

//-----------------------write driver---------------------------------
class counter_driver;
    virtual counter_if.DRV_MP dr_if;
    mailbox #(counter_trans) gen2dr;

    function new(virtual counter_if.DRV_MP dr_if, mailbox #(counter_trans) gen2dr);
        this.dr_if = dr_if;
        this.gen2dr = gen2dr;
    endfunction

    virtual task drive(counter_trans trans);
        @(dr_if.dr_cb);
        dr_if.dr_cb.load <= trans.load;
        dr_if.dr_cb.data_in <= trans.data_in;
        dr_if.dr_cb.up_down <= trans.up_down;
        dr_if.dr_cb.reset <= trans.reset;
        trans.display("driver");
    endtask

    virtual task start();
        forever begin
            counter_trans trans;
            gen2dr.get(trans);
            drive(trans);
        end
    endtask
endclass

//------------------------write monitor------------------------------------
class counter_wr_mon;
    virtual counter_if.WR_MON_MP wr_mon_if;
    mailbox #(counter_trans) mon2rm;

    function new(virtual counter_if.WR_MON_MP wr_mon_if, mailbox #(counter_trans) mon2rm);
        this.wr_mon_if = wr_mon_if;
        this.mon2rm = mon2rm;
    endfunction

    virtual task monitor();
        counter_trans wr_data = new();
        @(wr_mon_if.wr_cb);
        wr_data.load = wr_mon_if.wr_cb.load;
        wr_data.reset = wr_mon_if.wr_cb.reset;
        wr_data.up_down = wr_mon_if.wr_cb.up_down;
        wr_data.data_in = wr_mon_if.wr_cb.data_in;
        mon2rm.put(wr_data);
    endtask

    virtual task start();
        forever begin
            monitor();
        end
    endtask
endclass

//------------------read monitor------------------------------
class counter_rd_mon;
    virtual counter_if.RD_MON_MP rd_mon_if;
    mailbox #(counter_trans) mon2sb;

    function new(virtual counter_if.RD_MON_MP rd_mon_if, mailbox #(counter_trans) mon2sb);
        this.rd_mon_if = rd_mon_if;
        this.mon2sb = mon2sb;
    endfunction

    virtual task monitor();
        counter_trans rd_data = new();
        @(rd_mon_if.rd_cb);
        rd_data.data_out = rd_mon_if.rd_cb.data_out;
        mon2sb.put(rd_data);
    endtask

    virtual task start();
        forever begin
            monitor();
        end
    endtask
endclass

//-------------------refence model------------------------------
class counter_ref;
    mailbox #(counter_trans) wrmon2rm;
    mailbox #(counter_trans) rm2sb;

    function new(mailbox #(counter_trans) wrmon2rm, mailbox #(counter_trans) rm2sb);
        this.wrmon2rm = wrmon2rm;
        this.rm2sb = rm2sb;
    endfunction

    virtual task process_transaction(counter_trans trans);
        static logic[3:0] ref_count = 0;
        
        if(trans.reset)
            ref_count = 4'd0;
        else if(trans.load)
            ref_count = trans.data_in;
        else if(trans.up_down == 0) begin
            if(ref_count == 4'd11)
                ref_count = 4'd0;
            else
                ref_count = ref_count + 1;
        end
        else begin
            if(ref_count == 4'd0)
                ref_count = 4'd11;
            else
                ref_count = ref_count - 1;
        end
        
        trans.data_out = ref_count;
    endtask

    virtual task start();
        forever begin
            counter_trans trans;
            wrmon2rm.get(trans);
            process_transaction(trans);
            rm2sb.put(trans);
        end
    endtask
endclass

//-------------------------scoreboard---------------------------
class counter_sb;
    event DONE;
    counter_trans rm_data_h;
    counter_trans sb_data;
    counter_trans cov_data;
    static int ref_data, rm_data, data_verified;
    mailbox #(counter_trans)  ref2sb;
    mailbox #(counter_trans) rdm2sb;

    // COVERGROUP
    covergroup cg_control;
        cp_reset: coverpoint cov_data.reset {
            bins active = {1};
            bins inactive = {0};
        }
        cp_load: coverpoint cov_data.load {
            bins active = {1};
            bins inactive = {0};
        }
        cp_up_down: coverpoint cov_data.up_down {
            bins count_up = {0};
            bins count_down = {1};
        }
    endgroup
    
    covergroup cg_data;
        cp_data_in: coverpoint cov_data.data_in {
            bins valid[] = {[0:11]};
        }
        cp_data_out: coverpoint cov_data.data_out {
            bins valid[] = {[0:11]};
        }
    endgroup

    cg_control ctrl_cov;
    cg_data data_cov;

    function new(mailbox #(counter_trans) ref2sb, mailbox #(counter_trans) rdm2sb);
        this.ref2sb = ref2sb;
        this.rdm2sb = rdm2sb;
        ctrl_cov = new();
        data_cov = new();
    endfunction

    virtual task start();
        forever begin
            ref2sb.get(rm_data_h);
            ref_data++;
            rdm2sb.get(sb_data);
            rm_data++;
            check(sb_data);
        end
    endtask

    virtual task check(counter_trans rdata);
        if(rm_data_h.data_out == rdata.data_out)
            $display("Time=%0t: ✓ Verified: Exp=%0d, Act=%0d", $time, rm_data_h.data_out, rdata.data_out);
        else
            $display("Time=%0t: ✗ Mismatch: Exp=%0d, Act=%0d", $time, rm_data_h.data_out, rdata.data_out);

        data_verified++;
        cov_data = new rm_data_h;
        ctrl_cov.sample();
        data_cov.sample();
        
        if(data_verified == number_of_transactions)
            ->DONE;
    endtask

    function void report();
        real ctrl_cov_per = ctrl_cov.get_coverage();
        real data_cov_per = data_cov.get_coverage();
        
        $display("\n========== FINAL REPORT ==========");
        $display("Transactions: %0d", data_verified);
        $display("Control Coverage: %0.2f%%", ctrl_cov_per);
        $display("Data Coverage:    %0.2f%%", data_cov_per);
        $display("================================");
    endfunction
endclass

//---------------------Enviroment--------------------------
class counter_env;
    virtual counter_if.DRV_MP dr_if;
    virtual counter_if.WR_MON_MP wr_mon_if;
    virtual counter_if.RD_MON_MP rd_mon_if;
    
    mailbox #(counter_trans) gen2dr = new();
    mailbox #(counter_trans) rm2sb = new();
    mailbox #(counter_trans) mon2sb = new();
    mailbox #(counter_trans) mon2rm = new();
    
    counter_gen gen_h;
    counter_wr_mon wrmon_h;
    counter_driver dri_h;
    counter_rd_mon rdmon_h;
    counter_sb sb_h;
    counter_ref mob_h;

    function new(virtual counter_if.DRV_MP dr_if,
                 virtual counter_if.WR_MON_MP wr_mon_if,
                 virtual counter_if.RD_MON_MP rd_mon_if);
        this.dr_if = dr_if;
        this.wr_mon_if = wr_mon_if;
        this.rd_mon_if = rd_mon_if;
    endfunction

    virtual task build();
        gen_h = new(gen2dr);
        dri_h = new(dr_if, gen2dr);
        wrmon_h = new(wr_mon_if, mon2rm);
        rdmon_h = new(rd_mon_if, mon2sb);
        mob_h = new(mon2rm, rm2sb);
        sb_h = new(rm2sb, mon2sb);
    endtask

    virtual task start();
        fork
            gen_h.start();
            dri_h.start();
            wrmon_h.start();
            rdmon_h.start();
            mob_h.start();
            sb_h.start();
        join_none
    endtask

    virtual task stop();
        wait(sb_h.DONE.triggered);
    endtask

    virtual task run();
        start();
        stop();
        sb_h.report();
    endtask
endclass

//--------------------------Testcases---------------------------------    
class test;
    virtual counter_if.DRV_MP dr_if;
    virtual counter_if.WR_MON_MP wr_mon_if;
    virtual counter_if.RD_MON_MP rd_mon_if;
    counter_env env_h;

    function new(virtual counter_if.DRV_MP dr_if,
                 virtual counter_if.WR_MON_MP wr_mon_if,
                 virtual counter_if.RD_MON_MP rd_mon_if);
        this.dr_if = dr_if;
        this.wr_mon_if = wr_mon_if;
        this.rd_mon_if = rd_mon_if;
        env_h = new(dr_if, wr_mon_if, rd_mon_if);
    endfunction

    virtual task build();
        env_h.build();
    endtask

    virtual task run();
        env_h.run();
    endtask
endclass

//-----------------------Top model----------------------------
module top();
    import counter_pkg::*;
    
    parameter cycle = 10;
    reg clock;
    
    counter_if DUV_IF(clock);
    counter DUV(.clock(clock),
                .data_in(DUV_IF.data_in),
                .load(DUV_IF.load),
                .up_down(DUV_IF.up_down),
                .reset(DUV_IF.reset),
                .data_out(DUV_IF.data_out));
    
    test t_h;

    initial begin
        clock = 0;
        // Initialize signals
        DUV_IF.reset = 1;
        #20;
        DUV_IF.reset = 0;
        
        // Create test with proper modports
        t_h = new(DUV_IF.DRV_MP, DUV_IF.WR_MON_MP, DUV_IF.RD_MON_MP);
        number_of_transactions = 20;  // Reduced for testing
        
        $display("[%0t] Starting test with %0d transactions", $time, number_of_transactions);
        
        t_h.build();
        t_h.run();
        
        wait(t_h.env_h.sb_h.DONE.triggered);
        #100;
        $display("[%0t] Test completed", $time);
        $finish;
    end
    
    always #(cycle/2) clock = ~clock;
endmodule

