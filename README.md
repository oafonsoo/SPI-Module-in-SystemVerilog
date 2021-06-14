# SPI-Module-in-SystemVerilog
Master and Slaves Modules in SystemVerilog language to SPI Communication 

Description: SPI (Serial Peripheral Interface) Master
              
Sends a byte one bit at a time on o_mosi and will also receive byte data one bit at a time on i_miso.               

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

/* Description: SPI (Serial Peripheral Interface) Slave

// Note:  The Maximum frequency of the SPI can be the same as FPGA's clock , as long as you don't register the mosi and sclk, 
however, in that case you need guarantee the stable of the input signals. Other point is than, more high the speed, the signal can be more unstable, this way, It's advisable you keep the signal register. 
So, in cases where these signals are register the FPGA's frequency should be at least 4x sclk, i.e i_Clk >= 4*i_sclk

          If you desire a SPI of the 16 bit, You will reach it with a bit change in the logic.    

