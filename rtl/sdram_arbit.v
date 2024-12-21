/*
 * @Author: bit_stream 
 * @Date: 2024-12-21 19:15:15 
 * @Last Modified by:   bit_stream 
 * @Last Modified time: 2024-12-21 19:15:15 
 */

module  sdram_arbit
(
    input   wire            sys_clk     ,   //系统时钟
    input   wire            sys_rst_n   ,   //复位信号
//sdram_init
    input   wire    [3:0]   init_cmd    ,   //初始化阶段命令
    input   wire            init_end    ,   //初始化结束标志
    input   wire    [1:0]   init_ba     ,   //初始化阶段Bank地址
    input   wire    [12:0]  init_addr   ,   //初始化阶段数据地址
//sdram_auto_ref
    input   wire            aref_req    ,   //自刷新请求
    input   wire            aref_end    ,   //自刷新结束
    input   wire    [3:0]   aref_cmd    ,   //自刷新阶段命令
    input   wire    [1:0]   aref_ba     ,   //自动刷新阶段Bank地址
    input   wire    [12:0]  aref_addr   ,   //自刷新阶段数据地址
//sdram_write
    input   wire            wr_req      ,   //写数据请求
    input   wire    [1:0]   wr_ba       ,   //写阶段Bank地址
    input   wire    [15:0]  wr_data     ,   //写入SDRAM的数据
    input   wire            wr_end      ,   //一次写结束信号
    input   wire    [3:0]   wr_cmd      ,   //写阶段命令
    input   wire    [12:0]  wr_addr     ,   //写阶段数据地址
    input   wire            wr_sdram_en ,
//sdram_read
    input   wire            rd_req      ,   //读数据请求
    input   wire            rd_end      ,   //一次读结束
    input   wire    [3:0]   rd_cmd      ,   //读阶段命令
    input   wire    [12:0]  rd_addr     ,   //读阶段数据地址
    input   wire    [1:0]   rd_ba       ,   //读阶段Bank地址

    output  reg             aref_en     ,   //自刷新使能
    output  reg             wr_en       ,   //写数据使能
    output  reg             rd_en       ,   //读数据使能

    output  wire            sdram_cke   ,   //SDRAM时钟使能
    output  wire            sdram_cs_n  ,   //SDRAM片选信号
    output  wire            sdram_ras_n ,   //SDRAM行地址选通
    output  wire            sdram_cas_n ,   //SDRAM列地址选通
    output  wire            sdram_we_n  ,   //SDRAM写使能
    output  reg     [1:0]   sdram_ba    ,   //SDRAM Bank地址
    output  reg     [12:0]  sdram_addr  ,   //SDRAM地址总线
    inout   wire    [15:0]  sdram_dq        //SDRAM数据总线
);


    //仲裁阶段使用到的SDRAM  指令集
    localparam NOP                = 4'b0111 ;//空命令
   
    //仲裁阶段的状态机
    localparam IDLE  = 3'b000 ;//初始状态,初始化结束后跳转至仲裁阶段
    localparam ARBIT = 3'b001 ;//仲裁阶段
    localparam AREF  = 3'b010 ;//自动刷新阶段，自动刷新结束后跳转至仲裁阶段
    localparam WR    = 3'b011 ;//SDRAM写数据阶段，写数据结束后跳转至仲裁阶段
    localparam RD    = 3'b100 ;//SDRAM读数据阶段，读数据结束后跳转至仲裁阶段
    
    
    //定义状态机
    reg [2:0] arbit_state;

    //状态机跳转
    always@(posedge sys_clk)
    if(sys_rst_n == 1'b0)
        arbit_state <= IDLE;
    else begin
        case (arbit_state)
           IDLE:begin
               if(init_end) begin
                   arbit_state <= ARBIT;
               end
           end
           ARBIT:begin
               if(aref_req) begin
                    arbit_state <= AREF;
               end else if(wr_req) begin
                    arbit_state <= WR;
               end else if(rd_req) begin
                    arbit_state <= RD;
               end
           end
           AREF:begin
               if (aref_end) begin
                    arbit_state <= ARBIT;
               end
           end
           WR:begin
               if (wr_end) begin
                    arbit_state <= ARBIT;
               end
           end
           RD:begin
               if (rd_end) begin
                    arbit_state <= ARBIT;
               end
           end
            default:begin
                arbit_state <= IDLE;
            end 
        endcase
    end
    

    always @(posedge sys_clk) begin
        if (~sys_rst_n) begin
            aref_en <= 0;
            wr_en   <= 0;
            rd_en   <= 0;
        end else begin
            case (arbit_state)
                IDLE:begin
                    aref_en <= 0;
                    wr_en   <= 0;
                    rd_en   <= 0;
                end 
                ARBIT:begin
                    aref_en <= 0;
                    wr_en   <= 0;
                    rd_en   <= 0;
                end 
                AREF:begin
                    if (aref_end) begin
                        aref_en <= 0;
                    end else begin
                        aref_en <= 1;
                    end
                    wr_en   <= 0;
                    rd_en   <= 0;
                end 
                WR:begin
                    if (wr_end) begin
                        wr_en   <= 0;
                    end else begin
                        wr_en   <= 1;
                    end
                    aref_en <= 0;
                    rd_en   <= 0;
                end 
                RD:begin
                    if (rd_end) begin
                        rd_en   <= 0;
                    end else begin
                        rd_en   <= 1;
                    end
                    aref_en <= 0;
                    wr_en   <= 0;
                end 
                default:begin
                    aref_en <= 0;
                    wr_en   <= 0;
                    rd_en   <= 0;
                end 
            endcase
        end
    end

reg     [3:0]   sdram_cmd   ;   //写入SDRAM命令

always@(*)
    case(arbit_state) 
        IDLE: begin
            sdram_cmd   <=  init_cmd;
            sdram_ba    <=  init_ba;
            sdram_addr  <=  init_addr;
        end
        AREF: begin
            sdram_cmd   <=  aref_cmd;
            sdram_ba    <=  aref_ba;
            sdram_addr  <=  aref_addr;
        end
        WR: begin
            sdram_cmd   <=  wr_cmd;
            sdram_ba    <=  wr_ba;
            sdram_addr  <=  wr_addr;
        end
        RD: begin
            sdram_cmd   <=  rd_cmd;
            sdram_ba    <=  rd_ba;
            sdram_addr  <=  rd_addr;
        end
        default: begin
            sdram_cmd   <=  NOP;
            sdram_ba    <=  2'b11;
            sdram_addr  <=  13'h1fff;
        end
    endcase

    //SDRAM时钟使能
assign  sdram_cke = 1'b1;
//SDRAM数据总线
assign  sdram_dq = (wr_sdram_en == 1'b1) ? wr_data : 16'bz;
//片选信号,行地址选通信号,列地址选通信号,写使能信号
assign  {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} = sdram_cmd;

endmodule