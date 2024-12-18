/*
 * @Author: bit_stream 
 * @Date: 2024-12-15 18:18:35 
 * @Last Modified by: bit_stream
 * @Last Modified time: 2024-12-15 19:37:17
 */

//读和写类似，读出数据的流程如下：激活需要读的bank和行→等待TRCD时间→发出读命令→潜伏期等待（在初始化阶段配置的潜伏期为CAS latency为3，所以当读命令与第一个数据读出之间隔了3个时钟周期）、
//→读出rd_burst_len个数据→发出突发停止命令→发出预充电命令→等待tRP时间→一次突发读传输结束

module  sdram_read
(
    input   wire            sys_clk         ,   //系统时钟,频率100MHz
    input   wire            sys_rst_n       ,   //复位信号,低电平有效
    input   wire            init_end        ,   //初始化结束信号
    input   wire            rd_en           ,   //读使能
    input   wire    [23:0]  rd_addr         ,   //读SDRAM地址
    input   wire    [15:0]  rd_data         ,   //自SDRAM中读出的数据
    input   wire    [9:0]   rd_burst_len    ,   //读突发SDRAM字节数

    output  reg             rd_fifo_wr_en   ,   //SDRAM读侧的FIFO 写使能信号
    output  wire            rd_end          ,   //一次突发读结束
    output  reg     [3:0]   read_cmd        ,   //读数据阶段写入sdram的指令,{cs_n,ras_n,cas_n,we_n}
    output  reg     [1:0]   read_ba         ,   //读数据阶段Bank地址
    output  reg     [12:0]  read_addr       ,   //地址数据,辅助预充电操作,行、列地址,A12-A0,13位地址
    output  wire    [15:0]  rd_fifo_wr_data     //写入SDRAM读侧的FIFO数据
);

    //读阶段使用到的SDRAM  指令集
    localparam NOP                = 4'b0111 ;//空命令
    localparam ACTIVE             = 4'b0011 ;//激活命令
    localparam READ               = 4'b0101 ;//读数据命令
    localparam B_TERM             = 4'b0110 ;//突发停止命令
    localparam PRECHARGE          = 4'b0010 ;//预充电命令

    //读阶段的状态机
    localparam RD_IDLE   = 4'b0000 ;//初始状态，初始化结束并且读使能跳转至激活状态
    localparam RD_ACTIVE = 4'b0001 ;//发送激活命令
    localparam RD_TRCD   = 4'b0010 ;//激活状态，等待tRCD时间跳转至读状态
    localparam RD_READ   = 4'b0011 ;//发送读命令
    localparam RD_CAS    = 4'b0100 ;//潜伏期等待数据有效
    localparam RD_RDATA  = 4'b0101 ;//读数据状态，数据读完后发送突发停止命令
    localparam RD_PRE    = 4'b0110 ;//预充电命令
    localparam RD_TRP    = 4'b0111 ;//预充电状态，等待tRP时间读结束
    localparam RD_END    = 4'b1000 ;//读结束

    //各个阶段等待的周期数，一个时钟周期为10ns，0.01us
    localparam RD_TRP_CLK   = 2      ; //根据数据手册可知，最小时间为20ns
    localparam RD_TRCD_CLK  = 2      ; //根据数据手册可知，最小时间为20ns
    localparam RD_CAS_CLK   = 3      ; //初始化阶段配置为3

    //定义状态机
    reg [3:0] rd_state;

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
            case (rd_state)
                RD_TRCD,RD_CAS,RD_RDATA,RD_TRP:begin
                    cnt_clk_en <= 1'b1;
                end 
                RD_IDLE,RD_ACTIVE,RD_READ,RD_PRE,RD_END:begin
                    cnt_clk_en <= 1'b0;
                end
                default: begin
                    cnt_clk_en <= cnt_clk_en;
                end
            endcase
        end
    end

 //读状态机跳转
    always @(posedge sys_clk) begin
        if (~sys_rst_n) begin
            rd_state <= RD_IDLE;
        end else begin
            case (rd_state)
                RD_IDLE:begin
                    if (rd_en & init_end) begin
                        rd_state <= RD_ACTIVE;
                    end
                end 
                RD_ACTIVE:begin
                    rd_state <= RD_TRCD;
                end
                RD_TRCD:begin
                    if (cnt_clk == RD_TRCD_CLK - 'd1) begin
                        rd_state <= RD_READ;
                    end
                end
                RD_READ:begin
                    rd_state <= RD_CAS;
                end
                RD_CAS:begin
                    if (cnt_clk == RD_CAS_CLK - 'd1) begin //cnt_clk从RD_CAS状态开始计数，在其跳转到RD_RDATA状态时，其计数值为2
                        rd_state <= RD_RDATA;
                    end
                end
                RD_RDATA:begin
                    if (cnt_clk == rd_burst_len + 'd2) begin//所以这里是rd_burst_len + 'd2，计数范围是2~rd_burst_len + 'd2
                        rd_state <= RD_PRE;
                    end
                end
                RD_PRE:begin
                    rd_state <= RD_TRP;
                end
                RD_TRP:begin
                    if (cnt_clk == RD_TRP_CLK - 'd1) begin
                        rd_state <= RD_END;
                    end
                end
                RD_END:begin
                    rd_state <= RD_IDLE;
                end
                default: begin
                    rd_state <= RD_IDLE;
                end
            endcase
        end
    end


   always @(posedge sys_clk) begin
        if (~sys_rst_n) begin
            read_cmd   <=  NOP;
            read_ba    <=  2'b11;
            read_addr  <=  13'h1fff;
        end else begin
            case (rd_state)
                RD_IDLE,RD_TRCD,RD_CAS,RD_TRP,RD_END:begin
                    read_cmd   <=  NOP;
                    read_ba    <=  2'b11;
                    read_addr  <=  13'h1fff;
                end
                RD_ACTIVE:begin
                    read_cmd   <=  ACTIVE;
                    read_ba    <=  rd_addr[23:22];//地址高2bit代表哪一个bank
                    read_addr  <=  rd_addr[21:9];
                end
                RD_READ:begin
                    read_cmd   <=  READ;
                    read_ba    <=  rd_addr[23:22];
                    read_addr  <=  {4'b0000,rd_addr[8:0]};//其实列地址只需9位，但是，需要补4个零，因为数据长度为13,A10为0，不进行自动预充电
                end
                RD_RDATA:begin
                    read_ba    <=  2'b11;
                    read_addr  <=  13'h1fff;
                    if (cnt_clk == rd_burst_len - 'd1) begin //提前两个时钟周期发送突发停止命令
                        read_cmd <=  B_TERM; 
                    end else begin
                        read_cmd   <=  NOP;
                    end
                end
                RD_PRE:begin
                    read_cmd   <= PRECHARGE;
                    read_ba    <=  2'b11;
                    read_addr  <=  13'h1fff;
                end
                default: begin
                    read_cmd   <=  NOP;
                    read_ba    <=  2'b11;
                    read_addr  <=  13'h1fff;
                end
            endcase
        end
    end

always @(posedge sys_clk) begin
    if (~sys_rst_n) begin
        rd_fifo_wr_en <= 0;
    end else if (rd_state == RD_CAS && cnt_clk == RD_CAS_CLK - 'd1) begin //通过计数器，控制rd_fifo_wr_en何时有效
        rd_fifo_wr_en <= 1;
    end else if (rd_state == RD_RDATA && cnt_clk == rd_burst_len + 'd2) begin
        rd_fifo_wr_en <= 0;
    end
end

//对rd_data寄存一下，有利于布局布线，但是rd_data_reg并没有相对于rd_data延迟一个周期，因为rd_data是同步于sys_clk_shift（sdram的时钟）时钟
reg [15:0] rd_data_reg;
always @(posedge sys_clk) begin
    rd_data_reg <= rd_data;
end

assign rd_fifo_wr_data = rd_fifo_wr_en? rd_data_reg : 0;

assign rd_end = (rd_state == RD_END)? 1'b1: 1'b0;


endmodule