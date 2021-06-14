/*
 Description: SPI (Serial Peripheral Interface) Master
              
              Sends a byte one bit at a time on o_mosi
              Will also receive byte data one bit at a time on i_miso.               

Note: Sclk Frequency is equal to fsclk = Fpga Frequency / 2(n+1), where n is DIVIDE_FREQUENCY_SPI parameter      
              
 Parameters:  DIVIDE_FREQUENCY_SPI = See note above .
 							
 							SPI_MODE
              Mode | Clock Polarity (CPOL) | Clock Phase (CPHA)
               0   |             0             |        0
               1   |             0             |        1
               2   |             1             |        0
               3   |             1             |        1
              See: https://en.wikipedia.org/wiki/Serial_Peripheral_Interface#/media/File:SPI_timing_diagram2.svg
						
							FRAME FORMAT : 0 - MSB and 1 - LSB 
							SS_PIN_ENABLE : 1 - Enable the ss by Module. 0- Enable the ss by Module. 
															0- The signal is set up in High-Z. 
															In this case you need create the ss signal by yourself. 
															It's Advisable using  o_ss module signal and forward for desire slave. But it feel free.

Attention : If you use the multi-master, You need manage the i_Clk_en with the other cs signal to avoid start 
the communication while other master is using the bus. 
The same way, you need to guarantee than other masters don't try to use bus during communication this master. 

Attention : Before the pulse i_tx_ready must ensure that o_busy is low.

*/
module SPIMaster #(parameter DIVIDE_FREQUENCY_SPI = 0, MODE = 0, FRAME_FORMAT = 0, SS_PIN_ENABLE=1) (
	input                  i_Clk       , // Clock
	input                  i_Clk_en    , // Clock Enable
	input                  i_Rst_n     , // Asynchronous reset active low
	input                  i_tx_ready  , // Data to transmit ready
	input  byte  unsigned  i_tx_byte   , // Data byte to be sent 
	output byte  unsigned  o_rx_byte   , // Data received. 
	input                  i_miso      , // Data received in last communication ready
	output logic           o_mosi      , // SPI MOSI
	output logic           o_sclk      , // SPI SCLK
	output logic           o_ss        , // Slave Select / If you will use more than one slave you should be forward the signal for wanted slaves.
	output logic           o_byte_ready, // Data received in last communication ready.
	output logic           o_busy				 // Communication is running .
);

// Variable Declarations to SPI MODE select

bit         w_Clk               ;
logic [1:0] w_mode_select = MODE; // Passing parameter to variable. Avoiding something bugs during module synthesize.
logic       w_CPOL              ;
logic       w_CPHA              ;


// 0 - MSB and 1 - LSB 
bit r_frame_formart = bit'(FRAME_FORMAT); // Passing paramater to variable. Avoiding something bug during module synthesize.

// Variable Declarations to Sclk configurations 
logic [$clog2(DIVIDE_FREQUENCY_SPI):0] r_cont_sclk  ;
bit                                    r_sclk       ;
bit                                    r_edge_detect;



// Variables Declaration to store tx and rx byte datas
byte unsigned r_tx_byte, w_tx_byte;
byte unsigned r_rx_byte;

// Auxilar variables
bit r_ss  ;
bit r_mosi;
logic[3:0] 	r_cycle_count  ;
logic [7:0] r_count_pos_com;

// Typedef Enum of the FSM states
typedef enum logic[2:0] {
	STATE_IDLE,
	STATE_PRE_COMM,
	STATE_COMM,
	STATE_POS_COMM
}state_t;

state_t state, next_state;

// FSM update state
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
	if(~i_Rst_n) begin
		state <= STATE_IDLE;
	end else begin
		state <= next_state;
	end
end

