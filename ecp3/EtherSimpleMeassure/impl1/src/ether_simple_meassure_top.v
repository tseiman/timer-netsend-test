/*
 * Verilog code for the simple Etherent packet measure setup, EtherSimpleMeasure which is part
 * of the timer-netsend-test project
 * 
 * File Name: ether_simple_meassure_top.v
 * by Thomas Schmidt 2016, t.schmidt (at) md-network.de
 *
 * This is the top implementation of the meassurment setup. The FPGA receives Ethernet packets on PHY1,
 * in case the ethernet frame has a destination MAC of 01:02:03:04:05:06 the frame is accepted. 
 * The FPGA is counting packets, meassuring the total time span when receiving packets (to calculate packets/sec)
 * and stores the smallest time interval between 2 packets and the largest. The time (total, minimum frame gab/maximum frame gap)
 * is meassured in 125MHz clock ticks.
 * 
 * The Lattice ECP3 board offers a FTDI USB serial connection to the FPGA. In the second part of this module gives access via USB RS232 serial
 * to the meassurement registers. The RS232 Terminal has to use 115200 8N2.
 * To obtain the meassurement data the terminal has to send a 'G' to (g)et the data. The data structure looks as following:
 * 
 *   +----------------+--------------+------------+------------+-----------+
 *   |   total time   | # of packets |    min     |    max     | checksum  |
 *   +---- 5bytes ----+--- 3bytes ---+-- 4bytes --+-- 4bytes --+-- 1byte --+
 * 
 * and contains following fields:
 *  - total summary of inter packet delay of all received packets in number of 
 *    125MHz clock ticks since last (g)et, 5-bytes host byte order
 *  - number of packets received since last (g)et, 3-bytes host byte order
 *  - minimum inter packet delay occourd since last (g)et in number of 125MHz clock ticks, 4-bytes host byte order
 *  - maximum inter packet delay occourd since last (g)et in number of 125MHz clock ticks, 4-bytes host byte order
 *  - checksum - this is a 8 bit filed which is simply summed up from all 16 bytes transmitted from the other fields 
 *    the checksum will overflow the final value after sum of 16 bytes is stored in the last byte, 1-byte
 *
 * In case the terminal detects a problem with the checksum, the terminal can request the data again by sending 'R' to (r)etransmit the last dataset. 
 * In case a 'G' (g)et is sent the  timer counter (total, minimum frame gab/maximum frame gap) are reset.
 *
 */



module top (
  input  clock
 , input  reset_n
 , output phy1_rst_n
 , input  phy1_125M_clk
 , output phy1_gtx_clk
, input  phy1_rx_clk
, input  phy1_rx_dv
, input  [7:0] phy1_rx_data
, output phy1_mii_clk //= 1'b0
, inout  phy1_mii_data // = 1'b0
, output  TEST_reset_n
, output TEST_phy_rst_n 
, output  TEST_phy_125M_clk 
, output  TEST_phy_tx_clk
, output [7:0] TEST_phy_tx_data
, output  TEST_phy_rx_dv
, output  TEST_phy_rx_er 
, output  [7:0] TEST_phy_rx_data
, output  TEST_phy_col
, output TEST_phy_mii_clk //= 1'b0
, output  TEST_phy_mii_data // = 1'b0

  // Switch/LED 
, output TEST_uart_rx
, output TEST_uart_tx
, input UART_rx
, output UART_tx

, output TEST_read_gmii
, output TEST_busy_gmii


);

reg tx_en;
reg[11:0] counter;
reg[7:0]  tx_data;

assign phy1_tx_en   = tx_en;
assign phy1_tx_data = tx_data;
assign phy1_gtx_clk = phy1_125M_clk;

assign phy1_gtx_clk= phy1_125M_clk;

wire [15:0] buffer;
wire [7:0] rx_buffer;


assign TEST_reset_n 	 = reset_n;
assign TEST_phy_rst_n 	 = phy1_rst_n;
assign TEST_phy_mii_clk  = phy1_mii_clk;
assign TEST_phy_mii_data = phy1_mii_data;

// cold reset (260 clock)
reg [8:0] cold_rst = 0;
reg [8:0] hard_conf_reg = 8'd0;
reg read_gmii;
reg write_gmii;
wire busy_gmii;



