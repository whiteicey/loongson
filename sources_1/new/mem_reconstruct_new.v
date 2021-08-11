
//////////////////////////////////////////////////////////////////////////////////
// 访存阶段
// 寄存器： 31:24   23:16   15:8   7:0
// 地址：   0x03    0x02    0x01   0x00
// 所以按字节写入0x03时是写入寄存器高8位，sel为1000
// 半字写入时，例如写0x00，实际上写入的数据是寄存器低16位
// 由于这里RAM是32位的位宽，可以选择编址使得其字节地址与寄存器相对应：
// RAM：| 0x03 0x02 0x01 0x00 | 0x07 0x06 0x05 0x04 | ...
// 因为0x00~0x03访问的都是第一个32位的单元，其内部字节如何安排如何编地址就可以随意了
// 最终半字写0x00时sel即为0011，若半字写0x10则sel就是1100了
// 如果最终在外部写入8字节RAM，最终AXI接口的SRAM控制器会做转换（会的吧）
// 关于LWL和LWR，需要按字节顺序想：
// 物理地址下0x01~0x04是一个非对齐的字，要读取进寄存器：
// | 0x00 0x01 0x02 0x03 | 0x04 0x05 0x06 0x07 |
// | a+1  a+2  a+3       |                 a   |
// 转换成上面说的自定义编址（以32位的块访问，块内地址自定义）：
// | 0x03 0x02 0x01 0x00 | 0x07 0x06 0x05 0x04 |
//        a+3  a+2  a+1     a  
// 这时候lwl 0x02 -> a+3 a+2 a+1 ...
//      lwr 0x07 -> ... ... ...  a 
// SWL和SWR刚好是LWL和LWR的逆操作，读哪里写哪里就是了。
//////////////////////////////////////////////////////////////////////////////////
`include "defines.v"

module mem(
    input wire clk,
    input wire rst,
    
    // 来自执行阶段的信息    
    input wire[`RegAddrBus] waddr_i,
    input wire we_i, // 写有效信号
    input wire[`RegBus] wdata_i,
    input wire we_hilo_i,
    input wire[`RegBus] hi_i,
    input wire[`RegBus] lo_i,
    input wire[`AluOpBus] aluop_i,
    input wire[`RegBus] mem_addr_i,
    input wire[`RegBus] reg2_i,
    input wire cp0_we_i,
    input wire[7:0] cp0_waddr_i,
    input wire[`RegBus] cp0_wdata_i,
    input wire[31:0] exceptions_i,
    input wire[`RegBus] pc_i,
    input wire is_in_delayslot_i,

    // CP0，用以判断中断能否发生（未被屏蔽）
    input wire[`RegBus] cp0_status_i,
    input wire[`RegBus] cp0_cause_i,
    input wire[`RegBus] cp0_epc_i,

    // 异常
    output wire[`RegBus] pc_o,
    output wire is_in_delayslot_o,
    output reg exception_occured_o, // 发生异常时下面的字段才有效
    output reg[4:0] exc_code_o,
    output reg[`RegBus] bad_addr_o,
    
    // 送到回写阶段的信息
    output reg[`RegAddrBus] waddr_o,
    output wire we_o,
    output reg[`RegBus] wdata_o,
    output reg we_hilo_o,
    output reg[`RegBus] hi_o,
    output reg[`RegBus] lo_o,
    output reg cp0_we_o,
    output reg[7:0] cp0_waddr_o,
    output reg[`RegBus] cp0_wdata_o,
    
    // 数据RAM
    input wire mem_addr_ok,
    input wire mem_data_ok,
    // 送往数据RAM的信号
    output reg[`RegBus] mem_addr_o,
    output reg mem_wr_o,
    // 寄存器： 31:24   23:16   15:8   7:0
    // strb     1000    0100   0010   0001
    output reg[63:0] mem_strb_o,
    input wire[511:0] mem_data_i,
    output reg[511:0] mem_data_o,
    output reg mem_req_o,
    output wire[3:0] mem_data_burst,
    output reg stallreq
    );



    /*  
        写回式dcache
        三个重要指标：uncache， hit以及op
        uncache作用时，cache等同无效，正常向总线访问, len = 0000

                        hit                     unhit
        op =  read      读cache对应位置         * 写回cache行
                                                ** 
                                                
        
        
        
        
        op = write      直接写cache对应位置
    */
    wire uncache;
    assign uncache = (mem_addr_i[31:29] & 3'b111) == 3'b101;

    reg[3:0] state;
    wire[17:0] tag = mem_addr_i[31:14];
    wire[7:0] index = mem_addr_i[13:6];
    wire[3:0] offset = mem_addr_i[5:2];
    
    wire[7:0] rand;
    LSFR random_generator(
        .clk(clk),
        .rst(rst),
        .rand(rand)
    );

    reg way_choose;

    wire[17:0] tag_out_0;
    wire[17:0] tag_out_1;
    wire[17:0] tag_out_total;
    assign tag_out_total = way_choose ? tag_out_1:tag_out_0;
    wire valid_out_0;
    wire valid_out_1;
    // wire valid_out_total;
    // assign valid_out_total = 

    wire cache_ok;
    assign cache_ok = (!uncache) & (mem_data_ok && state == `READOK);

    wire hit_0;
    wire hit_1;
    wire hit_total;


    // way_choose = 
    always @(*) begin
        if (rst == `RstEnable) begin
            way_choose <= 1'b0;
        end
        else if (state == `IDLE) begin
            if (hit_total) begin
                way_choose <= hit_1;
            end
            else begin
                way_choose <= rand[0];
            end
        end
        else begin
        end
    end
  

    // 选择wr信号
    reg op;

    assign hit_0 = valid_out_0 & (tag_out_0 == tag);
    assign hit_1 = valid_out_1 & (tag_out_1 == tag);
    assign hit_total = hit_0 || hit_1;

    //dirty（脏位）
    wire dirty_in_0;//向cache输入这回的脏位
    wire dirty_in_1;
    // wire dirty_in_total;
    wire dirty_out_0;//这次cache的脏位的最终确定值
    wire dirty_out_1;
    // wire dirty_out_total;

    wire dirty_we_0;//cache判断模块的使能
    wire dirty_we_1;

    //当前地址命中且该次操作为写操作时脏位置1
    assign dirty_in_0 = (hit_0 & op) ? 1'b1 : 1'b0;
    assign dirty_in_1 = (hit_1 & op) ? 1'b1 : 1'b0;
    assign dirty_we_0 = (!way_choose) && ((hit_0 & (op == 1'b1)) || cache_ok) ? 1'b1 : 1'b0;
    assign dirty_we_1 = (way_choose) && ((hit_1 & (op == 1'b1)) || cache_ok) ? 1'b1 : 1'b0;

    reg mem_ce;
    

    // TODO
    // 如果不是uncache，则使用突发传输
    assign mem_data_burst = uncache ? 4'b0000 : 4'b1111;

    wire[31:0] block_0[0:15];
    wire[31:0] block_1[0:15];
    wire[31:0] block_total[0:15];
    wire[511:0] block_data;
    wire[31:0] last_addr;

    assign last_addr = {tag_out_total,index,6'b000000};
    
    
     // 从cache中拿取的数据
    wire[31:0] mem_data_cache_i;
    reg[31:0] mem_data_cache_o;

    assign mem_data_cache_i = uncache ? mem_data_i[31:0] : block_total[offset];

    reg[3:0] mem_strb;

    assign block_total[0] = way_choose ? block_1[0] : block_0[0];
    assign block_total[1] = way_choose ? block_1[1] : block_0[1];
    assign block_total[2] = way_choose ? block_1[2] : block_0[2];
    assign block_total[3] = way_choose ? block_1[3] : block_0[3];
    assign block_total[4] = way_choose ? block_1[4] : block_0[4];
    assign block_total[5] = way_choose ? block_1[5] : block_0[5];
    assign block_total[6] = way_choose ? block_1[6] : block_0[6];
    assign block_total[7] = way_choose ? block_1[7] : block_0[7];
    assign block_total[8] = way_choose ? block_1[8] : block_0[8];
    assign block_total[9] = way_choose ? block_1[9] : block_0[9];
    assign block_total[10] = way_choose ? block_1[10] : block_0[10];
    assign block_total[11] = way_choose ? block_1[11] : block_0[11];
    assign block_total[12] = way_choose ? block_1[12] : block_0[12];
    assign block_total[13] = way_choose ? block_1[13] : block_0[13];
    assign block_total[14] = way_choose ? block_1[14] : block_0[14];
    assign block_total[15] = way_choose ? block_1[15] : block_0[15];

    assign block_data[511:480] = block_total[0];
    assign block_data[479:448] = block_total[1];
    assign block_data[447:416] = block_total[2];
    assign block_data[415:384] = block_total[3];
    assign block_data[383:352] = block_total[4];
    assign block_data[351:320] = block_total[5];
    assign block_data[319:288] = block_total[6];
    assign block_data[287:256] = block_total[7];
    assign block_data[255:224] = block_total[8];
    assign block_data[223:192] = block_total[9];
    assign block_data[191:160] = block_total[10];
    assign block_data[159:128] = block_total[11];
    assign block_data[127:96] = block_total[12];
    assign block_data[95:64] = block_total[13];
    assign block_data[63:32] = block_total[14];
    assign block_data[31:0] = block_total[15];


    always @(*) begin
        if(rst == `RstEnable)begin
            stallreq <= 1'b0;
        end else begin
            case(state) 
                `IDLE: begin
                    if(mem_ce) begin
                        stallreq <= ~hit_total;
                    end else begin
                        stallreq <= `False_v;
                    end
                end
                `READWAIT: begin
                    stallreq <= `True_v;
                end
                `READOK: begin
                    stallreq <= `True_v;
                end
                `WRITEWAIT: begin
                    stallreq <= `True_v;
                end
                `WRITEOK: begin
                    stallreq <= `True_v;
                end
                `UNCACHEWAIT: begin
                    stallreq <= `True_v;
                end
                `UNCACHEOK: begin
                    if (!mem_data_ok) begin
                        // 数据握手不成功，原地等待
                        stallreq <= `True_v;
                    end else begin
                        // 数据握手成功，立刻撤销流水线暂停
                        // 转入空闲阶段
                        stallreq <= `False_v;
                    end
                end
                default: begin
                    stallreq <= `False_v;
                end
            endcase
        end
    end
    
    // 该行是否需要写回
    wire write_back_0;
    wire write_back_1;
    wire write_back;
    assign write_back_0 = dirty_out_0 & valid_out_0;
    assign write_back_1 = dirty_out_1 & valid_out_1;
    assign write_back = way_choose ? write_back_1:write_back_0;

    //状态机
    always @ (posedge clk) begin
        if (rst == `RstEnable) begin//复位
            state <= `IDLE;
            mem_req_o <= 1'b0;
            mem_data_o <= `BigZeroWord;
            mem_wr_o <= 1'b0;
            mem_strb_o <= 64'h0000000000000000;
            mem_addr_o <= `ZeroWord;
        end else begin
            case (state)//查看当前状态
                `IDLE: begin//空闲
                    if (mem_ce & ~exception_occured_o) begin
                        if(uncache) begin
                            mem_wr_o <= op;
                            mem_strb_o[3:0] <= mem_strb;
                            mem_data_o[31:0] <= mem_data_cache_o[31:0];
                            state <= `UNCACHEWAIT;
                            mem_req_o <= 1'b1;
                            // 地址
                            mem_addr_o <= mem_addr_i;
                        end else if(!hit_total) begin               // TODO
                            mem_data_o <= block_data;
                            mem_strb_o <= 64'hffffffffffffffff;
                            state <= write_back ? `WRITEWAIT : `READWAIT;
                            mem_wr_o <= write_back;
                            mem_req_o <= 1'b1;
                            mem_addr_o <= (write_back) ? last_addr : {mem_addr_i[31:6],6'b000000};
                            // way_choose <= rand[0];
                        end else begin
                            // way_choose <= hit_1;
                        end
                    end   
                end
                `READWAIT: begin
                    if(mem_addr_ok == 1'b1) begin//地址接收成功
                        mem_req_o <= 1'b0;
                        state <= `READOK;//转到读成功
                    end else begin
                    end
                end
                `READOK: begin
                    if(mem_data_ok) begin//数据接收成功
                        state <= `IDLE;//状态回转
                    end else begin
                    end
                end
                `WRITEWAIT: begin//写等待
                    if(mem_addr_ok) begin
                        state <= `WRITEOK;//转到写成功
                        mem_req_o <= 1'b1;
                    end else begin
                    end
                end
                `WRITEOK: begin//写成功
                    if(mem_data_ok)begin
                        state <= `READWAIT;//状态转到读等待
                        mem_req_o <= 1'b1;
                        mem_wr_o <= 1'b0;
                        mem_addr_o <= {mem_addr_i[31:6],6'b000000};
                    end else begin
                    end
                end
                `UNCACHEWAIT: begin//非cache读操操作
                    if(mem_addr_ok) begin
                        state <= `UNCACHEOK;//无cache直接读成功
                        mem_req_o <= 1'b0;
                    end else begin
                    end
                end
                `UNCACHEOK: begin//无cache直接读成功
                    if(mem_data_ok) begin//数据接收成功
                        state <= `IDLE;
                    end else begin
                    end
                end
                default: begin

                end
            endcase
        end
    end

   

    

dirty_ram zero_dirty0(
    .a(index),
    .d(dirty_in_0),
    .clk(clk),
    .we(dirty_we_0 & ~exception_occured_o),
    .spo(dirty_out_0)
);
valid_ram zero_valid(
    .a(index),
    .d(1'b1),
    .clk(clk),
    .we(~way_choose & cache_ok & ~exception_occured_o),
    .spo(valid_out_0)
);

tag_ram zero_tag0(
    .a(index),
    .d(tag),
    .clk(clk),
    .we(~way_choose & cache_ok & ~exception_occured_o),
    .spo(tag_out_0)
);

dirty_ram one_dirty0(
    .a(index),
    .d(dirty_in_1),
    .clk(clk),
    .we(dirty_we_1 & ~exception_occured_o),
    .spo(dirty_out_1)
);
valid_ram one_valid(
    .a(index),
    .d(1'b1),
    .clk(clk),
    .we(way_choose & cache_ok & ~exception_occured_o),
    .spo(valid_out_1)
);

tag_ram one_tag0(
    .a(index),
    .d(tag),
    .clk(clk),
    .we(way_choose & cache_ok & ~exception_occured_o),
    .spo(tag_out_1)
);

wire[3:0] data_we_0[0:15];
assign data_we_0[0] = (cache_ok) ? 4'hf : (hit_0 && offset == 4'h0 && op) ? mem_strb : 4'h0;

wire[31:0] data_in_0[0:15];
//
assign data_in_0[0] = (cache_ok) ? mem_data_i[511:480] : (hit_0 && offset == 4'h0 && op) ? mem_data_cache_o : `ZeroWord;
strb_ram zero_data0(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_0[0]),
    .douta(block_0[0]),
    .ena(mem_ce),
    .wea({4{~way_choose}} & data_we_0[0] & ~exception_occured_o)
);

assign data_we_0[1] = (cache_ok) ? 4'hf : (hit_0 && offset == 4'h1 && op) ? mem_strb : 4'h0;

assign data_in_0[1] = (cache_ok) ? mem_data_i[479:448] : (hit_0 && offset == 4'h1 && op) ? mem_data_cache_o : `ZeroWord;
strb_ram zero_data1(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_0[1]),
    .douta(block_0[1]),
    .ena(mem_ce),
    .wea({4{~way_choose}} & data_we_0[1] & ~exception_occured_o)
);

assign data_we_0[2] = (cache_ok) ? 4'hf : (hit_0 && offset == 4'h2 && op) ? mem_strb : 4'h0;

assign data_in_0[2] = (cache_ok) ? mem_data_i[447:416] : (hit_0 && offset == 4'h2 && op) ? mem_data_cache_o : `ZeroWord;
strb_ram zero_data2(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_0[2]),
    .douta(block_0[2]),
    .ena(mem_ce),
    .wea({4{~way_choose}} & data_we_0[2] & ~exception_occured_o)
);

assign data_we_0[3] = (cache_ok) ? 4'hf : (hit_0 && offset == 4'h3 && op) ? mem_strb : 4'h0;

assign data_in_0[3] = (cache_ok) ? mem_data_i[415:384] : (hit_0 && offset == 4'h3 && op) ? mem_data_cache_o : `ZeroWord;
strb_ram zero_data3(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_0[3]),
    .douta(block_0[3]),
    .ena(mem_ce),
    .wea({4{~way_choose}} & data_we_0[3] & ~exception_occured_o)
);

assign data_we_0[4] = (cache_ok) ? 4'hf : (hit_0 && offset == 4'h4 && op) ? mem_strb : 4'h0;

assign data_in_0[4] = (cache_ok) ? mem_data_i[383:352] : (hit_0 && offset == 4'h4 && op) ? mem_data_cache_o : `ZeroWord;
strb_ram zero_data4(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_0[4]),
    .douta(block_0[4]),
    .ena(mem_ce),
    .wea({4{~way_choose}} & data_we_0[4] & ~exception_occured_o)
);

assign data_we_0[5] = (cache_ok) ? 4'hf : (hit_0 && offset == 4'h5 && op) ? mem_strb : 4'h0;

assign data_in_0[5] = (cache_ok) ? mem_data_i[351:320] : (hit_0 && offset == 4'h5 && op) ? mem_data_cache_o : `ZeroWord;
strb_ram zero_data5(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_0[5]),
    .douta(block_0[5]),
    .ena(mem_ce),
    .wea({4{~way_choose}} & data_we_0[5] & ~exception_occured_o)
);

assign data_we_0[6] = (cache_ok) ? 4'hf : (hit_0 && offset == 4'h6 && op) ? mem_strb : 4'h0;

assign data_in_0[6] = (cache_ok) ? mem_data_i[319:288] : (hit_0 && offset == 4'h6 && op) ? mem_data_cache_o : `ZeroWord;
strb_ram zero_data6(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_0[6]),
    .douta(block_0[6]),
    .ena(mem_ce),
    .wea({4{~way_choose}} & data_we_0[6] & ~exception_occured_o)
);

assign data_we_0[7] = (cache_ok) ? 4'hf : (hit_0 && offset == 4'h7 && op) ? mem_strb : 4'h0;

