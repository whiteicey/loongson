`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// IF
//////////////////////////////////////////////////////////////////////////////////


//2021.7.6：icache优化，容量扩大，组相联映射
`include "defines.v"

module sram_if(
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

    output wire[`RegBus] pc,
    
    // 指令存储器使能信号
    output reg req,
    input wire addr_ok,
    input wire data_ok,
    output wire[3:0] burst,
    output wire[`RegBus] addr,
    input wire[511:0] inst_rdata_i,
    output wire[`RegBus] inst_rdata_o,

    output wire stallreq
    );

    wire ce;

    pc_reg pc_reg0(
        .clk(clk),
        .rst(rst), 
        .stall(stall),
        .is_branch_i(is_branch_i),
        .branch_target_address_i(branch_target_address_i),

        .flush(flush),
        .epc(epc),
        .exceptions_o(exceptions_o),

        .pc(pc),
        .ce(ce)
    );

    //--------------- icache部分 ---------------
    // icache代替原来的if握手
    assign addr = {pc[31:6],6'b000000};
    assign burst = 4'b1111;

    reg[2:0] state;
    wire[17:0] tag = pc[31:14];
    // index应为8线
    wire[7:0] index = pc[13:6];
    wire[3:0] offset = pc[5:2];

    wire[31:0] block[0:15];//临时存储取到的块
    wire[17:0] tag_out;
    wire valid_out;
    wire hit;
    
    assign hit = valid_out & (tag_out == tag);//判断是否hit
    assign inst_rdata_o = (hit == 1'b1) ? block[offset] : 32'h00000000;
    assign stallreq = ce && (~hit || state == 2'b01 || state == 2'b10);

    reg flush_wait;

    wire cache_we = flush_wait ? 1'b0 : data_ok;
    `define IDLE 3'b000
    `define WAITADDROK 3'b001
    `define ADDROK 3'b010
    `define DATAOK 3'b011
    `define FLUSHWAIT 3'b100

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            state <= `IDLE;
            req <= 1'b0;
            flush_wait <= 1'b0;
        end else if (flush) begin
            if(state != `IDLE && state != `DATAOK) begin
                state <= `FLUSHWAIT;
                flush_wait <= 1'b1;
            end 
        end else if (ce == 1'b1) begin
            case (state)
                `IDLE: begin
                    if(pc[1:0] != 2'b00) begin
                        req <= 1'b0;
                    end else if(!hit) begin//cache读缺失
                        state <= `WAITADDROK;//进入等待地址确认状态
                        req <= 1'b1;
                    end else begin
                        req <= 1'b0;
                    end
                end
                `WAITADDROK: begin
                    if(addr_ok == 1'b1) begin
                        req <= 1'b0;
                        state <= `ADDROK;
                    end
                end
                `ADDROK: begin
                    if(data_ok == 1'b1) begin
                        state <= `DATAOK;
                    end 
                end
                `DATAOK: begin
                    state <= `IDLE;
                end
                `FLUSHWAIT: begin
                    if(data_ok) begin
                        state <= `IDLE;
                        flush_wait <= 1'b0;
                    end
                end
            endcase
        end
    end

    valid_ram valid(//给index获得vaild
        .a(index),
        .d(1'b1),
        .clk(clk),
        .we(cache_we),
        .spo(valid_out)
    );

    tag_ram tag0(
        .a(index),
        .d(tag),
        .clk(clk),
        .we(cache_we),
        .spo(tag_out)
    );
    //数据寄存器
     icache_demo_0 data0(
        .a(index),
        .clk(~clk),
        .d(inst_rdata_i[511:480]),
        .spo(block[0]),
        .we(cache_we)
    );
    icache_demo_0 data1(
        .a(index),
        .clk(~clk),
        .d(inst_rdata_i[479:448]),
        .spo(block[1]),
        .we(cache_we)
    );
    icache_demo_0 data2(
        .a(index),
        .clk(~clk),
        .d(inst_rdata_i[447:416]),
        .spo(block[2]),
        .we(cache_we)
    );
    icache_demo_0 data3(
        .a(index),
        .clk(~clk),
        .d(inst_rdata_i[415:384]),
        .spo(block[3]),
        .we(cache_we)
    );
    icache_demo_0 data4(
        .a(index),
        .clk(~clk),
        .d(inst_rdata_i[383:352]),
        .spo(block[4]),
        .we(cache_we)
    );
    icache_demo_0 data5(
        .a(index),
        .clk(~clk),
        .d(inst_rdata_i[351:320]),
        .spo(block[5]),
        .we(cache_we)
    );
    icache_demo_0 data6(
        .a(index),
        .clk(~clk),
        .d(inst_rdata_i[319:288]),
        .spo(block[6]),
        .we(cache_we)
    );
    icache_demo_0 data7(
        .a(index),
        .clk(~clk),
        .d(inst_rdata_i[287:256]),
        .spo(block[7]),
        .we(cache_we)
    );
    icache_demo_0 data8(
        .a(index),
        .clk(~clk),
        .d(inst_rdata_i[255:224]),
        .spo(block[8]),
        .we(cache_we)
    );
    icache_demo_0 data9(
        .a(index),
        .clk(~clk),
        .d(inst_rdata_i[223:192]),
        .spo(block[9]),
        .we(cache_we)
    );
    icache_demo_0 data10(
        .a(index),
        .clk(~clk),
        .d(inst_rdata_i[191:160]),
        .spo(block[10]),
        .we(cache_we)
    );
    icache_demo_0 data11(
        .a(index),
        .clk(~clk),
        .d(inst_rdata_i[159:128]),
        .spo(block[11]),
        .we(cache_we)
    );
    icache_demo_0 data12(
        .a(index),
        .clk(~clk),
        .d(inst_rdata_i[127:96]),
        .spo(block[12]),
        .we(cache_we)
    );
    icache_demo_0 data13(
        .a(index),
        .clk(~clk),
        .d(inst_rdata_i[95:64]),
        .spo(block[13]),
        .we(cache_we)
    );
    icache_demo_0 data14(
        .a(index),
        .clk(~clk),
        .d(inst_rdata_i[63:32]),
        .spo(block[14]),
        .we(cache_we)
    );
    icache_demo_0 data15(
        .a(index),
        .clk(~clk),
        .d(inst_rdata_i[31:0]),
        .spo(block[15]),
        .we(cache_we)
    );

endmodule