// FSM combinational logic
always_comb begin
	next_state = state ;

	case (state)

		STATE_IDLE : begin
			if (i_tx_ready) begin
				next_state = STATE_PRE_COMM ;
			end
		end

		STATE_PRE_COMM : begin
			next_state = STATE_COMM;
		end

		STATE_COMM : begin
			if (r_cycle_count >= 4'd8 && r_edge_detect) begin
				next_state = STATE_POS_COMM ;
			end
		end

		STATE_POS_COMM : begin
			if(r_count_pos_com == DIVIDE_FREQUENCY_SPI >> 1) begin // Time to slave detect last edge clock . Default is DIVIDE_FREQUENCY_SPI by 2. But if necessy change this value, it's free .
				next_state = STATE_IDLE;
			end
		end

	endcase
end

// Assigns
assign w_Clk     = i_Clk_en ? i_Clk : '0; // Clock enable.
assign o_mosi    = !r_ss ? r_mosi : 'z; // If the communication isn't running, the mosi signal should be in High-Impedance State

// Combinational logic to define SPI MODE.
always_comb begin

	if(w_mode_select == 2'd0) begin
		w_CPOL = '0;
		w_CPHA = '0;
	end else if (w_mode_select == 2'd1) begin
		w_CPOL = 1'd0;
		w_CPHA = 1'd1;
	end else if (w_mode_select == 2'd2) begin
		w_CPOL = 1'd1;
		w_CPHA = 1'd0;
	end else if (w_mode_select == 2'd3) begin
		w_CPOL = 1'd1;
		w_CPHA = 1'd1;
	end else begin 
		w_CPOL = 1'bz;
		w_CPHA = 1'bz;
	end
end

// Shift Register of the tx buffer.
always_comb begin
	if (!r_frame_formart) begin
		w_tx_byte = r_tx_byte << r_cycle_count;
	end else begin
		w_tx_byte = r_tx_byte >> r_cycle_count;
	end
end

// Process to register byte data to tx buffer  
// Always tx_ready pulse the data containg in i_tx_byte will be passing to r_tx_byte (Buffer).
// Please check the o_busy pulse before send pulse to i_tx_ready.
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
	if(~i_Rst_n) begin
		r_tx_byte <= '0;
	end else begin
		if (i_tx_ready && state==STATE_IDLE) begin
			r_tx_byte <= i_tx_byte;
		end 
	end
end

// Update busy state to outside module.
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
	if(~i_Rst_n) begin
		o_busy <= '0;
	end else begin
		if (!state==STATE_IDLE) begin
			o_busy <= 1'd1;
		end else  begin
			o_busy <= '0;
		end
	end
end

// If wish use the ss signal generate by this module, set SS_PIN_ENABLE like 1 otherwise shoud be set like 0. 
// If SS_PIN_ENABLE is zero means than o_ss will in Z-state and you should be generate ss signal by yourself.
// If will use multi-slave you should be driven ss signal to correct slave.

/*If will use multi-master you should be driven not ss signal of the other master to clk_en port. 
 In this case the clock this module is inactive and any signal will be ignored. */
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
	if(~i_Rst_n) begin
		r_ss <= 1'd1;
	end else begin
		if (state == STATE_PRE_COMM) begin
			r_ss <= '0;
		end
		if (state == STATE_POS_COMM && (r_count_pos_com == DIVIDE_FREQUENCY_SPI >> 1)) begin
			r_ss <= 1'd1;
		end
	end
end

always_comb begin
	if (SS_PIN_ENABLE) begin
		o_ss = r_ss;
	end else begin
		o_ss = 1'bz;
	end
end

// Process to pass data bit from tx  buffer to mosi pin.
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
	if(~i_Rst_n) begin
		r_mosi        <= '0;
		r_cycle_count <= '0;
	end else begin
		if ((state == STATE_PRE_COMM) && !w_CPHA) begin
			if(r_frame_formart) begin
				r_mosi <= w_tx_byte[0];
			end else begin
				r_mosi <= w_tx_byte[7];
			end
			r_cycle_count <= r_cycle_count + 3'd1;
		end
		else if ((state == STATE_COMM) || (state == STATE_POS_COMM)) begin
			if (!w_CPHA) begin
				if (!r_sclk && r_edge_detect) begin
					if(r_frame_formart) begin
						r_mosi <= w_tx_byte[0];
					end else begin
						r_mosi <= w_tx_byte[7];
					end
					r_cycle_count <= r_cycle_count + 3'd1;
				end
			end
			else if (w_CPHA) begin
				if (r_sclk && r_edge_detect) begin
					if(r_frame_formart) begin
						r_mosi <= w_tx_byte[0];
					end else begin
						r_mosi <= w_tx_byte[7];
					end
					r_cycle_count <= r_cycle_count + 3'd1;
				end
			end
		end
		else if (state==STATE_IDLE) begin
			r_cycle_count <= '0;
		end
	end
end 

// Process to count the pulses of the FPGA Clock to clock change edge.
always_ff @(posedge w_Clk or negedge i_Rst_n) begin 
	if(~i_Rst_n) begin
		r_cont_sclk <= '0;
	end else begin
		if(state==STATE_COMM) begin
			if (r_cont_sclk == DIVIDE_FREQUENCY_SPI) begin
				r_cont_sclk <= '0;
			end else begin
				r_cont_sclk <= r_cont_sclk + 1'd1;
			end
		end else begin
			r_cont_sclk <= '0;
		end
	end
end
bit r_edge_detect_tmp;
// Process to change sclk edge. 
// Divide Frequency SPI represent the amount of the FPGA positive edge clock to change the edge of sclk. 
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
	if(~i_Rst_n) begin
		r_sclk <= '0;
		r_edge_detect_tmp <='0;
	end else begin
		r_edge_detect_tmp <= r_edge_detect;
		if (state==STATE_COMM) begin
			if(r_cont_sclk == DIVIDE_FREQUENCY_SPI) begin
				r_sclk        <= !r_sclk;
				r_edge_detect <= 1'd1;
			end else begin
				r_edge_detect <= '0;
			end
		end else  begin
			r_sclk        <= 1'd0;
			r_edge_detect <= '0;
		end
	end
end

// Process adjust sclk to CPOL set up.
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
	if(~i_Rst_n) begin
		o_sclk <= '0;
	end else begin
		if (state==STATE_COMM || state==STATE_POS_COMM) begin
			if (w_CPOL) begin
				o_sclk <= !r_sclk;
			end else begin
				o_sclk <= r_sclk;
			end
		end else begin
			if (w_CPOL) begin
				o_sclk <= 1'd1;
			end else begin
				o_sclk <= '0;
			end
		end
	end
end

// Process to count the time to finish the communication 
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
	if(~i_Rst_n) begin
		r_count_pos_com <= '0;
	end else begin
		if (state == STATE_POS_COMM) begin
			r_count_pos_com <= r_count_pos_com + 1'd1;
		end else if (state == STATE_IDLE) begin
			r_count_pos_com <= '0;
		end
	end
end

// Process to get value from miso input 
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
	if(~i_Rst_n) begin
		r_rx_byte    <= '0;
	end else begin
		if ((w_mode_select==0 || w_mode_select==3) && o_sclk && r_edge_detect_tmp) begin
			if (!r_frame_formart) begin
				r_rx_byte <= {r_rx_byte[6:0],i_miso};
			end else begin
				r_rx_byte <= {i_miso,r_rx_byte[7:1]};
			end
		end
		else if ((w_mode_select==1 || w_mode_select==2) && !o_sclk && r_edge_detect_tmp) begin
			if (!r_frame_formart) begin
				r_rx_byte <= {r_rx_byte[6:0],i_miso};
			end else begin
				r_rx_byte <= {i_miso,r_rx_byte[7:1]};
			end
		end
	end
end

// Process pass rx_byte buffer to output of the module after finish of the communication. 
// This module also generate pulse of data valid. 
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
	if(~i_Rst_n) begin
		o_rx_byte    <= '0;
		o_byte_ready <= '0;
	end else begin
		if (state==STATE_IDLE && o_busy) begin
			o_rx_byte    <= r_rx_byte;
			o_byte_ready <= 1'd1;
		end else begin
			o_byte_ready <= '0;
		end
	end
end

endmodule