/*
 * @Author: bit_stream 
 * @Date: 2024-12-12 10:52:13 
 * @Last Modified by: bit_stream
 * @Last Modified time: 2024-12-12 10:52:45
 */
`timescale  1ns/1ns
module  tb_sdram_init();


wire            rst_n           ;   //复位信号,低有效
//sdram_init
wire    [3:0]   init_cmd        ;   //初始化阶段指令
wire    [1:0]   init_ba         ;   //初始化阶段L-Bank地址
wire    [12:0]  init_addr       ;   //初始化阶段地址总线
wire            init_end        ;   //初始化完成信号

//reg define
reg             sys_clk         ;   //系统时钟
reg             sys_rst_n       ;   //复位信号

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

always  #10 sys_clk = ~sys_clk;

//rst_n:复位信号
assign  rst_n = sys_rst_n;


//------------- sdram_init_inst -------------
sdram_init  sdram_init_inst(

    .sys_clk    (sys_clk   ),
    .sys_rst_n  (rst_n      ),

    .init_cmd   (init_cmd   ),
    .init_ba    (init_ba    ),
    .init_addr  (init_addr  ),
    .init_end   (init_end   )

);

//-------------sdram_model_plus_inst-------------
sdram_model_plus    sdram_model_plus_inst(
    .Dq     (               ),
    .Addr   (init_addr      ),
    .Ba     (init_ba        ),
    .Clk    (sys_clk ),
    .Cke    (1'b1           ),
    .Cs_n   (init_cmd[3]    ),
    .Ras_n  (init_cmd[2]    ),
    .Cas_n  (init_cmd[1]    ),
    .We_n   (init_cmd[0]    ),
    .Dqm    (2'b0           ),
    .Debug  (1'b1           )

);

endmodule