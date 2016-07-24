/*
 * Verilog code for the simple Etherent packet measure setup, EtherSimpleMeasure which is part
 * of the timer-netsend-test project
 * 
 * File Name: gmii.v
 * (Part of) this source was somewhere from the internet. Unfortunately i lost the place where i got it from.
 * If you feel the code belongs to you please let me know.
 *
 * obtained from internet and modified by Thomas Schmidt 2016, t.schmidt (at) md-network.de
 *
 * This file contains the gmii module to communicate with the ethernet PHY
 *
 */





module gmii(
	clk
,	read
,	write
,	device_addr
,	register_addr
,	data
, 	mdc
, 	mdio_out
, 	mdio_in
, 	mdio_write_flag
, 	busy
, 	write_r
);

input 			clk;
input 			read;
input 			write;
input	[0:4]	device_addr;
input	[0:4]	register_addr;
inout 	[15:0]	data;
output reg		mdc;
output reg		mdio_out;
input 			mdio_in;
output reg		mdio_write_flag;
output reg		busy;
output 			write_r;



reg [6:0] bit_counter;
reg mdc_enable;
reg	[15:0]	data_reg;
reg read_flag;
reg write_flag;


function reg inbetween;
	input [7:0] low,value, high;
	begin
	  inbetween = value >= low && value <= high;
	end
endfunction
	

always @(posedge clk) begin


	
	if(read || write) begin // rw action
		read_flag <= read;  // may theinstanciator deassigns 
		write_flag <= write; // read write flag during write process ...
		mdc_enable <= 1'd1;
	end else begin
		read_flag <= read_flag;
		write_flag <= write_flag;
		mdc_enable <= mdc_enable;
	end





/*
	The MDC/MDIO read/write operation 
	+-------+-------------------------------------+-------------+-----------+------------------+--------------------+----+------------------+---------+
	| r/w	|   32 bit preamble all set to 1      | Frame start | rw opcode | 5bit device addr | 5bit register addr | TA |    16bit Data    | Idle    |
	+-------+-------------------------------------+-------------+-----------+------------------+--------------------+----+------------------+---------+
	| read  | 11111111 11111111 11111111 11111111 |      01     |     10    |       01110      |        01111       | zz | zzzzzzzzzzzzzzzz | 111...  |
	+-------+-------------------------------------+-------------+-----------+------------------+--------------------+----+------------------+---------+
	| write | 11111111 11111111 11111111 11111111 |      01     |     01    |       01110      |        01111       | 10 | 0000111111110000 | 111...  |
	+-------+-------------------------------------+-------------+-----------+------------------+--------------------+----+------------------+---------+
	
*/


	if(mdc == 1'd1) begin /* on each mdc rising edge we're setting new data */
		case(1) 
			inbetween(0,bit_counter,31): begin /* 32 bit preamble, means 64 transitions on the mdc */
						busy <= 1'd1;
						mdc_enable <=  1'd1;
						mdio_write_flag <= 1'd1;
						mdio_out <= 1'd1;
					 end
			inbetween(32,bit_counter,32): begin // start of frame _0_1
						busy <= 1'd1;
						mdc_enable <=  1'd1;
						mdio_write_flag <= 1'd1;
						mdio_out <= 1'd0;
					 end
			inbetween(33,bit_counter,33): begin // start of frame 0_1_
						busy <= 1'd1;
						mdc_enable <=  1'd1;
						mdio_write_flag <= 1'd1;
						mdio_out <= 1'd1;
					 end
			inbetween(34,bit_counter,34): begin // set read bit, read=(_1_0) write=(_0_1)
						busy <= 1'd1;
						mdc_enable <=  1'd1;
						mdio_write_flag <= 1'd1;
						mdio_out <= read_flag;
					 end
			inbetween(35,bit_counter,35): begin // set write bit, read=(1_0_) write=(0_1_)
						busy <= 1'd1;
						mdc_enable <=  1'd1;
						mdio_write_flag <= 1'd1;
						mdio_out <= write_flag;
					 end					 
			inbetween(36,bit_counter,40): begin // 5Bit device Addr
						busy <= 1'd1;
						mdc_enable <=  1'd1;
						mdio_write_flag <= 1'd1;
						mdio_out <= device_addr[bit_counter - 36];
					 end
			inbetween(41,bit_counter,45): begin // 5Bit register Addr
						busy <= 1'd1;
						mdc_enable <=  1'd1;
						mdio_write_flag <= 1'd1;
						mdio_out <= register_addr[bit_counter - 41];
					 end
			inbetween(46,bit_counter,46): begin // 1 of 2Bit turnaround  
						busy <= 1'd1;
						mdc_enable <=  1'd1;
						mdio_write_flag <= write_flag; 
						mdio_out <=  write_flag ? 1'd1 : 1'dz; 
					 end
			inbetween(47,bit_counter,47): begin // 2 of 2Bit turnaround  
						busy <= 1'd1;
						mdc_enable <=  1'd1;
						mdio_write_flag <= write_flag; 
						mdio_out <=  write_flag? 1'd0 : 1'dz;    
					 end
			inbetween(48,bit_counter,63): begin // data read or write
						busy <= 1'd1;
						mdc_enable <=  1'd1;
						
						if(read_flag) begin // we read
							mdio_write_flag <= 1'd0;
							data_reg[bit_counter - 48] <= mdio_in;
							mdio_out <=  1'd0; 				// actually we dont care
						end else begin // we write
							mdio_write_flag <= 1'd1;
							mdio_out <= data[bit_counter - 48];
						end
						
					 end

			default: begin
						busy <= 1'd0;
						mdc_enable <=  1'd0;
						mdio_write_flag <= 1'd0;
						mdio_out <=  1'd0; 						
					end
		endcase
		bit_counter<=bit_counter+1;

	end else begin /* if(bit_counter[0] == 1'd1) */
		busy <= busy;
		mdc_enable <= mdc_enable;
		mdio_out <=  mdio_out;
		mdio_write_flag <= mdio_write_flag; 
		bit_counter<=bit_counter;
	end /* if(bit_counter[0] == 1'd1) */

	
	
	mdc <= ~mdc;

end /* always @(posedge clk)  */


	assign data = (read_flag) ? data_reg : data;


endmodule





		