assign data_in_0[7] = (cache_ok) ? mem_data_i[287:256] : (hit_0 && offset == 4'h7 && op) ? mem_data_cache_o : `ZeroWord;
strb_ram zero_data7(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_0[7]),
    .douta(block_0[7]),
    .ena(mem_ce),
    .wea({4{~way_choose}} & data_we_0[7] & ~exception_occured_o)
);

assign data_we_0[8] = (cache_ok) ? 4'hf : (hit_0 && offset == 4'h8 && op) ? mem_strb : 4'h0;

assign data_in_0[8] = (cache_ok) ? mem_data_i[255:224] : (hit_0 && offset == 4'h8 && op) ? mem_data_cache_o : `ZeroWord;
strb_ram zero_data8(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_0[8]),
    .douta(block_0[8]),
    .ena(mem_ce),
    .wea({4{~way_choose}} & data_we_0[8] & ~exception_occured_o)
);

assign data_we_0[9] = (cache_ok) ? 4'hf : (hit_0 && offset == 4'h9 && op) ? mem_strb : 4'h0;

assign data_in_0[9] = (cache_ok) ? mem_data_i[223:192] : (hit_0 && offset == 4'h9 && op) ? mem_data_cache_o : `ZeroWord;
strb_ram zero_data9(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_0[9]),
    .douta(block_0[9]),
    .ena(mem_ce),
    .wea({4{~way_choose}} & data_we_0[9] & ~exception_occured_o)
);

