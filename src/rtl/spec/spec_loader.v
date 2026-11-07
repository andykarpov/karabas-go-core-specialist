`timescale 1ns / 1ps
`default_nettype wire

/*
 spec_loader.v (the shape of orion_loader.v of karabas-go-core-orion128)

 What the firmware loads, one master on the aux port of spec_sram. The ROM loader writes at
 rom_addr. An FL item writes by the slot of file_slot (the mcu writes a byte in ten clocks or less
 often; the machine is in reset meanwhile):
   slot 1  a tape file .rks into the main RAM
   slot 2  a Monitor of the Specialist at 200000 (up to 12 KB, C000-EFFF)
   slot 3  a ROM of the MX at 210000 (up to 48 KB)
   slot 7  the ROM of SDOS at 21C000 (up to 4 KB, D000-DFFF of the Specialist)
   slot 0  the ROM of the MX2 at 220000 (64 KB)

 .rks, as Emu80 SpecFileLoader reads it: an optional E6, an optional name (D9 D9 D9, the name, E6;
 one or two D9 alone are the start address),
 the start and end addresses (low byte first), the bytes from start to end, a checksum (ignored).
 At the end of the file rks_ok tells that all the bytes came, rks_start is the start address.
*/

module spec_loader (
	input wire clk,

	input wire rom_active,
	input wire [21:0] rom_addr,
	input wire [7:0] rom_data,
	input wire rom_wr,

	input wire file_active,
	input wire [7:0] file_slot,
	input wire [31:0] file_addr,
	input wire [7:0] file_data,
	input wire file_wr,

	output reg [15:0] rks_start = 16'd0,
	output reg rks_ok = 1'b0,

	output reg aux_req = 1'b0,
	output reg [21:0] aux_addr = 22'd0,
	output reg [7:0] aux_din = 8'd0,
	input wire aux_ack
);

// a write waits here for the port
reg pend = 1'b0;
reg [21:0] pend_addr = 22'd0;
reg [7:0] pend_data = 8'd0;

// .rks
localparam R_FIRST = 4'd0, R_NAME = 4'd1, R_S0 = 4'd2, R_S1 = 4'd3, R_E0 = 4'd4, R_E1 = 4'd5, R_DATA = 4'd6,
           R_END = 4'd7, R_D1 = 4'd8, R_D2 = 4'd9;
reg [3:0] rs = R_FIRST;
reg e6 = 1'b0;            // the leading E6 was there
reg [15:0] cur = 16'd0;
reg [15:0] last = 16'd0;

always @(posedge clk) begin
	if (rom_wr) begin
		pend <= 1'b1;
		pend_addr <= rom_addr;
		pend_data <= rom_data;
	end
	else if (file_wr) begin
		if (file_slot == 8'd2) begin
			pend <= 1'b1;
			pend_addr <= { 8'b10000000, file_addr[13:0] };
			pend_data <= file_data;
		end
		else if (file_slot == 8'd3) begin
			pend <= 1'b1;
			pend_addr <= { 6'b100001, file_addr[15:0] };
			pend_data <= file_data;
		end
		else if (file_slot == 8'd7) begin
			pend <= 1'b1;
			pend_addr <= { 10'b1000011100, file_addr[11:0] };
			pend_data <= file_data;
		end
		else if (file_slot == 8'd0) begin
			pend <= 1'b1;
			pend_addr <= { 6'b100010, file_addr[15:0] };
			pend_data <= file_data;
		end
		else if (file_slot == 8'd1) begin
			if (file_addr == 32'd0) begin
				rks_ok <= 1'b0;
				e6 <= 1'b0;
			end
			case (file_addr == 32'd0 ? R_FIRST : rs)
				R_FIRST:
					if (file_data == 8'hE6 && (file_addr == 32'd0 || !e6)) begin
						e6 <= 1'b1;
						rs <= R_FIRST;
					end
					else if (file_data == 8'hD9) begin
						rks_start[7:0] <= file_data;   // a start at xxD9, unless two more D9 follow
						rs <= R_D1;
					end
					else begin
						rks_start[7:0] <= file_data;
						rs <= R_S1;
					end
				R_D1:
					if (file_data == 8'hD9)
						rs <= R_D2;
					else begin
						rks_start[15:8] <= file_data;
						rs <= R_E0;
					end
				R_D2:
					if (file_data == 8'hD9)
						rs <= R_NAME;
					else begin
						rks_start[15:8] <= 8'hD9;
						last[7:0] <= file_data;
						rs <= R_E1;
					end
				R_NAME:
					if (file_data == 8'hE6)
						rs <= R_S0;
				R_S0: begin
					rks_start[7:0] <= file_data;
					rs <= R_S1;
				end
				R_S1: begin
					rks_start[15:8] <= file_data;
					rs <= R_E0;
				end
				R_E0: begin
					last[7:0] <= file_data;
					rs <= R_E1;
				end
				R_E1: begin
					last[15:8] <= file_data;
					cur <= rks_start;
					rs <= R_DATA;
				end
				R_DATA: begin
					pend <= 1'b1;
					pend_addr <= { 5'd0, cur, 1'b0 };
					pend_data <= file_data;
					cur <= cur + 16'd1;
					if (cur == last) begin
						rks_ok <= 1'b1;
						rs <= R_END;
					end
				end
				default: ;
			endcase
		end
	end

	// the port
	if (aux_ack)
		aux_req <= 1'b0;
	else if (!aux_req && pend) begin
		aux_req <= 1'b1;
		aux_addr <= pend_addr;
		aux_din <= pend_data;
		if (!rom_wr && !file_wr)
			pend <= 1'b0;
	end
end

endmodule
