//////////////////////////////////////////////////////////////////////////////////
// PC程序计数器
// 按字节计数
//////////////////////////////////////////////////////////////////////////////////
`include "defines.v"

module pc_reg(
    input wire clk,
    input wire rst, 

    input wire[5:0] stall,

    // 分支跳转信号
    input wire is_branch_i,
    input wire[`RegBus] branch_target_address_i,

    // 异常
    input wire flush,
    input wire[`RegBus] epc,
    output wire[31:0] exceptions_o,

    output reg[`RegBus] pc,
    output wire ce
    );

    assign ce = (pc[1:0] == 2'b00) ? `ChipEnable : `ChipDisable;
    assign exceptions_o = {31'h00000000, (pc[1:0] != 2'b00) ? 1'b1 : 1'b0};
    
    // 修改PC
    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            pc <= 32'hbfc00000;
        end else if (flush) begin
            // 出现异常，使用epc的值
            if (stall[0] == `Stop) begin
                pc <= epc - 4;
            end else begin
                pc <= epc;
            end
        end else if (stall[0] == `NoStop) begin
            // IF未暂停
            if(is_branch_i) begin
                pc <= branch_target_address_i;
            end else begin
                pc <= pc + 4'h4;
            end
        end else begin
        end
    end
    
endmodule