assign data_we_0[10] = (cache_ok) ? 4'hf : (hit_0 && offset == 4'ha && op) ? mem_strb : 4'h0;

assign data_in_0[10] = (cache_ok) ? mem_data_i[191:160] : (hit_0 && offset == 4'ha && op) ? mem_data_cache_o : `ZeroWord;
strb_ram zero_data10(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_0[10]),
    .douta(block_0[10]),
    .ena(mem_ce),
    .wea({4{~way_choose}} & data_we_0[10] & ~exception_occured_o)
);

assign data_we_0[11] = (cache_ok) ? 4'hf : (hit_0 && offset == 4'hb && op) ? mem_strb : 4'h0;

assign data_in_0[11] = (cache_ok) ? mem_data_i[159:128] : (hit_0 && offset == 4'hb && op) ? mem_data_cache_o : `ZeroWord;
strb_ram zero_data11(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_0[11]),
    .douta(block_0[11]),
    .ena(mem_ce),
    .wea({4{~way_choose}} & data_we_0[11] & ~exception_occured_o)
);

assign data_we_0[12] = (cache_ok) ? 4'hf : (hit_0 && offset == 4'hc && op) ? mem_strb : 4'h0;

assign data_in_0[12] = (cache_ok) ? mem_data_i[127:96] : (hit_0 && offset == 4'hc && op) ? mem_data_cache_o : `ZeroWord;
strb_ram zero_data12(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_0[12]),
    .douta(block_0[12]),
    .ena(mem_ce),
    .wea({4{~way_choose}} & data_we_0[12] & ~exception_occured_o)
);

