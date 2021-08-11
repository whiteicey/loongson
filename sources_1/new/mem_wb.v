//////////////////////////////////////////////////////////////////////////////////
// MEM/WB寄存器
//////////////////////////////////////////////////////////////////////////////////
`include "defines.v"

module mem_wb(
    input wire clk,
    input wire rst,
    input wire flush,

    input wire[5:0] stall,

    //来自访存阶段的信息    
    input wire[`RegAddrBus] mem_waddr,
    input wire mem_we,
    input wire[`RegBus] mem_wdata,
    input wire mem_we_hilo, 
    input wire[`RegBus] mem_hi,
    input wire[`RegBus] mem_lo,
    input wire mem_cp0_we,
    input wire[7:0] mem_cp0_waddr,
    input wire[`RegBus] mem_cp0_wdata,
    input wire[`RegBus] mem_pc,

    //送到回写阶段的信息
    output reg[`RegAddrBus] wb_waddr,
    output reg wb_we,
    output reg[`RegBus] wb_wdata,
    output reg wb_we_hilo,  
    output reg[`RegBus] wb_hi,
    output reg[`RegBus] wb_lo,
    output reg wb_cp0_we,
    output reg[7:0] wb_cp0_waddr,
    output reg[`RegBus] wb_cp0_wdata,
    output reg[`RegBus] wb_pc
    );

    always @ (posedge clk) begin
        if(rst == `RstEnable || flush) begin
            wb_waddr <= `NOPRegAddr;
            wb_we <= `WriteDisable;
            wb_wdata <= `ZeroWord;  
            wb_we_hilo <= `WriteDisable;  
            wb_hi <= `ZeroWord;
            wb_lo <= `ZeroWord;
            wb_cp0_we <= `WriteDisable;
            wb_cp0_waddr <= 8'b00000000;
            wb_cp0_wdata <= `ZeroWord;
            wb_pc <= `ZeroWord;
        end else if (stall[4] == `Stop && stall[5] == `NoStop) begin
            wb_waddr <= `NOPRegAddr;
            wb_we <= `WriteDisable;
            wb_wdata <= `ZeroWord;  
            wb_we_hilo <= `WriteDisable;  
            wb_hi <= `ZeroWord;
            wb_lo <= `ZeroWord;
            wb_cp0_we <= `WriteDisable;
            wb_cp0_waddr <= 8'b00000000;
            wb_cp0_wdata <= `ZeroWord;
            wb_pc <= `ZeroWord;
        end else if (stall[4] == `NoStop) begin
            wb_waddr <= mem_waddr;
            wb_we <= mem_we;
            wb_wdata <= mem_wdata;
            wb_we_hilo <= mem_we_hilo;  
            wb_hi <= mem_hi;
            wb_lo <= mem_lo;
            wb_cp0_we <= mem_cp0_we;
            wb_cp0_waddr <= mem_cp0_waddr;
            wb_cp0_wdata <= mem_cp0_wdata;
            wb_pc <= mem_pc;
        end else begin
        end
    end 

endmodule
