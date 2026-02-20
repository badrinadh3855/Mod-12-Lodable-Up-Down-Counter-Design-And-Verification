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

	//driver 
	modport DRV_MP(clocking dr_cb);

	//write monitor 
	modport WR_MON_MP(clocking wr_cb);

	//read monitor
	modport RD_MON_MP(clocking rd_cb);

endinterface

//-----------------------------Transaction--------------------------
class counter_trans;

	rand logic [3:0]data_in;
	logic [3:0]data_out;
	rand bit load;
	rand bit up_down;
	rand bit reset;

	//constraits
	constraint c1 {data_in inside {[0:11]};}
	constraint c2 {load dist {1 := 50, 0 := 50};}
	constraint c3 {up_down dist {1 := 50,0 := 50};}
	constraint c4 {reset dist {1 := 50,0 := 50};}
	//constraint c6{reset dist{1:=1,0:=99};}
	constraint c5{load ==0 || up_down ==1 || data_in==0;}

	//Display method
	virtual function void display(input string s);
		begin
	   		$display("----------%s----------",s);
			$display("no_of_transaction",number_of_transactions);
	   	 	$display("up_down = %0d",up_down);
	    		$display("load = %0d",load);
	    		$display("data_in = %0d",data_in);
	    		$display("data_out = %0d",data_out);
	    		$display("reset=%0d",reset);
	    		$display("-----------------------------------");
		end
    	endfunction

	function void post_randomize();
		display("randomization completed");
	endfunction
endclass

//----------------------------generator-----------------------------------
import counter_pkg::*;

