
///DEMO Change 1

//-----------------------------------------------------------------------------
// Company:      RiRe Technologies Pvt Ltd
// Author:       Mahesh Kshirsagar
// 
// Create Date:  07-Apr-2026
// File Name:    generic_trigger_wdt.v
// Module Name:  generic_trigger_wdt
// Project Name: <COMMON_IP_LIBRARY>
//
// Description:  A standalone, trigger-based 32-bit Watchdog Timer.
//               Functional Behavior:
//               - Timer starts counting from 0 when 'trig' is asserted.
//               - Timer runs only when 'active' is high.
//               - If count reaches (threshold - 1), 'timeout' is asserted
//                 and timer stops automatically.
//               - 'halt' stops the timer before timeout (success condition).
//               - 'clr' stops the timer and resets the counter.
//               - 'timeout_ack' clears the timeout flag .
//
//               Debug / Observability Features:
//               - 'halt_count' captures the counter value at the moment
//                 'halt' is asserted during active operation.
//               - 'halt_count' holds the last valid captured value until reset.
//               - Debug state output 'wdt_state' provides internal visibility.
//
//               DFT / Test Mode:
//               - When 'test_mode' is enabled, threshold is internally forced
//                 to a small value (15) to accelerate simulation and ATPG.
//
//               Design Notes:
//               - Timeout is sticky until cleared by 'timeout_ack'.
//               - 'halt_count' updates only when (halt && active).
//               - All state updates are synchronous to clk with async reset.
//
//-----------------------------------------------------------------------------
// TIMING REFERENCE GUIDE (Assuming 50 MHz System Clock / 20ns Period):
// Formula: Timeout (seconds) = Threshold / Frequency (Hz)
// 
// Threshold Value | Hexadecimal | Real-World Time
// ----------------|-------------|-------------------------
// 1               | 0x00000001  | 20 ns (Minimum)
// 50              | 0x00000032  | 1 us
// 50,000          | 0x0000C350  | 1 ms
// 500,000         | 0x0007A120  | 10 ms
// 1,750,000       | 0x001AAE60  | 35 ms (SMBus Spec)
// 50,000,000      | 0x02FAF080  | 1 Second
// 4,294,967,295   | 0xFFFFFFFF  | ~85.89 Seconds (Maximum)
//-----------------------------------------------------------------------------
//
// Revision History:
// Rev 1.00 - 06-Apr-2026 - Initial implementation of trigger-based watchdog timer (AM)
// Rev 1.01 - 07-Apr-2026 - Added halt_count debug feature to capture count at halt
//                        - Converted halt_count to output register for observability
//                        - Added reset initialization for halt_count
//                        - Ensured halt_count updates only when (halt && active)
//                        
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

	module generic_trigger_wdt #(
	parameter WIDTH = 32
	)(
	input wire clk,
	input wire rst_n,

	//-------------------------------------------------------------------------
	// Control Signal Behavior Summary:
	// - trig        : Starts or restarts timer from 0
	// - halt        : Stops timer (indicates successful completion)
	// - clr         : Stops timer and clears counter to 0
	// - timeout_ack : Clears timeout flag after expiration
	// - en          : Global enable (acts like soft reset when low)
	//-------------------------------------------------------------------------

	// DFT / Test Interface
	input  wire             test_mode,   

	// Control Interface
	input  wire             en,          
	input  wire             trig,        
	input  wire             halt,        
	input  wire             clr,         
	input  wire             timeout_ack, 
	input  wire [WIDTH-1:0] threshold,   

	// Status Outputs
	output reg              timeout,     
	output reg              active,      

	//-------------------------------------------------------------------------
	// halt_count:
	// Captures the counter value at the exact moment halt is asserted
	// while the timer is active. This helps measure execution time
	// before successful completion.
	// Value is retained until next reset or overwrite.
	//-------------------------------------------------------------------------
	output reg [WIDTH-1:0]  halt_count,  

	// Validation/Monitor Interface
	output wire [3:0]       wdt_state    

	);

	reg [WIDTH-1:0] count;

	//-------------------------------------------------------------------------
	// 1. DFT Threshold Scaling
	// During test_mode, threshold is reduced to a small value (15)
	// so timeout can be observed in very few clock cycles.
	// This avoids long simulation/ATPG runtime when large thresholds are used.
	//-------------------------------------------------------------------------
	wire [WIDTH-1:0] effective_threshold;
	assign effective_threshold = (test_mode) ? {{ (WIDTH-4){1'b0} }, 4'hF} : threshold;

	//-------------------------------------------------------------------------
	// Priority Order inside main logic:
	// 1. timeout_ack (clear timeout)
	// 2. trig        (start/restart)
	// 3. halt / clr  (stop conditions)
	// 4. counting    (normal operation)
	//-------------------------------------------------------------------------

	//-------------------------------------------------------------------------
	// 2. Watchdog Core Logic
	//-------------------------------------------------------------------------
	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			count       <= {WIDTH{1'b0}};
			timeout     <= 1'b0;
			active      <= 1'b0;
			halt_count  <= {WIDTH{1'b0}};

		end else if (!en) begin
			count       <= {WIDTH{1'b0}};
			timeout     <= 1'b0;
			active      <= 1'b0;
			halt_count  <= {WIDTH{1'b0}};

		end else begin
			
			// Priority 1: Manual Timeout Acknowledge
			if (timeout_ack) begin
				timeout <= 1'b0;
			end

			// Priority 2: Trigger (Start/Restart)
			if (trig) begin
				count   <= {WIDTH{1'b0}};
				active  <= 1'b1;
				timeout <= 1'b0;
			end 

			// Priority 3: Halt (Success) or Clear
			else if (halt || clr) begin
				active <= 1'b0;

				// Capture only valid running count
				if (halt && active) begin
					halt_count <= count;
				end

				if (clr) begin
					count <= {WIDTH{1'b0}};
				end
			end

			// Priority 4: Internal Counting Logic
			else if (active) begin
				if (count >= (effective_threshold - 1)) begin
					timeout <= 1'b1;
					active  <= 1'b0; 
				end else begin
					count <= count + 1'b1;
				end
			end
		end
	end

	//-------------------------------------------------------------------------
	// 3. Validation/Debug Port
	// Provides compact visibility of internal state:
	// {en, active, timeout, trig}
	// Useful for waveform debug and on-chip logic analyzers.
	//-------------------------------------------------------------------------
	assign wdt_state = {en, active, timeout, trig};

	//-------------------------------------------------------------------------
	// SYSTEMVERILOG ASSERTIONS (Verification)
	//-------------------------------------------------------------------------
	// synthesis translate_off
	always @(posedge clk) begin
		if (rst_n && en && active) begin
			if (threshold == {WIDTH{1'b0}}) 
				$error("WDT Error: Threshold set to 0 while watchdog is active!");
			
			if (trig && halt)
				$warning("WDT Warning: Simultaneous Trig and Halt detected.");
		end
	end
	// synthesis translate_on

	endmodule