assign data_we_0[13] = (cache_ok) ? 4'hf : (hit_0 && offset == 4'hd && op) ? mem_strb : 4'h0;

assign data_in_0[13] = (cache_ok) ? mem_data_i[95:64] : (hit_0 && offset == 4'hd && op) ? mem_data_cache_o : `ZeroWord;
strb_ram zero_data13(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_0[13]),
    .douta(block_0[13]),
    .ena(mem_ce),
    .wea({4{~way_choose}} & data_we_0[13] & ~exception_occured_o)
);

assign data_we_0[14] = (cache_ok) ? 4'hf : (hit_0 && offset == 4'he && op) ? mem_strb : 4'h0;

assign data_in_0[14] = (cache_ok) ? mem_data_i[63:32] : (hit_0 && offset == 4'he && op) ? mem_data_cache_o : `ZeroWord;
strb_ram zero_data14(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_0[14]),
    .douta(block_0[14]),
    .ena(mem_ce),
    .wea({4{~way_choose}} & data_we_0[14] & ~exception_occured_o)
);

assign data_we_0[15] = (cache_ok) ? 4'hf : (hit_0 && offset == 4'hf && op) ? mem_strb : 4'h0;

assign data_in_0[15] = (cache_ok) ? mem_data_i[31:0] : (hit_0 && offset == 4'hf && op) ? mem_data_cache_o : `ZeroWord;
strb_ram zero_data15(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_0[15]),
    .douta(block_0[15]),
    .ena(mem_ce),
    .wea({4{~way_choose}} & data_we_0[15] & ~exception_occured_o)
);

