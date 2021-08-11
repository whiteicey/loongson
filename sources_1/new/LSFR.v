`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2021/07/19 10:23:34
// Design Name: 
// Module Name: LSFR
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`include "defines.v"

module LSFR(
    input               clk,
    input               rst,
    output reg[7:0]     rand       
    );
    
    wire[7:0] seed = 8'b11111111;
    always @(posedge clk) begin
        if (rst == `RstEnable)   rand <= seed;
        else begin
            rand[0] <= rand[7];
            rand[1] <= rand[0];
            rand[2] <= rand[1];
            rand[3] <= rand[2];
            rand[4] <= rand[3] ^ rand[7];
            rand[5] <= rand[4] ^ rand[7];
            rand[6] <= rand[5] ^ rand[7];
            rand[7] <= rand[6];
        end
    end
    
endmodule
