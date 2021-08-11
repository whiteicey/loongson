`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2021/07/21 04:03:30
// Design Name: 
// Module Name: dirty_regfile
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


module dirty_regfile(
    input               clk,
    input[7:0]          addr,
    input               din,
    input               we,
    output              dout
    );
    reg[255:0]          data;
    reg                 ans;
    assign dout = ans;
    always @(posedge clk) begin
        if (we) begin
            ans <= din;
            data[addr] <= din;
        end
        else
            ans <= data[addr];
    end
endmodule