wire[3:0] data_we_1[0:15];
assign data_we_1[0] = (cache_ok) ? 4'hf : (hit_1 && offset == 4'h0 && op) ? mem_strb : 4'h0;

wire[31:0] data_in_1[0:15];
//
assign data_in_1[0] = (cache_ok) ? mem_data_i[511:480] : (hit_1 && offset == 4'h0 && op) ? mem_data_cache_o : `ZeroWord;
strb_ram one_data0(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_1[0]),
    .douta(block_1[0]),
    .ena(mem_ce),
    .wea({4{way_choose}} & data_we_1[0] & ~exception_occured_o)
);

assign data_we_1[1] = (cache_ok) ? 4'hf : (hit_1 && offset == 4'h1 && op) ? mem_strb : 4'h0;

assign data_in_1[1] = (cache_ok) ? mem_data_i[479:448] : (hit_1 && offset == 4'h1 && op) ? mem_data_cache_o : `ZeroWord;
strb_ram one_data1(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_1[1]),
    .douta(block_1[1]),
    .ena(mem_ce),
    .wea({4{way_choose}} & data_we_1[1] & ~exception_occured_o)
);

assign data_we_1[2] = (cache_ok) ? 4'hf : (hit_1 && offset == 4'h2 && op) ? mem_strb : 4'h0;

assign data_in_1[2] = (cache_ok) ? mem_data_i[447:416] : (hit_1 && offset == 4'h2 && op) ? mem_data_cache_o : `ZeroWord;
strb_ram one_data2(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_1[2]),
    .douta(block_1[2]),
    .ena(mem_ce),
    .wea({4{way_choose}} & data_we_1[2] & ~exception_occured_o)
);

assign data_we_1[3] = (cache_ok) ? 4'hf : (hit_1 && offset == 4'h3 && op) ? mem_strb : 4'h0;

assign data_in_1[3] = (cache_ok) ? mem_data_i[415:384] : (hit_1 && offset == 4'h3 && op) ? mem_data_cache_o : `ZeroWord;
strb_ram one_data3(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_1[3]),
    .douta(block_1[3]),
    .ena(mem_ce),
    .wea({4{way_choose}} & data_we_1[3] & ~exception_occured_o)
);

assign data_we_1[4] = (cache_ok) ? 4'hf : (hit_1 && offset == 4'h4 && op) ? mem_strb : 4'h0;

assign data_in_1[4] = (cache_ok) ? mem_data_i[383:352] : (hit_1 && offset == 4'h4 && op) ? mem_data_cache_o : `ZeroWord;
strb_ram one_data4(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_1[4]),
    .douta(block_1[4]),
    .ena(mem_ce),
    .wea({4{way_choose}} & data_we_1[4] & ~exception_occured_o)
);

assign data_we_1[5] = (cache_ok) ? 4'hf : (hit_1 && offset == 4'h5 && op) ? mem_strb : 4'h0;

assign data_in_1[5] = (cache_ok) ? mem_data_i[351:320] : (hit_1 && offset == 4'h5 && op) ? mem_data_cache_o : `ZeroWord;
strb_ram one_data5(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_1[5]),
    .douta(block_1[5]),
    .ena(mem_ce),
    .wea({4{way_choose}} & data_we_1[5] & ~exception_occured_o)
);

assign data_we_1[6] = (cache_ok) ? 4'hf : (hit_1 && offset == 4'h6 && op) ? mem_strb : 4'h0;

assign data_in_1[6] = (cache_ok) ? mem_data_i[319:288] : (hit_1 && offset == 4'h6 && op) ? mem_data_cache_o : `ZeroWord;
strb_ram one_data6(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_1[6]),
    .douta(block_1[6]),
    .ena(mem_ce),
    .wea({4{way_choose}} & data_we_1[6] & ~exception_occured_o)
);

assign data_we_1[7] = (cache_ok) ? 4'hf : (hit_1 && offset == 4'h7 && op) ? mem_strb : 4'h0;

assign data_in_1[7] = (cache_ok) ? mem_data_i[287:256] : (hit_1 && offset == 4'h7 && op) ? mem_data_cache_o : `ZeroWord;
strb_ram one_data7(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_1[7]),
    .douta(block_1[7]),
    .ena(mem_ce),
    .wea({4{way_choose}} & data_we_1[7] & ~exception_occured_o)
);

assign data_we_1[8] = (cache_ok) ? 4'hf : (hit_1 && offset == 4'h8 && op) ? mem_strb : 4'h0;

assign data_in_1[8] = (cache_ok) ? mem_data_i[255:224] : (hit_1 && offset == 4'h8 && op) ? mem_data_cache_o : `ZeroWord;
strb_ram one_data8(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_1[8]),
    .douta(block_1[8]),
    .ena(mem_ce),
    .wea({4{way_choose}} & data_we_1[8] & ~exception_occured_o)
);