class counter_gen;
	counter_trans trans_h;
	counter_trans data2send;

	mailbox #(counter_trans) gen2dr;


	function new(mailbox #(counter_trans) gen2dr);
		this.gen2dr = gen2dr;
		this.trans_h = new();
	endfunction

	virtual task start();
		fork
	    
			for(int i=0;i<number_of_transactions;i++)
				begin
					trans_h.randomize();
					data2send = new trans_h;
					gen2dr.put(data2send);
				end
       	    
		join_none
	endtask
endclass

//-----------------------write driver---------------------------------
class counter_driver;
	virtual counter_if.DRV_MP dr_if;
	mailbox #(counter_trans) gen2dr;
	counter_trans data2duv;
									
	function new(virtual counter_if.DRV_MP dr_if,mailbox #(counter_trans) gen2dr);
		this.dr_if = dr_if;
		this.gen2dr = gen2dr;
	endfunction

	virtual task drive();
		@(dr_if.dr_cb);
		dr_if.dr_cb.load <= data2duv.load;
		dr_if.dr_cb.data_in <= data2duv.data_in;
		dr_if.dr_cb.up_down <= data2duv.up_down;
		dr_if.dr_cb.reset <= data2duv.reset;
		data2duv.display("driver");
	endtask

	virtual task start();
      		fork
			forever
	   			begin
					gen2dr.get(data2duv);
					drive();
	   			end
		join_none
     	endtask

endclass

//------------------------write monitor------------------------------------
class counter_wr_mon;
	virtual counter_if.WR_MON_MP wr_mon_if;
	mailbox #(counter_trans) mon2rm;
	counter_trans wr_data;

	function new(virtual counter_if.WR_MON_MP wr_mon_if,mailbox #(counter_trans)mon2rm);
		this.wr_mon_if = wr_mon_if;
		this.mon2rm = mon2rm;
		this.wr_data = new();
	endfunction

	virtual task monitor();
		@(wr_mon_if.wr_cb);
		begin
			wr_data.load = wr_mon_if.wr_cb.load;
			wr_data.reset = wr_mon_if.wr_cb.reset;
			repeat(10)  wr_data.up_down = wr_mon_if.wr_cb.up_down;
			wr_data.data_in = wr_mon_if.wr_cb.data_in;
		end

	endtask

	virtual task start();
		fork
			forever
	   			begin
					monitor();
					mon2rm.put(wr_data);
					$display("write monitor is working");
	   			end
		join_none
	endtask
endclass

//------------------read monitor------------------------------
class counter_rd_mon;
	virtual counter_if.RD_MON_MP rd_mon_if;
	mailbox #(counter_trans) mon2sb;
	counter_trans rd_data;

	function new (virtual counter_if.RD_MON_MP rd_mon_if,mailbox #(counter_trans)mon2sb);
		this.rd_mon_if = rd_mon_if;
		this.mon2sb = mon2sb;
		this.rd_data = new();
	endfunction

	virtual task monitor();
			@(rd_mon_if.rd_cb);
			rd_data.data_out = rd_mon_if.rd_cb.data_out;
			rd_data.display("from the read monitor");

	endtask

	virtual task start();
		fork
			forever
	  			begin
					monitor();
					mon2sb.put(rd_data);
					$display("read monitor is working");
	   			end
		join_none
	endtask

endclass

//-------------------refence model------------------------------
class counter_ref;

	counter_trans w_data = new();

	static logic[3:0] ref_count;

	mailbox #(counter_trans) wrmon2rm;
	mailbox #(counter_trans) rm2sb;

	function new(mailbox #(counter_trans) wrmon2rm,mailbox #(counter_trans) rm2sb);
		this.wrmon2rm = wrmon2rm;
		this.rm2sb = rm2sb;
	endfunction

	virtual task count_mod(counter_trans model_counter);
		begin
 	 		if(w_data.reset)
                		ref_count <= 4'd0;
             		else if(w_data.load)
                		w_data.data_out <= w_data.data_in;
             		else if(w_data.up_down)
                		begin
                    			if(w_data.data_out == 4'd11)
                      				ref_count <= 4'd0;
                    			else
                       				ref_count<= ref_count + 1;
                		end
             		else
                		begin
                    			if(w_data.data_out == 4'd0)
                       				ref_count <= 4'd11;
                    			else
                       				ref_count <= ref_count - 1;
                		end

	

		end 
	endtask


	virtual task start();
		fork 
    			forever 
	      			begin
					count_mod(w_data);
					wrmon2rm.get(w_data);
	      				rm2sb.put(w_data);
	      			end
	
     		join_none
  	endtask

endclass

//-------------------------scoreboard---------------------------
class counter_sb;
	
	event DONE;

   	counter_trans rm_data_h;
  	counter_trans sb_data;
   	counter_trans cov_data;
	//counter_trans coverage1;

   	static int ref_data,rm_data,data_verified;

	mailbox #(counter_trans)  ref2sb;
	mailbox #(counter_trans) rdm2sb;

	function new(mailbox #(counter_trans)  ref2sb,
		     mailbox #(counter_trans) rdm2sb);
		this.ref2sb = ref2sb;
		this.rdm2sb = rdm2sb;
		this.coverage = new();
	endfunction

	covergroup coverage;
		RST:coverpoint cov_data.reset;
		MODE:coverpoint cov_data.up_down;
		LOAD:coverpoint cov_data.load;
		DATA_IN:coverpoint cov_data.data_in{bins a = {[0:11]};}
		DATA_OUT:coverpoint cov_data.data_out{bins a = {[0:11]};}

		CR:cross RST,MODE,LOAD,DATA_IN;
	endgroup

		virtual task start();
			fork
   				forever
					begin
	   					ref2sb.get(rm_data_h);
	   					ref_data++;
						rdm2sb.get(sb_data);
	  					rm_data++;
						check(sb_data);
        				end
    			join_none
		endtask


	virtual task check(counter_trans rdata);
		if(rm_data_h.data_out == rdata.data_out)
	  		$display("data verified");
		else
	   		$display("data mismatch");

			data_verified++;
			cov_data= new rm_data_h;
			coverage.sample();
			//$display(rm_data_h);
		if(data_verified == number_of_transactions)
			begin
				->DONE;
			end
		$display("coverage =%d",coverage.get_coverage());
	endtask

 	function void report();
		$display(".........SCOREBOARD............");
		//$display("coverage=%d",coverage1);
		$display("dat_generated = %d",rm_data);
		$display("data received = %0d",ref_data);
		$display("data_verified = %0d",data_verified);
		$display("----------------------------");
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
		dri_h = new(dr_if,gen2dr);
		wrmon_h = new(wr_mon_if,mon2rm);
		rdmon_h = new(rd_mon_if,mon2sb);
		mob_h = new(mon2rm,rm2sb);
		sb_h = new(rm2sb,mon2sb);
	endtask

	/*virtual task reset_duv();
		@(dr_if.dr_cb);
  	 	dr_if.dr_cb.reset<= 1'b0;
		repeat(2);
		@(dr_if.dr_cb);
		dr_if.dr_cb.reset <= 1'b1;
	endtask*/

	virtual task start();
		gen_h.start();
		dri_h.start();
		wrmon_h.start();
		rdmon_h.start();
		mob_h.start();
		sb_h.start();
	endtask

	virtual task stop();
   		wait(sb_h.DONE.triggered);
	endtask

	virtual task run();
	//   reset_duv();
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
		this.env_h = new(dr_if,wr_mon_if,rd_mon_if);
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

test t_h;
					
counter DUV(.clock(clock),.data_in(DUV_IF.data_in),.load(DUV_IF.load),.up_down(DUV_IF.up_down),.reset(DUV_IF.reset),.data_out(DUV_IF.data_out));


initial 
     begin
	     begin
		t_h = new(DUV_IF,DUV_IF,DUV_IF);
		number_of_transactions = 200;
		t_h.build();
		t_h.run();
		$finish;
	     end
 end
//Generate the clock
   initial
      begin
         clock = 1'b0;
         forever #(cycle/2) clock = ~clock;
      end

endmodule

//qverilog mod12counter_tb.sv
//vsim -c -coverage work.top \-do "coverage save -onexit cov.ucdb; run -all; exit"
// vcover report -detail cov.ucdb
