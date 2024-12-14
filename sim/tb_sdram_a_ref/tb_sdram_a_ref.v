/*
 * @Author: bit_stream 
 * @Date: 2024-12-14 15:44:44 
 * @Last Modified by: bit_stream
 * @Last Modified time: 2024-12-14 17:20:08
 */

`timescale  1ns/1ns
module  tb_sdram_a_ref();


wire            rst_n           ;   //复位信号,低有效
//sdram_init
wire    [3:0]   init_cmd        ;   //初始化阶段指令
wire    [1:0]   init_ba         ;   //初始化阶段L-Bank地址
wire    [12:0]  init_addr       ;   //初始化阶段地址总线
wire            init_end        ;   //初始化完成信号

//sdram_a_ref
wire            a_ref_req        ;   //自动刷新请求
wire            a_ref_end        ;   //自动刷新结束
wire    [3:0]   a_ref_cmd        ;   //自动刷新阶段指令
wire    [1:0]   a_ref_ba         ;   //自动刷新阶段L-Bank地址
wire    [12:0]  a_ref_addr       ;   //自动刷新阶段地址总线

//reg define
reg             sys_clk         ;   //系统时钟
reg             sys_rst_n       ;   //复位信号
reg             a_ref_en         ;   //自动刷新使能


//defparam
//重定义仿真模型中的相关参数
defparam sdram_model_plus_inst.addr_bits = 13;          //地址位宽
defparam sdram_model_plus_inst.data_bits = 16;          //数据位宽
defparam sdram_model_plus_inst.col_bits  = 9;           //列地址位宽
defparam sdram_model_plus_inst.mem_sizes = 2*1024*1024; //L-Bank容量



//时钟、复位信号
initial
  begin
    sys_clk     =   1'b1  ;
    sys_rst_n   <=  1'b0  ;
    #200
    sys_rst_n   <=  1'b1  ;
  end

always  #5 sys_clk = ~sys_clk;

//rst_n:复位信号
assign  rst_n = sys_rst_n;


//a_ref_en:自动刷新使能
always@(posedge sys_clk or negedge rst_n)
    if(rst_n == 1'b0)
        a_ref_en <=  1'b0;
    else    if((init_end == 1'b1) && (a_ref_req == 1'b1))
        a_ref_en <=  1'b1;
    else    if(a_ref_end == 1'b1)
        a_ref_en <=  1'b0;

//sdram_cmd,sdram_ba,sdram_addr

wire    [3:0]   sdram_cmd        ;   
wire    [1:0]   sdram_ba         ;   
wire    [12:0]  sdram_addr       ;   

assign  sdram_cmd = (init_end == 1'b1) ? a_ref_cmd : init_cmd;
assign  sdram_ba = (init_end == 1'b1) ? a_ref_ba : init_ba;
assign  sdram_addr = (init_end == 1'b1) ? a_ref_addr : init_addr;


//------------- sdram_init_inst -------------
sdram_init  sdram_init_inst(

    .sys_clk    (sys_clk   ),
    .sys_rst_n  (rst_n      ),

    .init_cmd   (init_cmd   ),
    .init_ba    (init_ba    ),
    .init_addr  (init_addr  ),
    .init_end   (init_end   )

);


//------------- sdram_a_ref_inst -------------
sdram_a_ref sdram_a_ref_inst(

    .sys_clk     (sys_clk  ),
    .sys_rst_n   (rst_n     ),
    .init_end    (init_end  ),
    .a_ref_en     (a_ref_en   ),

    .a_ref_req    (a_ref_req  ),
    .a_ref_cmd    (a_ref_cmd  ),
    .a_ref_ba     (a_ref_ba   ),
    .a_ref_addr   (a_ref_addr ),
    .a_ref_end    (a_ref_end  )

);

//-------------sdram_model_plus_inst-------------
sdram_model_plus    sdram_model_plus_inst(
    .Dq     (               ),
    .Addr   (sdram_addr     ),
    .Ba     (sdram_ba       ),
    .Clk    (sys_clk ),
    .Cke    (1'b1           ),
    .Cs_n   (sdram_cmd[3]   ),
    .Ras_n  (sdram_cmd[2]   ),
    .Cas_n  (sdram_cmd[1]   ),
    .We_n   (sdram_cmd[0]   ),
    .Dqm    (2'b0           ),
    .Debug  (1'b1           )

);

endmodule