assign data_we_1[9] = (cache_ok) ? 4'hf : (hit_1 && offset == 4'h9 && op) ? mem_strb : 4'h0;

assign data_in_1[9] = (cache_ok) ? mem_data_i[223:192] : (hit_1 && offset == 4'h9 && op) ? mem_data_cache_o : `ZeroWord;
strb_ram one_data9(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_1[9]),
    .douta(block_1[9]),
    .ena(mem_ce),
    .wea({4{way_choose}} & data_we_1[9] & ~exception_occured_o)
);

assign data_we_1[10] = (cache_ok) ? 4'hf : (hit_1 && offset == 4'ha && op) ? mem_strb : 4'h0;

assign data_in_1[10] = (cache_ok) ? mem_data_i[191:160] : (hit_1 && offset == 4'ha && op) ? mem_data_cache_o : `ZeroWord;
strb_ram one_data10(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_1[10]),
    .douta(block_1[10]),
    .ena(mem_ce),
    .wea({4{way_choose}} & data_we_1[10] & ~exception_occured_o)
);

assign data_we_1[11] = (cache_ok) ? 4'hf : (hit_1 && offset == 4'hb && op) ? mem_strb : 4'h0;

assign data_in_1[11] = (cache_ok) ? mem_data_i[159:128] : (hit_1 && offset == 4'hb && op) ? mem_data_cache_o : `ZeroWord;
strb_ram one_data11(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_1[11]),
    .douta(block_1[11]),
    .ena(mem_ce),
    .wea({4{way_choose}} & data_we_1[11] & ~exception_occured_o)
);

assign data_we_1[12] = (cache_ok) ? 4'hf : (hit_1 && offset == 4'hc && op) ? mem_strb : 4'h0;

assign data_in_1[12] = (cache_ok) ? mem_data_i[127:96] : (hit_1 && offset == 4'hc && op) ? mem_data_cache_o : `ZeroWord;
strb_ram one_data12(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_1[12]),
    .douta(block_1[12]),
    .ena(mem_ce),
    .wea({4{way_choose}} & data_we_1[12] & ~exception_occured_o)
);

assign data_we_1[13] = (cache_ok) ? 4'hf : (hit_1 && offset == 4'hd && op) ? mem_strb : 4'h0;

assign data_in_1[13] = (cache_ok) ? mem_data_i[95:64] : (hit_1 && offset == 4'hd && op) ? mem_data_cache_o : `ZeroWord;
strb_ram one_data13(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_1[13]),
    .douta(block_1[13]),
    .ena(mem_ce),
    .wea({4{way_choose}} & data_we_1[13] & ~exception_occured_o)
);

assign data_we_1[14] = (cache_ok) ? 4'hf : (hit_1 && offset == 4'he && op) ? mem_strb : 4'h0;

assign data_in_1[14] = (cache_ok) ? mem_data_i[63:32] : (hit_1 && offset == 4'he && op) ? mem_data_cache_o : `ZeroWord;
strb_ram one_data14(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_1[14]),
    .douta(block_1[14]),
    .ena(mem_ce),
    .wea({4{way_choose}} & data_we_1[14] & ~exception_occured_o)
);

assign data_we_1[15] = (cache_ok) ? 4'hf : (hit_1 && offset == 4'hf && op) ? mem_strb : 4'h0;

