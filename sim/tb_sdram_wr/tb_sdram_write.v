/*
 * @Author: bit_stream 
 * @Date: 2024-12-15 11:06:39 
 * @Last Modified by: bit_stream
 * @Last Modified time: 2024-12-15 11:49:24
 */
`timescale  1ns/1ns

module  tb_sdram_write();


wire            rst_n           ;   //复位信号,低有效
//sdram_init
wire    [3:0]   init_cmd        ;   //初始化阶段指令
wire    [1:0]   init_ba         ;   //初始化阶段L-Bank地址
wire    [12:0]  init_addr       ;   //初始化阶段地址总线
wire            init_end        ;   //初始化完成信号
//sdram_write
wire    [12:0]  write_addr      ;   //数据写阶段地址总线
wire    [1:0]   write_ba        ;   //数据写阶段L-Bank地址
wire    [3:0]   write_cmd       ;   //数据写阶段指令
wire    [15:0]  wr_sdram_data   ;   //数据写阶段写入SDRAM数据
wire            wr_sdram_en     ;   //数据写阶段写数据有效使能信号
wire            wr_end          ;   //数据写阶段一次突发写结束
wire            sdram_wr_ack    ;   //数据写阶段写响应
//sdram_addr
wire    [12:0]  sdram_addr      ;   //SDRAM地址总线
wire    [1:0]   sdram_ba        ;   //SDRAML-Bank地址
wire    [3:0]   sdram_cmd       ;   //SDRAM指令
wire    [15:0]  sdram_dq        ;   //SDRAM数据总线
//reg define
reg             sys_clk         ;   //系统时钟
reg             sys_clk_shift   ;   //系统时钟
reg             sys_rst_n       ;   //复位信号
reg             wr_en           ;   //写使能
reg     [15:0]  wr_data_in      ;   //写数据

//defparam
//重定义仿真模型中的相关参数
defparam sdram_model_plus_inst.addr_bits = 13;          //地址位宽
defparam sdram_model_plus_inst.data_bits = 16;          //数据位宽
defparam sdram_model_plus_inst.col_bits  = 9;           //列地址位宽
defparam sdram_model_plus_inst.mem_sizes = 2*1024*1024; //L-Bank容量

//********************************************************************//
//**************************** Clk And Rst ***************************//
//********************************************************************//

//时钟、复位信号
initial
  begin
    sys_rst_n     <=  1'b0  ;
    #200
    sys_rst_n   <=  1'b1  ;
  end


initial fork
    #2;
    sys_clk_shift <= 1;
    forever begin
        #5;
        sys_clk_shift <= ~sys_clk_shift;
    end
join

initial fork
    sys_clk <= 1;
    forever begin
        #5;
        sys_clk <= ~sys_clk;
    end
join


//rst_n:复位信号
assign  rst_n = sys_rst_n ;

//wr_en：写数据使能
always@(posedge sys_clk or negedge rst_n)
    if(rst_n == 1'b0)
        wr_en   <=  1'b0;
    else    if(wr_end == 1'b1)
        wr_en   <=  1'b0;
    else    if(init_end == 1'b1)
        wr_en   <=  1'b1;
    else
        wr_en   <=  wr_en;

//wr_data_in:写数据
always@(posedge sys_clk or negedge rst_n)
    if(rst_n == 1'b0)
        wr_data_in  <=  16'd0;
    else    if(wr_data_in == 16'd255)
        wr_data_in  <=  16'd0;
    else    if(sdram_wr_ack == 1'b1)
        wr_data_in  <=  wr_data_in + 1'b1;
    else
        wr_data_in  <=  wr_data_in;

//sdram_cmd,sdram_ba,sdram_addr
assign  sdram_cmd = (init_end == 1'b1) ? write_cmd : init_cmd;
assign  sdram_ba = (init_end == 1'b1) ? write_ba : init_ba;
assign  sdram_addr = (init_end == 1'b1) ? write_addr : init_addr;

//wr_sdram_data
assign  sdram_dq = (wr_sdram_en == 1'b1) ? wr_sdram_data : 16'hz;



//------------- sdram_init_inst -------------
sdram_init  sdram_init_inst(

    .sys_clk    (sys_clk   ),
    .sys_rst_n  (rst_n      ),

    .init_cmd   (init_cmd   ),
    .init_ba    (init_ba    ),
    .init_addr  (init_addr  ),
    .init_end   (init_end   )

);

//------------- sdram_write_inst -------------
sdram_write sdram_write_inst(

    .sys_clk        (sys_clk       ),
    .sys_rst_n      (rst_n          ),
    .init_end       (init_end       ),
    .wr_en          (wr_en          ),

    .wr_addr        (24'h000_000    ),
    .wr_data        (wr_data_in     ),
    .wr_burst_len   (10'd256        ),

    .wr_fifo_rd_en  (sdram_wr_ack   ),
    .wr_end         (wr_end         ),
    .write_cmd      (write_cmd      ),
    .write_ba       (write_ba       ),
    .write_addr     (write_addr     ),
    .wr_sdram_en    (wr_sdram_en    ),
    .wr_sdram_data  (wr_sdram_data  )

);

//-------------sdram_model_plus_inst-------------
sdram_model_plus    sdram_model_plus_inst(
    .Dq     (sdram_dq       ),
    .Addr   (sdram_addr     ),
    .Ba     (sdram_ba       ),
    .Clk    (sys_clk_shift ),
    .Cke    (1'b1           ),
    .Cs_n   (sdram_cmd[3]   ),
    .Ras_n  (sdram_cmd[2]   ),
    .Cas_n  (sdram_cmd[1]   ),
    .We_n   (sdram_cmd[0]   ),
    .Dqm    (4'b0           ),
    .Debug  (1'b1           )

);

endmodule