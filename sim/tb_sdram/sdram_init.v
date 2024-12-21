/*
 * @Author: bit_stream 
 * @Date: 2024-12-12 10:51:27 
 * @Last Modified by: bit_stream
 * @Last Modified time: 2024-12-15 10:47:18
 */

`timescale  1ns/1ns

 //初始化流程如下
//上电→100us空命令→预充电命令→等待tRP时间→自动刷新命令→等待tRFC时间→自动刷新命令→等待tRFC时间→模式寄存器配置命令→等待tMRD时间→初始化结束。
module sdram_init (
    input   wire            sys_clk     ,   //系统时钟,频率100MHz
    input   wire            sys_rst_n   ,   //复位信号,低电平有效

    output  reg     [3:0]   init_cmd    ,   //初始化阶段写入sdram的指令,对应的引脚为{cs#,ras#,cas#,we#}
    output  reg     [1:0]   init_ba     ,   //初始化阶段Bank地址
    output  reg     [12:0]  init_addr   ,   //初始化阶段地址数据,辅助预充电操作
                                            //和配置模式寄存器操作,A12-A0,共13位
    output  reg            init_end        //初始化结束信号
);
    //初始化阶段使用到的SDRAM  指令集
    localparam NOP                = 4'b0111 ;//空命令
    localparam PRECHARGE          = 4'b0010 ;//预充电命令
    localparam AUTO_REFRESH       = 4'b0001 ;//自动刷新命令
    localparam LOAD_MODE_REGISTER = 4'b0000 ;//模式寄存器配置命令
    
    //初始化阶段的状态机
    localparam INIT_IDLE  = 3'b000 ;//初始状态，等待100us跳转至预充电状态
    localparam INIT_PRE   = 3'b001 ;//预充电命令
    localparam INIT_TRP   = 3'b010 ;//预充电状态，等待tRP时间跳转至自动刷新
    localparam INIT_A_R   = 3'b011 ;//自动刷新命令
    localparam INIT_TRFC  = 3'b100 ;//等待tRFC时间,两次自动刷新后跳转至模式寄存器配置命令
    localparam INIT_LMR   = 3'b101 ;//模式寄存器配置命令
    localparam INIT_TMRD  = 3'b110 ;//等待tMRD时间，初始化结束
    localparam INIT_END   = 3'b111 ;//初始化结束

    //各个阶段等待的周期数，一个时钟周期为10ns，0.01us
    localparam INIT_WAIT_CLK  = 10_000 ; //100us
    localparam INIT_TRP_CLK   = 2      ; //根据数据手册可知，最小时间为20ns
    localparam INIT_TRFC_CLK  = 7      ; //根据数据手册可知，最小时间为66ns
    localparam INIT_TMRD_CLK  = 2      ; //根据数据手册可知，最小时间为2个CLK

    //自动刷新次数
    localparam INIT_A_R_TIME  = 2 ;


    //定义状态机
    reg [2:0] init_state;

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
            case (init_state)
                INIT_IDLE,INIT_TRP,INIT_TRFC,INIT_TMRD:begin
                    cnt_clk_en <= 1'b1;
                end 
                INIT_PRE,INIT_A_R,INIT_LMR,INIT_END:begin
                    cnt_clk_en <= 1'b0;
                end
                default: begin
                    cnt_clk_en <= cnt_clk_en;
                end
            endcase
        end
    end

    //定义计数器，计数自动刷新的次数
    reg [1:0] cnt_a_r_times;
    always @(posedge sys_clk) begin
        if (~sys_rst_n) begin
            cnt_a_r_times <= 'd0;
        end else if (init_state == INIT_A_R) begin
            cnt_a_r_times <= cnt_a_r_times + 1'b1;
        end
    end



    
    always @(posedge sys_clk) begin
        if (~sys_rst_n) begin
            init_state <= INIT_IDLE;
        end else begin
            case (init_state)
                INIT_IDLE:begin
                    if (cnt_clk == INIT_WAIT_CLK - 'd1) begin 
                        init_state <= INIT_PRE;
                    end else begin
                        init_state <= INIT_IDLE;
                    end
                end 
                INIT_PRE:begin
                    init_state <= INIT_TRP;
                end
                INIT_TRP:begin
                    if (cnt_clk == INIT_TRP_CLK - 'd1) begin
                        init_state <= INIT_A_R;
                    end else begin
                        init_state <= INIT_TRP;
                    end
                end
                INIT_A_R:begin
                    init_state <= INIT_TRFC;
                end
                INIT_TRFC:begin
                    if ((cnt_clk == INIT_TRFC_CLK - 'd1)&&(cnt_a_r_times < INIT_A_R_TIME)) begin
                        init_state <= INIT_A_R;
                    end else if ((cnt_clk == INIT_TRFC_CLK - 'd1)&&(cnt_a_r_times == INIT_A_R_TIME)) begin
                        init_state <= INIT_LMR;
                    end else begin
                        init_state <= INIT_TRFC;
                    end
                end
                INIT_LMR:begin
                    init_state <= INIT_TMRD;
                end
                INIT_TMRD:begin
                    if (cnt_clk == INIT_TMRD_CLK - 'd1) begin
                        init_state <= INIT_END;
                    end else begin
                        init_state <= INIT_TMRD;
                    end
                end
                INIT_END:begin
                    init_state <= INIT_END;
                end
                default: begin
                    init_state <= INIT_IDLE;
                end
            endcase
        end
    end


    always @(posedge sys_clk) begin
        if (~sys_rst_n) begin
            init_cmd  <= NOP;
            init_ba   <= 2'b11;
            init_addr <= 13'h1fff;
            init_end  <= 1'b0;
        end else begin
            case (init_state)
                INIT_IDLE:begin
                    init_cmd  <= NOP;
                    init_ba   <= 2'b11;
                    init_addr <= 13'h1fff;
                    init_end  <= 1'b0;
                end 
                INIT_PRE:begin //A10为1，所有bank进行预充电
                    init_cmd  <= PRECHARGE;
                    init_ba   <= 2'b11;
                    init_addr <= 13'h1fff;
                    init_end  <= 1'b0;
                end 
                INIT_TRP:begin
                    init_cmd  <= NOP;
                    init_ba   <= 2'b11;
                    init_addr <= 13'h1fff;
                    init_end  <= 1'b0;
                end 
                INIT_A_R:begin
                    init_cmd  <= AUTO_REFRESH;
                    init_ba   <= 2'b11;
                    init_addr <= 13'h1fff;
                    init_end  <= 1'b0;
                end 
                INIT_TRFC:begin
                    init_cmd  <= NOP;
                    init_ba   <= 2'b11;
                    init_addr <= 13'h1fff;
                    init_end  <= 1'b0;
                end 
                INIT_LMR:begin
                    init_cmd  <= LOAD_MODE_REGISTER;
                    init_ba   <= 2'b11;
                    init_addr<={
                        3'b000,//A12-A10,保留位
                        1'b0,//A9设置为0，读写方式为突发读和突发写
                        2'b00,//A8,A7参考芯片手册设置为00，默认
                        3'b011,//A6,A5,A4设置011，则CAS latency为3
                        1'b0,//A3为0，突发传输方式为顺序传输
                        3'b111//A2-A0,突发长度为全页
                    };
                    init_end  <= 1'b0;
                end 
                INIT_TMRD:begin
                    init_cmd  <= NOP;
                    init_ba   <= 2'b11;
                    init_addr <= 13'h1fff;
                    init_end  <= 1'b0;
                end
                INIT_END:begin
                    init_cmd  <= NOP;
                    init_ba   <= 2'b11;
                    init_addr <= 13'h1fff;
                    init_end  <= 1'b1;
                end
                default: begin
                    init_cmd  <= init_cmd;
                    init_ba   <= init_ba;
                    init_addr <= init_addr;
                    init_end  <= init_end;
                end
            endcase
        end
    end

    
endmodule