assign data_in_1[15] = (cache_ok) ? mem_data_i[31:0] : (hit_1 && offset == 4'hf && op) ? mem_data_cache_o : `ZeroWord;
strb_ram one_data15(
    .addra({22'd0,index,2'b00}),
    .clka(~clk),
    .dina(data_in_1[15]),
    .douta(block_1[15]),
    .ena(mem_ce),
    .wea({4{way_choose}} & data_we_1[15] & ~exception_occured_o)
);

    assign we_o = exception_occured_o ? `WriteDisable : we_i;

    // 没有发生异常才允许存储器操作
    // assign mem_req_o = ~hit && mem_ce && (~exception_occured_o);
    assign is_in_delayslot_o = is_in_delayslot_i;
    assign pc_o = pc_i;
    reg read_exception;
    reg write_exception;

    // 产生异常ExcCode
    always @ (*) begin
        if (rst == `RstEnable) begin
            exception_occured_o <= `False_v;
            exc_code_o <= 5'b00000;
            bad_addr_o <= `ZeroWord;
        end else begin
            // 等待cpu复位或清空流水线
            if (pc_i != `ZeroWord) begin
                exception_occured_o <= `True_v; // 默认有异常
                if (((cp0_cause_i[15:8] & cp0_status_i[15:8]) != 8'd0) // 有未被屏蔽的中断申请
                && cp0_status_i[2] == 1'b0 && cp0_status_i[1] == 1'b0 // 不在异常级或错误级中
                && cp0_status_i[0] == 1'b1 /* 总中断开启 */)  begin
                    exc_code_o <= 5'h00;
                end else if (exceptions_i[0]) begin
                    // PC取指未对齐
                    exc_code_o <= 5'h04;
                    bad_addr_o <= pc_i;
                end else if (exceptions_i[1]) begin
                    // 无效指令
                    exc_code_o <= 5'h0a;
                end else if (exceptions_i[5]) begin
                    // 溢出
                    exc_code_o <= 5'h0c;
                end else if (exceptions_i[6]) begin
                    // 自陷
                    exc_code_o <= 5'h0d;
                end else if (exceptions_i[4]) begin
                    // Syscall调用
                    exc_code_o <= 5'h08;
                end else if (exceptions_i[3]) begin
                    // Break调用
                    exc_code_o <= 5'h09;
                end else if (read_exception) begin
                    exc_code_o <= 5'h04;
                    bad_addr_o <= mem_addr_i;
                end else if (write_exception) begin
                    exc_code_o <= 5'h05;
                    bad_addr_o <= mem_addr_i;
                end else if (exceptions_i[2]) begin
                    // ERET调用
                    exc_code_o <= 5'h10; // MIPS32并未定义ERET，这里使用implementation dependent use
                end else begin
                    exception_occured_o <= `False_v;
                end
            end else begin
                exception_occured_o <= `False_v;
            end
        end
    end

    wire[`RegBus] zero32 = `ZeroWord;

    always @ (*) begin
        read_exception <= `False_v;
        write_exception <= `False_v;
        op <= `WriteDisable;
        mem_ce <= `ChipDisable;
        if(rst == `RstEnable) begin
            waddr_o <= `NOPRegAddr;
            wdata_o <= `ZeroWord;
            we_hilo_o <= `WriteDisable;
            hi_o <= `ZeroWord;
            lo_o <= `ZeroWord;
            mem_strb[3:0] <= 4'b0000;
            cp0_we_o <= `WriteDisable;
            cp0_waddr_o <= 8'b00000000;
            cp0_wdata_o <= `ZeroWord;
            mem_data_cache_o <= `ZeroWord;//新加
        end else begin
            waddr_o <= waddr_i;
            wdata_o <= wdata_i;
            we_hilo_o <= we_hilo_i;
            hi_o <= hi_i;
            lo_o <= lo_i;
            mem_strb[3:0] <= 4'b1111;
            cp0_we_o <= cp0_we_i;
            cp0_waddr_o <= cp0_waddr_i;
            cp0_wdata_o <= cp0_wdata_i;
            // 下面根据MEM_OP决定wdata、mem_data和mem_sel及片选和写使能
            case (aluop_i)
                // LB
                `MEM_OP_LB: begin
                    mem_ce <= `ChipEnable;
                    case (mem_addr_i[1:0])
                        2'b00: begin
                            wdata_o <= {{24{mem_data_cache_i[7]}},mem_data_cache_i[7:0]};
                            mem_strb[3:0] <= 4'b0001;
                        end
                        2'b01: begin
                            wdata_o <= {{24{mem_data_cache_i[15]}},mem_data_cache_i[15:8]};
                            mem_strb[3:0] <= 4'b0010;
                        end
                        2'b10: begin
                            wdata_o <= {{24{mem_data_cache_i[23]}},mem_data_cache_i[23:16]};
                            mem_strb[3:0] <= 4'b0100;
                        end
                        2'b11: begin
                            wdata_o <= {{24{mem_data_cache_i[31]}},mem_data_cache_i[31:24]};
                            mem_strb[3:0] <= 4'b1000;
                        end
                        default: begin
                            wdata_o <= `ZeroWord;
                        end
                    endcase
                end
                // LH
                `MEM_OP_LH: begin
                    mem_ce <= `ChipEnable;
                    case (mem_addr_i[1:0])
                        2'b00: begin
                            wdata_o <= {{16{mem_data_cache_i[15]}}, mem_data_cache_i[15:0]};
                            mem_strb[3:0] <= 4'b0011;
                        end
                        2'b10: begin
                            wdata_o <= {{16{mem_data_cache_i[31]}}, mem_data_cache_i[31:16]};
                            mem_strb[3:0] <= 4'b1100;
                        end
                        default: begin
                            // 此时一定是最低没有对齐，应当抛地址异常
                            read_exception <= `True_v;
                            wdata_o <= `ZeroWord;
                            mem_ce <= `ChipDisable;
                        end
                    endcase
                end
                // LWL
                `MEM_OP_LWL: begin
                    mem_strb[3:0] <= 4'b1111;
                    mem_ce <= `ChipEnable;
                    case (mem_addr_i[1:0])
                        2'b00: begin
                            wdata_o <= {mem_data_cache_i[7:0],reg2_i[23:0]};
                        end
                        2'b01: begin
                            wdata_o <= {mem_data_cache_i[15:0],reg2_i[15:0]};
                        end
                        2'b10: begin
                            wdata_o <= {mem_data_cache_i[23:0],reg2_i[7:0]};
                        end
                        2'b11: begin
                            wdata_o <= mem_data_cache_i[31:0];
                        end
                        default: begin
                            wdata_o <= `ZeroWord;
                        end
                    endcase
                end
                // LW
                `MEM_OP_LW: begin
                    wdata_o <= mem_data_cache_i[31:0];
                    mem_strb[3:0] <= 4'b1111;
                    mem_ce <= `ChipEnable;
                    if (mem_addr_i[1:0] != 2'b00) begin 
                        read_exception <= `True_v;
                        mem_ce <= `ChipDisable;
                    end
                end
                // LBU
                `MEM_OP_LBU: begin
                    mem_ce <= `ChipEnable;
                    case (mem_addr_i[1:0])
                        2'b00: begin
                            wdata_o <= {{24{1'b0}},mem_data_cache_i[7:0]};
                            mem_strb[3:0] <= 4'b0001;
                        end
                        2'b01: begin
                            wdata_o <= {{24{1'b0}},mem_data_cache_i[15:8]};
                            mem_strb[3:0] <= 4'b0010;
                        end
                        2'b10: begin
                            wdata_o <= {{24{1'b0}},mem_data_cache_i[23:16]};
                            mem_strb[3:0] <= 4'b0100;
                        end
                        2'b11: begin
                            wdata_o <= {{24{1'b0}},mem_data_cache_i[31:24]};
                            mem_strb[3:0] <= 4'b1000;
                        end
                        default: begin
                            wdata_o <= `ZeroWord;
                        end
                    endcase
                end
                // LHU
                `MEM_OP_LHU: begin
                    mem_ce <= `ChipEnable;
                    case (mem_addr_i[1:0])
                        2'b00: begin
                            wdata_o <= {{16{1'b0}}, mem_data_cache_i[15:0]};
                            mem_strb[3:0] <= 4'b0011;
                        end
                        2'b10: begin
                            wdata_o <= {{16{1'b0}}, mem_data_cache_i[31:16]};
                            mem_strb[3:0] <= 4'b1100;
                        end
                        default: begin
                            read_exception <= `True_v;
                            wdata_o <= `ZeroWord;
                            mem_ce <= `ChipDisable;
                        end
                    endcase
                end
                // LWR
                `MEM_OP_LWR: begin
                    mem_strb[3:0] <= 4'b1111;
                    mem_ce <= `ChipEnable;
                    case (mem_addr_i[1:0])
                        2'b00: begin
                            wdata_o <= mem_data_cache_i[31:0];
                        end
                        2'b01: begin
                            wdata_o <= {reg2_i[31:24],mem_data_cache_i[31:8]};
                        end
                        2'b10: begin
                            wdata_o <= {reg2_i[31:16],mem_data_cache_i[31:16]};
                        end
                        2'b11: begin
                            wdata_o <= {reg2_i[31:8],mem_data_cache_i[31:24]};
                        end
                        default: begin
                            wdata_o <= `ZeroWord;
                        end
                    endcase
                end
                // SB
                `MEM_OP_SB: begin
                    op <= `WriteEnable;
                    // 因为只写入1byte，因此全部复制最低位要写入的数据
                    mem_data_cache_o[31:0] <= {reg2_i[7:0],reg2_i[7:0],reg2_i[7:0],reg2_i[7:0]};
                    mem_ce <= `ChipEnable;
                    case (mem_addr_i[1:0])
                        2'b00: begin
                            mem_strb[3:0] <= 4'b0001;
                        end
                        2'b01: begin
                            mem_strb[3:0] <= 4'b0010;
                        end
                        2'b10: begin
                            mem_strb[3:0] <= 4'b0100;
                        end
                        2'b11: begin
                            mem_strb[3:0] <= 4'b1000;
                        end
                        default: begin
                            mem_strb[3:0] <= 4'b0000;
                        end
                    endcase
                end
                // SH
                `MEM_OP_SH: begin
                    op <= `WriteEnable;
                    mem_data_cache_o[31:0] <= {reg2_i[15:0], reg2_i[15:0]};
                    mem_ce <= `ChipEnable;
                    case (mem_addr_i[1:0])
                        2'b00: begin
                            mem_strb[3:0] <= 4'b0011;
                        end
                        2'b10: begin
                            mem_strb[3:0] <= 4'b1100;
                        end
                        default: begin
                            write_exception <= `True_v;
                            mem_strb[3:0] <= 4'b0000;
                            mem_ce <= `ChipDisable;
                        end
                    endcase
                end
                // SWL
                `MEM_OP_SWL: begin
                    op <= `WriteEnable;
                    mem_data_cache_o[31:0] <= reg2_i;
                    mem_ce <= `ChipEnable;
                    case (mem_addr_i[1:0])
                        2'b00: begin
                            mem_strb[3:0] <= 4'b0001;
                            mem_data_cache_o[31:0] <= {zero32[23:0],reg2_i[31:24]};
                        end
                        2'b01: begin
                            mem_strb[3:0] <= 4'b0011;
                            mem_data_cache_o[31:0] <= {zero32[15:0],reg2_i[31:16]};
                        end
                        2'b10: begin
                            mem_strb[3:0] <= 4'b0111;
                            mem_data_cache_o[31:0] <= {zero32[7:0],reg2_i[31:8]};
                        end
                        2'b11: begin
                            mem_strb[3:0] <= 4'b1111;
                            mem_data_cache_o[31:0] <= reg2_i;
                        end
                        default: begin
                            mem_strb[3:0] <= 4'b0000;
                        end
                    endcase
                end
                // SW
                `MEM_OP_SW: begin
                    op <= `WriteEnable;
                    mem_data_cache_o[31:0] <= reg2_i;
                    mem_strb[3:0] <= 4'b1111;
                    mem_ce <= `ChipEnable;
                    if (mem_addr_i[1:0] != 2'b00) begin
                        write_exception <= `True_v;
                        mem_ce <= `ChipDisable;
                    end
                end
                // SWR
                `MEM_OP_SWR: begin
                    op <= `WriteEnable;
                    mem_data_cache_o[31:0] <= reg2_i;
                    mem_ce <= `ChipEnable;
                    case (mem_addr_i[1:0])
                        2'b00: begin
                            mem_strb[3:0] <= 4'b1111;
                            mem_data_cache_o[31:0] <= reg2_i[31:0];
                        end
                        2'b01: begin
                            mem_strb[3:0] <= 4'b1110;
                            mem_data_cache_o[31:0] <= {reg2_i[23:0],zero32[7:0]};
                        end
                        2'b10: begin
                            mem_strb[3:0] <= 4'b1100;
                            mem_data_cache_o[31:0] <= {reg2_i[15:0],zero32[15:0]};
                        end
                        2'b11: begin
                            mem_strb[3:0] <= 4'b1000;
                            mem_data_cache_o[31:0] <= {reg2_i[7:0],zero32[23:0]};
                        end
                        default: begin
                            mem_strb[3:0] <= 4'b0000;
                        end
                    endcase
                end
                // LL
                `MEM_OP_LL: begin
                    // TODO LL
                end
                // SC
                `MEM_OP_SC: begin
                    // TODO SC
                end
                default: begin
                end
            endcase
        end
    end
    
endmodule
