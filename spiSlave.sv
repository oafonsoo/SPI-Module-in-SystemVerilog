///////////////////////////////////////////////////////////////////////////////
/* Description: SPI (Serial Peripheral Interface) Slave

// Note:  The Maximum frequency of the SPI can be the same as FPGA's clock , as long as you don't register the mosi and sclk, 
however, in that case you need guarantee the stable of the input signals. Other point is than, more high the speed, the signal can be more unstable, this way, It's advisable you keep the signal register. 
So, in cases where these signals are register the FPGA's frequency should be at least 4x sclk, i.e i_Clk >= 4*i_sclk

// If you desire a SPI of the 16 bit, You will reach it with a bit change in the logic.     

 Parameters:  SPI_MODE
              Mode | Clock Polarity (CPOL) | Clock Phase (CPHA)
               0   |             0             |        0
               1   |             0             |        1
               2   |             1             |        0
               3   |             1             |        1
              See: https://en.wikipedia.org/wiki/Serial_Peripheral_Interface#/media/File:SPI_timing_diagram2.svg
							
							FRAME FORMAT : 0 - MSB and 1 - LSB 
*/              
///////////////////////////////////////////////////////////////////////////////
module spiSlave #(parameter MODE =0, FRAME_FORMAT = 0) (
	input                  i_Clk        , // Clock.
	input                  i_Clk_en     , // Clock Enable.
	input                  i_Rst_n      , // Asynchronous reset active low
	input                  i_tx_ready   , // Data ready to be register.
	input  byte  unsigned  i_tx_byte    , // Data to sent.
	output byte  unsigned  o_rx_byte    , // Data received.
	output logic           o_byte_ready , // Data received in last communication ready.
	input                  i_mosi       , // SPI MOSI.
	input                  i_sclk       , // SPI CLOCK.
	input                  i_ss         , // Slave Select / If you will use more than one slave you should be forward the signal for wanted slaves.
	output logic           o_miso       , // SPI MISO
	output logic           o_busy         // Communication is running .
);

// Variable Declarations to SPI MODE select
bit         w_Clk               ;
logic [1:0] w_mode_select = MODE; // Passing parameter to variable. Avoiding something bugs during module synthesize.
logic       w_CPOL              ;
logic       w_CPHA              ;

// 0 - MSB and 1 - LSB 
bit r_frame_formart = bit'(FRAME_FORMAT); // Passing parameter to variable. Avoiding something bugs during module synthesize.

// Variables Declaration to store tx and rx byte datas
byte unsigned r_tx_byte, w_tx_byte;
byte unsigned r_rx_byte, r_tx_byte_tmp;

// SPI registers  
logic w_sclk;
logic w_miso;
logic r_mosi;
logic r_sclk;
logic r_ss  ;

// Other Variables 
logic[3:0] r_cycle_count;

//Process to register the external SPI's signals. 
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
	if(~i_Rst_n) begin
		r_mosi <= '0;
		r_sclk <= '0;
		r_ss   <= '0;
	end else begin
		r_mosi <= i_mosi;
		r_sclk <= i_sclk;
		r_ss   <= i_ss;
	end
end

/* If you need of the sclk frequency four time less than FGPA's frequency uncomment the always combination below and comment
the always_ff above. Attention . In this case you need guarantee than your signals will be stable, main the i_sclk and i_ss.
All the case, you can choose if register or nor the signal, but is better keep registered.
*/  

// always_comb begin
// 		r_mosi = i_mosi;
// 		r_sclk = i_sclk;
// 		r_ss   = i_ss;
// end

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

// Assigns
assign w_Clk  = i_Clk_en ? i_Clk : '0; // Clock enable.
assign o_miso = r_ss ? 'z : w_miso;
assign w_sclk = w_CPOL ? !r_sclk : r_sclk;


// Process to register input signal.
// If the communication is running the value doesn't update until the final of the actual communication
// If you need increse the FPGA clock retire the r_ss of the and conditional, but you need garantir than i_tx_ready won't set up during a communication.
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
	if(~i_Rst_n) begin
		r_tx_byte <= '0;
	end else begin
		 if(i_tx_ready && r_ss) begin
		 r_tx_byte <= i_tx_byte;
		end
	end
end

// Process to update communication state to outside module.
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
	if(~i_Rst_n) begin
		o_busy <= '0;
	end else begin
		o_busy <= !r_ss;
	end
end

// Process to shift datas to pass the value to miso's output
always_comb begin
	if (!r_frame_formart) begin
		w_tx_byte = r_tx_byte << r_cycle_count ;
	end else begin
		w_tx_byte = r_tx_byte >> r_cycle_count ;
	end
end

always_comb begin
	if (!r_frame_formart) begin
		w_miso <= w_tx_byte[7];
	end else begin
		w_miso <= w_tx_byte[0];
	end
end


// Generate is dependent of the SPI mode. The difference is the edge detection in always parameter
generate
	if(MODE == 1 || MODE == 3)

		always_ff @(posedge w_sclk or posedge r_ss) begin
			if(r_ss) begin
				r_cycle_count <= -8'd1;
			end else begin
				r_cycle_count <= r_cycle_count + 1'd1;
			end
		end

	else

		always_ff @(negedge w_sclk or posedge r_ss) begin
			if(r_ss) begin
				r_cycle_count <= '0;
			end else begin
				r_cycle_count <= r_cycle_count + 1'd1;
			end
		end

endgenerate

generate
	if (MODE == 1 || MODE == 3)

		always_ff @(negedge w_sclk or negedge i_Rst_n) begin
			if(~i_Rst_n) begin
				r_rx_byte <= '0;
			end else begin
				if (!r_frame_formart) begin
						r_rx_byte <= {r_rx_byte[6:0],r_mosi};
					end else begin
						r_rx_byte <= {r_mosi,r_rx_byte[7:1]};
					end
			end
		end

		else

			always_ff @(posedge w_sclk or negedge i_Rst_n) begin
				if(~i_Rst_n) begin
					r_rx_byte     <= '0;
				end else begin
					if (!r_frame_formart) begin
						r_rx_byte <= {r_rx_byte[6:0],r_mosi};
					end else begin
						r_rx_byte <= {r_mosi,r_rx_byte[7:1]};
					end
				end
			end

endgenerate

// Update the signal received after end communication. The o_byte_ready is a pulse of the FPGA clock.
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
	if(~i_Rst_n) begin
		o_rx_byte    <= '0;
		o_byte_ready <= '0;
	end else begin
		if (r_ss && o_busy) begin
			o_rx_byte    <= r_rx_byte ;
			o_byte_ready <= 1'd1;
		end else begin 
			o_byte_ready <= '0;
		end
	end 
end

endmodule