reg [17:0] device_addr_cnt=0;
wire cold_rst_end  = (cold_rst >= 9'd260);
wire hard_configure_end  = (cold_rst >= 9'd460);
assign phy1_rst_n  = cold_rst_end;

always @(posedge clock or negedge reset_n) begin
	if (reset_n == 1'b0) begin
		read_gmii <= 1'd0;
		cold_rst <= 9'd0;
	end else begin
		cold_rst <= !hard_configure_end ? cold_rst + 9'd1 : 9'd460;
		if(phy1_rst_n && (!busy_gmii)) begin
			read_gmii <= 1'd1;
		end else begin
			read_gmii <= 1'd0;
		end
	end
	
end

wire clk_2mhz;
wire clk_1hz;

freq_divider gmii_div0 (
	.clk			(clock)
,	.rst		(reset_n)
,	.clk_out	(clk_2mhz)
,	.clk_out_1hz	(clk_1hz)
);

wire phy_mdata_tri, phy_mdata_out;
assign phy1_mii_data = phy_mdata_tri ? phy_mdata_out : 1'bz;
assign phy_mdata_in = phy1_mii_data;
reg [15:0] data_out_buffer;

gmii gmii0 (
	.clk(clk_2mhz)
,	.read(read_gmii)
,	.write(1'd0)
,	.device_addr(device_addr_cnt[17:13])
,	.register_addr(5'h1)
,	.data()
, 	.mdc(phy1_mii_clk)
, 	.mdio_out(phy_mdata_out)
, 	.mdio_in(phy_mdata_in)
, 	.mdio_write_flag(phy_mdata_tri)
, 	.busy(busy_gmii)
,	.write_r(TEST_phy_col)

);

assign TEST_phy_125M_clk = clock; // phy1_rx_clk;
assign TEST_busy_gmii = busy_gmii;
assign TEST_read_gmii = read_gmii;


assign TEST_phy_rx_data = phy1_rx_data;


wire sys_rst = ~reset_n;
reg [10:0] rxcounter;
reg [7:0] rx_packet_accept_cnt;

assign TEST_phy_tx_data = rx_packet_accept_cnt;

reg [47:0] eth_addr_dst;
reg reset_counters;
reg reset_counters_done;
reg reset_delay_counter;

reg [31:0] delay_counter_actual;
reg [39:0] delay_counter_sum; /* sumary counter is 40bit - can hold sum of 256 * max of actual (32bit) */
reg [23:0] delay_counter_sum_number; 
reg [31:0] delay_counter_max;
reg [31:0] delay_counter_min;



/* ------------------------------------------------------------------------- */
/* this implements the ethernet meassurement                                 */
/* ------------------------------------------------------------------------- */
always @(posedge phy1_rx_clk) begin
	if (sys_rst) begin    			/* we reset all value buffers on total system reset */
		rxcounter <= 11'd0;
		rx_packet_accept_cnt <= 8'd0;
	
		eth_addr_dst <= 48'h0;

		reset_counters_done<= 1'd0;
		
		delay_counter_actual <=  32'd0;
		delay_counter_sum <= 39'd0;
		delay_counter_sum_number <= 24'd0;
		delay_counter_max <=  32'h0;
		delay_counter_min <=  32'hffffffff;
		
		reset_delay_counter <= 1'd0;

	end else begin					/* wer receive data and process incomming data */

		delay_counter_actual <=delay_counter_actual + 32'd1;

		if (phy1_rx_dv) begin
			rxcounter <= rxcounter + 11'd1;

			case (rxcounter) 
				11'd8:  eth_addr_dst[47:40]		<= phy1_rx_data; /* extract destination ethernet addr */
				11'd9: eth_addr_dst[39:32]		<= phy1_rx_data;
				11'd10: eth_addr_dst[31:24]		<= phy1_rx_data;
				11'd11: eth_addr_dst[23:16]		<= phy1_rx_data;
				11'd12: eth_addr_dst[15:8]		<= phy1_rx_data;
				11'd13: eth_addr_dst[7:0]		<= phy1_rx_data;
				
				

				11'd14: begin					/*				for simplicity we accept the packet already if destination MAC is OK, there will be no other participants on meassure ehthernet segment */
							 if (eth_addr_dst[47:0]    == 48'h010203040506) begin
								 reset_delay_counter  <= 1'd1;
								rx_packet_accept_cnt <=  rx_packet_accept_cnt + 8'd1;
								delay_counter_sum <= delay_counter_actual + delay_counter_sum;
								delay_counter_sum_number <= delay_counter_sum_number + 24'd1;
								if(delay_counter_sum_number > 1'd1) begin
									if(delay_counter_actual > delay_counter_max) delay_counter_max <= delay_counter_actual; /* nach 2 clock zyklen erreicht wenn meassure_now */
									if(delay_counter_actual < delay_counter_min) delay_counter_min <= delay_counter_actual;
								end

							 end
						end
			endcase



		end else begin 				/* if we don't receive data we keep buffers initilized - same as on reset */
			rxcounter <= 11'd0;
			eth_addr_dst <= 48'h0;
		end
		
	end /* end if(phy1_rx_dv) */

	if(reset_counters & ~reset_counters_done) begin
		reset_counters_done <= 1'd1;
		
		delay_counter_sum  <= 39'd0;
		delay_counter_sum_number <= 24'd0;
		delay_counter_max <=  32'h0;
		delay_counter_min <=  32'hffffffff;
	end else if (~reset_counters & reset_counters_done) begin
		reset_counters_done <= 1'd0;
	end	
	if(reset_delay_counter) begin
		reset_delay_counter <= 1'd0;
		delay_counter_actual <= 32'd1;
	end

end   /* end always */



wire uartbusy;
reg enable_send;
wire data_ready;
wire data_idle;


wire [7:0] data_in;
reg [39:0] delay_counter_sum_temp; 
reg [23:0] delay_counter_sum_number_temp; 

reg [5:0] uart_send_data_enable;
reg [3:0] uart_send_data_count;
reg [7:0] uart_byte_to_send;

reg [31:0] delay_counter_max_temp;
reg [31:0] delay_counter_min_temp;

reg [7:0] simple_checksum;


assign TEST_phy_tx_clk = UART_tx;

/* ------------------------------------------------------------------------- */
/* this part implemetns the RS232 serial access to the meassurment registers */
/* ------------------------------------------------------------------------- */
always @(posedge clock) begin
	if (sys_rst) begin    		
		enable_send <= 1'd0;
		uart_send_data_enable <= 6'd0;		
		uart_byte_to_send <= 8'd0;		
		simple_checksum  <= 8'd0;	
		reset_counters<= 1'd0;
		
	end else begin	

		if(~data_idle) begin
			
			if(data_ready & (data_in==7'h47) & (uart_send_data_enable == 6'd0)) begin  // we got a 'G' for (g)et, in this case we'll transmit the registers and reset all measurement
				uart_send_data_enable <= 6'd1;	
			end
			if(data_ready & (data_in==7'h52) & (uart_send_data_enable == 6'd0)) begin // we got a 'R' for (r)etransmit, in this we'll reread the registers and transmit them on RS232 but not reset the measurement
				uart_send_data_enable <= 6'd3;					
			end
		end
		
		
		if(uartbusy == 1'd0) begin
			case(uart_send_data_enable)
				 6'd1: begin
	 				delay_counter_sum_temp <= delay_counter_sum;
					delay_counter_sum_number_temp <= delay_counter_sum_number;

					delay_counter_max_temp <=  delay_counter_max; 
					delay_counter_min_temp <=  delay_counter_min;					 

					uart_send_data_enable <= 6'd2;						
				 end

				 6'd2: begin
						reset_counters<= 1'd1;
						uart_send_data_enable <= 6'd3;						
				 end
				 6'd3: begin
						simple_checksum  <= 8'd0;
						uart_send_data_enable <= 6'd4;						
				 end

				 6'd4: begin
						uart_byte_to_send <= delay_counter_sum_temp[7:0];
						simple_checksum <= delay_counter_sum_temp[7:0];
						enable_send <= 1'd1;
						uart_send_data_enable <= 6'd5;
					end
				 6'd5: begin
						uart_byte_to_send <= delay_counter_sum_temp[15:8];
						simple_checksum <= simple_checksum + delay_counter_sum_temp[15:8];
						enable_send <= 1'd1;
						uart_send_data_enable <= 6'd6;
					end
				 6'd6: begin
						uart_byte_to_send <= delay_counter_sum_temp[23:16];
						simple_checksum <= simple_checksum + delay_counter_sum_temp[23:16];
						enable_send <= 1'd1;
						uart_send_data_enable <= 6'd7;
					end
				 6'd7: begin					 
						uart_byte_to_send <= delay_counter_sum_temp[31:24];
						simple_checksum <= simple_checksum + delay_counter_sum_temp[31:24];
						enable_send <= 1'd1;
						uart_send_data_enable <= 6'd8;
					end
				 6'd8: begin
						uart_byte_to_send <= delay_counter_sum_temp[39:32];
						simple_checksum <= simple_checksum + delay_counter_sum_temp[39:32];
						enable_send <= 1'd1;
						uart_send_data_enable <= 6'd9;
					end
				 6'd9: begin
						uart_byte_to_send <= delay_counter_sum_number_temp[7:0];
						simple_checksum <= simple_checksum + delay_counter_sum_number_temp[7:0];
						enable_send <= 1'd1;
						uart_send_data_enable <= 6'd10;
					end
				 6'd10: begin
						uart_byte_to_send <= delay_counter_sum_number_temp[15:8];
						simple_checksum <= simple_checksum + delay_counter_sum_number_temp[15:8];
						enable_send <= 1'd1;
						uart_send_data_enable <= 6'd11;
					end
				 6'd11: begin
						uart_byte_to_send <= delay_counter_sum_number_temp[23:16];
						simple_checksum <= simple_checksum + delay_counter_sum_number_temp[23:16];
						enable_send <= 1'd1;
						uart_send_data_enable <= 6'd12;
					end
				 6'd12: begin
						uart_byte_to_send <= delay_counter_min_temp[7:0];
						simple_checksum <= simple_checksum + delay_counter_min_temp[7:0];
						enable_send <= 1'd1;
						uart_send_data_enable <= 6'd13;
					end
				 6'd13: begin
						uart_byte_to_send <= delay_counter_min_temp[15:8];
						simple_checksum <= simple_checksum + delay_counter_min_temp[15:8];
						enable_send <= 1'd1;
						uart_send_data_enable <= 6'd14;
					end
				 6'd14: begin
						uart_byte_to_send <= delay_counter_min_temp[23:16];
						simple_checksum <= simple_checksum + delay_counter_min_temp[23:16];
						enable_send <= 1'd1;
						uart_send_data_enable <= 6'd15;
					end
				 6'd15: begin					 
						uart_byte_to_send <= delay_counter_min_temp[31:24];
						simple_checksum <= simple_checksum + delay_counter_min_temp[31:24];
						enable_send <= 1'd1;
						uart_send_data_enable <= 6'd16;
					end
				 6'd16: begin
						uart_byte_to_send <= delay_counter_max_temp[7:0];
						simple_checksum <= simple_checksum + delay_counter_max_temp[7:0];
						enable_send <= 1'd1;
						uart_send_data_enable <= 6'd17;
					end
				 6'd17: begin
						uart_byte_to_send <= delay_counter_max_temp[15:8];
						simple_checksum <= simple_checksum + delay_counter_max_temp[15:8];
						enable_send <= 1'd1;
						uart_send_data_enable <= 6'd18;
					end
				 6'd18: begin
						uart_byte_to_send <= delay_counter_max_temp[23:16];
						simple_checksum <= simple_checksum + delay_counter_max_temp[23:16];
						enable_send <= 1'd1;
						uart_send_data_enable <= 6'd19;
					end
				 6'd19: begin					 
						uart_byte_to_send <= delay_counter_max_temp[31:24];
						simple_checksum <= simple_checksum + delay_counter_max_temp[31:24];
						enable_send <= 1'd1;
						uart_send_data_enable <= 6'd20;
					end
				 6'd20: begin					 
						uart_byte_to_send <= simple_checksum;
						enable_send <= 1'd1;
						uart_send_data_enable <= 6'd21;
					end

				 6'd21: begin
					 uart_send_data_enable <= 6'd0;
						enable_send <= 1'd0;
					end
				default: begin
						enable_send <= 1'd0;
					end
			endcase
		end /* end if(uartbusy == 1'd0) */
		
		if(reset_counters & reset_counters_done) begin 
			reset_counters <= 1'd0;
		end
		
	end	/* end if reset */
end


async_transmitter uart0_out (
	.clk(clock)
,	.TxD_start(enable_send)
,	.TxD_data(uart_byte_to_send)
,	.TxD(UART_tx)
,	.TxD_busy(uartbusy)

);


async_receiver uart0_in (
	.clk(clock)
,	.RxD(UART_rx)
,	.RxD_data_ready(data_ready)
,	.RxD_data(data_in)
,	.RxD_idle(data_idle)
,	.RxD_endofpacket()
);



endmodule
