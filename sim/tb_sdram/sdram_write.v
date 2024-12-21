/*
 * @Author: bit_stream 
 * @Date: 2024-12-15 10:02:47 
 * @Last Modified by: bit_stream
 * @Last Modified time: 2024-12-15 14:58:06
 */

//写入数据的流程如下： 激活需要写入的bank和行→等待TRCD时间→发出写命令（需要写入的第一个数据有效）→写入wr_burst_len个数据→
//发送突发停止命令→等待tWR的时间→发出预充电命令→等待tRP时间→一次突发写传输结束
module  sdram_write
(
    input   wire            sys_clk         ,   //系统时钟,频率100MHz
    input   wire            sys_rst_n       ,   //复位信号,低电平有效
    input   wire            init_end        ,   //初始化结束信号
    input   wire            wr_en           ,   //写使能
    input   wire    [23:0]  wr_addr         ,   //写SDRAM地址
    input   wire    [15:0]  wr_data         ,   //待写入SDRAM的数据(写FIFO传入)
    input   wire    [9:0]   wr_burst_len    ,   //写突发SDRAM字节数

    output  reg             wr_fifo_rd_en   ,   //SDRAM写侧的FIFO 读使能信号
    output  wire            wr_end          ,   //一次突发写结束
    output  reg     [3:0]   write_cmd       ,   //写数据阶段写入sdram的指令,{cs_n,ras_n,cas_n,we_n}
    output  reg     [1:0]   write_ba        ,   //写数据阶段Bank地址
    output  reg     [12:0]  write_addr      ,   //地址数据,辅助预充电操作,行、列地址,A12-A0,13位地址
    output  wire            wr_sdram_en     ,   //数据总线输出使能
    output  wire    [15:0]  wr_sdram_data       //写入SDRAM的数据
);

    //写阶段使用到的SDRAM  指令集
    localparam NOP                = 4'b0111 ;//空命令
    localparam ACTIVE             = 4'b0011 ;//激活命令
    localparam WRITE              = 4'b0100 ;//写数据命令
    localparam B_TERM             = 4'b0110 ;//突发停止命令
    localparam PRECHARGE          = 4'b0010 ;//预充电命令

     //写阶段的状态机
    localparam WR_IDLE   = 4'b0000 ;//初始状态，初始化结束并且写使能跳转至激活状态
    localparam WR_ACTIVE = 4'b0001 ;//发送激活命令
    localparam WR_TRCD   = 4'b0010 ;//激活状态，等待tRCD时间跳转至写状态
    localparam WR_WRITE  = 4'b0011 ;//发送写命令
    localparam WR_WDATA  = 4'b0100 ;//写数据状态，数据写完后发送突发停止命令
    localparam WR_TWR    = 4'b0101 ;//等待TWR时间，确保本次写入的数据被存进SDRAM
    localparam WR_PRE    = 4'b0110 ;//预充电命令
    localparam WR_TRP    = 4'b0111 ;//预充电状态，等待tRP时间写结束
    localparam WR_END    = 4'b1000 ;//写结束

    
    //各个阶段等待的周期数，一个时钟周期为10ns，0.01us
    localparam WR_TRP_CLK   = 2      ; //根据数据手册可知，最小时间为20ns
    localparam WR_TRCD_CLK  = 2      ; //根据数据手册可知，最小时间为20ns
    localparam WR_TWR_CLK   = 2      ; //根据数据手册可知，最小时间为2个CLK
    
    //定义状态机
    reg [3:0] wr_state;

    //定义计数器，计数需要等待的时间
    reg [14:0] cnt_clk;

    //定义计数器使能信号，在特定的状态使能计数器计数
    reg cnt_clk_en; //其为1时，使能计数，其为0时，计数器清零

    always @(posedge sys_clk) begin
        if (~sys_rst_n) begin
            cnt_clk <= 'd0;
        end else if (cnt_clk_en) begin
            cnt_clk <= cnt_clk + 1'b1;
        end else if (~cnt_clk_en) begin
            cnt_clk <= 'd0;
        end 
    end 


    always @(*) begin //信号立刻变化
        if (~sys_rst_n) begin
            cnt_clk_en <= 0;
        end else begin
            case (wr_state)
                WR_TRCD,WR_WDATA,WR_TRP:begin
                    cnt_clk_en <= 1'b1;
                end 
                WR_IDLE,WR_ACTIVE,WR_WRITE,WR_TWR,WR_PRE,WR_END:begin
                    cnt_clk_en <= 1'b0;
                end
                default: begin
                    cnt_clk_en <= cnt_clk_en;
                end
            endcase
        end
    end

    //写状态机跳转
    always @(posedge sys_clk) begin
        if (~sys_rst_n) begin
            wr_state <= WR_IDLE;
        end else begin
            case (wr_state)
                WR_IDLE:begin
                    if (wr_en & init_end) begin
                        wr_state <= WR_ACTIVE;
                    end
                end 
                WR_ACTIVE:begin
                    wr_state <= WR_TRCD;
                end
                WR_TRCD:begin
                    if (cnt_clk == WR_TRCD_CLK - 'd1) begin
                        wr_state <= WR_WRITE;
                    end
                end
                WR_WRITE:begin
                    wr_state <= WR_WDATA;
                end
                WR_WDATA:begin
                    if (cnt_clk == wr_burst_len - 'd1) begin
                        wr_state <= WR_TWR;
                    end
                end
                WR_TWR:begin
                        wr_state <= WR_PRE;
                end
                WR_PRE:begin
                    wr_state <= WR_TRP;
                end
                WR_TRP:begin
                    if (cnt_clk == WR_TRP_CLK - 'd1) begin
                        wr_state <= WR_END;
                    end
                end
                WR_END:begin
                    wr_state <= WR_IDLE;
                end
                default: begin
                    wr_state <= WR_IDLE;
                end
            endcase
        end
    end


    always @(posedge sys_clk) begin
        if (~sys_rst_n) begin
            write_cmd   <=  NOP;
            write_ba    <=  2'b11;
            write_addr  <=  13'h1fff;
        end else begin
            case (wr_state)
                WR_IDLE,WR_TRCD,WR_TWR,WR_TRP,WR_END:begin
                    write_cmd   <=  NOP;
                    write_ba    <=  2'b11;
                    write_addr  <=  13'h1fff;
                end
                WR_ACTIVE:begin
                    write_cmd   <=  ACTIVE;
                    write_ba    <=  wr_addr[23:22];//地址高2bit代表哪一个bank
                    write_addr  <=  wr_addr[21:9];
                end
                WR_WRITE:begin
                    write_cmd   <=  WRITE;
                    write_ba    <=  wr_addr[23:22];
                    write_addr  <=  {4'b0000,wr_addr[8:0]};//其实列地址只需9位，但是，需要补4个零，因为数据长度为13,A10为0，不进行自动预充电
                end
                WR_WDATA:begin
                    write_ba    <=  2'b11;
                    write_addr  <=  13'h1fff;
                    if (cnt_clk == wr_burst_len - 'd1) begin
                        write_cmd <=  B_TERM; 
                    end else begin
                        write_cmd   <=  NOP;
                    end
                end
                WR_PRE:begin
                    write_cmd   <= PRECHARGE;
                    write_ba    <=  2'b11;
                    write_addr  <=  13'h1fff;
                end
                default: begin
                    write_cmd   <=  NOP;
                    write_ba    <=  2'b11;
                    write_addr  <=  13'h1fff;
                end
            endcase
        end
    end

//当写命令后效时，第一个写数据有效，假设FIFO为fwft模式，即FIFO的读使能有效时，数据立刻有效

always @(posedge sys_clk) begin
    if (~sys_rst_n) begin
        wr_fifo_rd_en <= 0;
    end else if (wr_state == WR_WRITE) begin
        wr_fifo_rd_en <= 1;
    end else if (cnt_clk == wr_burst_len - 'd1) begin
        wr_fifo_rd_en <= 0;
    end
end

assign wr_end = (wr_state == WR_END)? 1'b1:1'b0 ;

assign wr_sdram_en = wr_fifo_rd_en;

assign wr_sdram_data = wr_data;




endmodule