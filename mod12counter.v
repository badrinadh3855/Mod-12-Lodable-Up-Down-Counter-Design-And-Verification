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
             else if(up_down ==0)
                begin
                    if(data_out > 4'd11)
                       data_out <= 4'd0;
                    else
                       data_out <= data_out + 1;
                end
             else
                begin
                    if((data_out > 4'd11) ||(data_out<1))
                       data_out <= 4'd11;
                    else
                       data_out <= data_out - 1;
                end

         end
endmodule
