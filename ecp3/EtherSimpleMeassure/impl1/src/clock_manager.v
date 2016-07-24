/*
 * Verilog code for the simple Etherent packet measure setup, EtherSimpleMeasure which is part
 * of the timer-netsend-test project
 * 
 * File Name: clock_manager.v
 * by Thomas Schmidt 2016, t.schmidt (at) md-network.de
 *
 * This file contains the module freq_divider module 
 * to generate different low frequency clocks
 *
 */

module freq_divider(
	input 	clk
,	input 	rst
,	output reg clk_out
,	output reg clk_out_1hz

);
reg [15:0] counter;
reg [23:0] counter_1hz;

always @(posedge clk or negedge rst) begin

	if(!rst) begin
		counter<=16'd0;
		clk_out <= 1'b0;
	end else if(counter==16'd12) begin
		counter<=16'd0;
		clk_out <= ~clk_out;
	end else begin 
		counter<=counter+1;
	end

	if(!rst) begin
		counter_1hz<=24'd0;
		clk_out_1hz <= 1'b0;
	end else if(counter_1hz==24'd500000) begin
		counter_1hz<=24'd0;
		clk_out_1hz <= ~clk_out_1hz;
	end else begin 
		counter_1hz<=counter_1hz+1;
	end

	
end




endmodule
