/*
 * @Author: bit_stream 
 * @Date: 2024-12-14 11:21:39 
 * @Last Modified by: bit_stream
 * @Last Modified time: 2024-12-14 17:09:01
 */

//自动刷新流程如下
//每隔7.81us发出读请求→ 预充电命令→等待tRP时间→自动刷新命令→等待tRFC时间→自动刷新命令→等待tRFC时间

`timescale  1ns/1ns

module sdram_a_ref (
    input   wire            sys_clk     ,   //系统时钟,频率100MHz
    input   wire            sys_rst_n   ,   //复位信号,低电平有效
    input   wire            init_end    ,   //初始化结束信号
    input   wire            a_ref_en     ,   //自动刷新使能，当没有进行数据读写时进行自动刷新

    output  reg             a_ref_req    ,   //自动刷新请求
    output  reg     [3:0]   a_ref_cmd    ,   //自动刷新阶段写入sdram的指令,{cs_n,ras_n,cas_n,we_n}
    output  reg     [1:0]   a_ref_ba     ,   //自动刷新阶段Bank地址
    output  reg     [12:0]  a_ref_addr   ,   //地址数据,辅助预充电操作,A12-A0,13位地址
    output  wire            a_ref_end        //自动刷新结束标志
);

    //自动刷新阶段使用到的SDRAM  指令集
    localparam NOP                = 4'b0111 ;//空命令
    localparam PRECHARGE          = 4'b0010 ;//预充电命令
    localparam AUTO_REFRESH       = 4'b0001 ;//自动刷新命令
    
    //自动刷新阶段的状态机
    localparam A_REF_IDLE  = 3'b000 ;//初始状态，a_ref_en为1并且初始化结束时跳转至预充电状态
    localparam A_REF_PRE   = 3'b001 ;//预充电命令
    localparam A_REF_TRP   = 3'b010 ;//预充电状态，等待tRP时间跳转至自动刷新
    localparam A_REF_A_R   = 3'b011 ;//自动刷新命令
    localparam A_REF_TRFC  = 3'b100 ;//等待tRFC时间,两次自动刷新后跳转至自动刷新结束
    localparam A_REF_END   = 3'b101 ;
   
    //各个阶段等待的周期数，一个时钟周期为10ns，0.01us
    localparam A_REF_WAIT_CLK  = 781 ;    //7.81us
    localparam A_REF_TRP_CLK   = 2      ; //根据数据手册可知，最小时间为20ns
    localparam A_REF_TRFC_CLK  = 7      ; //根据数据手册可知，最小时间为66ns

    //自动刷新次数，每隔7.81us进行两次刷新操作。32ms内就可以把8192行全部刷新玩 
    localparam A_REF_A_R_TIME  = 2 ;


    //定义状态机
    reg [2:0] a_ref_state;

    //定义计数器，计数需要等待的时间
    reg [4:0] cnt_clk;

    //定义计数器使能信号，在特定的状态使能计数器计数
    reg cnt_clk_en; //其为1时，使能计数，其为0时，计数器清零

    
    //定义计数器，计数发出刷新请求的时间
    reg [11:0] cnt_areq;//位宽大一些，计数器计数到最大值归零

    always @(posedge sys_clk) begin
        if (~sys_rst_n ) begin
            cnt_areq <= 0;
        end else if (cnt_areq == A_REF_WAIT_CLK -1) begin
            cnt_areq <= 0;
        end else if(init_end) begin
            cnt_areq <= cnt_areq + 1;
        end
    end

    //a_ref_req每隔7.81us拉高一次，开始进行自动刷新后拉低
    always @(posedge sys_clk) begin
        if (~sys_rst_n) begin
            a_ref_req <= 0;
        end else if (cnt_areq == A_REF_WAIT_CLK -1) begin
            a_ref_req <= 1;
        end else if (a_ref_state == A_REF_PRE) begin
            a_ref_req <= 0;
        end 
    end
    
    

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
            case (a_ref_state)
                A_REF_TRP,A_REF_TRFC:begin
                    cnt_clk_en <= 1'b1;
                end 
                A_REF_IDLE,A_REF_PRE,A_REF_A_R,A_REF_END:begin
                    cnt_clk_en <= 1'b0;
                end
                default: begin
                    cnt_clk_en <= cnt_clk_en;
                end
            endcase
        end
    end




    //定义计数器，计数自动刷新的次数，每次回到初始状态需要清零
    reg [1:0] cnt_a_r_times;
    always @(posedge sys_clk) begin
        if (~sys_rst_n) begin
            cnt_a_r_times <= 'd0;
        end if (a_ref_state == A_REF_IDLE) begin
            cnt_a_r_times <= 'd0;
        end else if (a_ref_state == A_REF_A_R) begin
            cnt_a_r_times <= cnt_a_r_times + 1'b1;
        end
    end

    

    always @(posedge sys_clk) begin
        if (~sys_rst_n) begin
            a_ref_state <= A_REF_IDLE;
        end else begin
            case (a_ref_state)
                A_REF_IDLE:begin
                    if (a_ref_en & init_end) begin
                        a_ref_state <= A_REF_PRE;
                    end 
                end 
                A_REF_PRE:begin
                    a_ref_state <= A_REF_TRP;
                end
                A_REF_TRP:begin
                    if (cnt_clk == A_REF_TRP_CLK - 'd1) begin
                        a_ref_state <= A_REF_A_R;
                    end 
                end
                A_REF_A_R:begin
                    a_ref_state <= A_REF_TRFC;
                end
                A_REF_TRFC:begin
                    if ((cnt_clk == A_REF_TRFC_CLK - 'd1)&&(cnt_a_r_times < A_REF_A_R_TIME)) begin
                        a_ref_state <= A_REF_A_R;
                    end else if ((cnt_clk == A_REF_TRFC_CLK - 'd1)&&(cnt_a_r_times == A_REF_A_R_TIME)) begin
                        a_ref_state <= A_REF_END;
                    end 
                end
                A_REF_END:begin
                    a_ref_state <= A_REF_IDLE;
                end
                default: begin
                    a_ref_state <= a_ref_state;
                end
            endcase
        end
    end


    always @(posedge sys_clk) begin
        if (~sys_rst_n) begin
            a_ref_cmd  <= NOP;
            a_ref_ba   <= 2'b11;
            a_ref_addr <= 13'h1fff;
        end else begin
            case (a_ref_state)
                A_REF_IDLE:begin
                    a_ref_cmd  <= NOP;
                    a_ref_ba   <= 2'b11;
                    a_ref_addr <= 13'h1fff;
                end 
                A_REF_PRE:begin //A10为1，所有bank进行预充电
                    a_ref_cmd  <= PRECHARGE;
                    a_ref_ba   <= 2'b11;
                    a_ref_addr <= 13'h1fff;
                end 
                A_REF_TRP:begin
                    a_ref_cmd  <= NOP;
                    a_ref_ba   <= 2'b11;
                    a_ref_addr <= 13'h1fff;
                end 
                A_REF_A_R:begin
                    a_ref_cmd  <= AUTO_REFRESH;
                    a_ref_ba   <= 2'b11;
                    a_ref_addr <= 13'h1fff;
                end 
                A_REF_TRFC:begin
                    a_ref_cmd  <= NOP;
                    a_ref_ba   <= 2'b11;
                    a_ref_addr <= 13'h1fff;
                end 
                A_REF_END:begin
                    a_ref_cmd  <= NOP;
                    a_ref_ba   <= 2'b11;
                    a_ref_addr <= 13'h1fff;
                end
                
                default: begin
                    a_ref_cmd  <= a_ref_cmd;
                    a_ref_ba   <= a_ref_ba;
                    a_ref_addr <= a_ref_addr;
                end
            endcase
        end
    end

    assign a_ref_end = (a_ref_state == A_REF_END)? 1'b1:1'b0 ;

endmodule