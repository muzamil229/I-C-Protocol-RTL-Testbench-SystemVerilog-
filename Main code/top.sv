/////////// Master
 
`timescale 1ns / 1ps
 
module i2c_master( input clk, rst , newd,
input [6:0] addr,
input op,//1-r
inout sda,
output scl,
input [7:0] din,
output [7:0] dout,
output reg busy, ack_err, done
);
 
reg scl_t = 0;
reg sda_t = 0;
 
parameter sys_freq = 40000000; //40 MHz
parameter i2c_freq = 100000;  //// 100k
 
 
parameter clk_count4 = (sys_freq/i2c_freq);/// 400
parameter clk_count1 = clk_count4/4; ///100
 
integer count1 = 0;
reg i2c_clk = 0;
 
///////4x clock
reg [1:0] pulse = 0;
always@(posedge clk)
begin
      if(rst)
       begin
       pulse <= 0;
       count1 <= 0;
       end
       else if (busy == 1'b0) ///pulse count start only after newd
        begin
        pulse <= 0;
        count1 <= 0;
        end
      else if(count1  == clk_count1 - 1)
       begin
       pulse <= 1;
       count1 <= count1 + 1;
       end
      else if(count1  == clk_count1*2 - 1)
       begin
       pulse <= 2;
       count1 <= count1 + 1;
       end
      else if(count1  == clk_count1*3 - 1)
       begin
       pulse <= 3;
       count1 <= count1 + 1;
       end
      else if(count1  == clk_count1*4 - 1)
       begin
       pulse <= 0;
       count1 <= 0;
       end
      else
       begin
       count1 <= count1 + 1;
       end
end
 
//////////////////
reg [3:0] bitcount = 0;
reg [7:0] data_addr   = 0, data_tx = 0;
reg r_ack = 0;
reg [7:0] rx_data = 0;
reg sda_en = 0;
reg r_scl = 0;
reg scl_en = 0;
 
 
typedef enum logic [3:0] {idle = 0, start = 1, write_addr = 2, ack_1 = 3, write_data = 4, read_data = 5, stop = 6, ack_2 =7, master_ack = 8} state_type;
state_type state = idle;
 
always@(posedge clk)
begin
 if(rst)
   begin
    bitcount   <= 0;
    data_addr  <= 0;
    data_tx    <= 0;
    scl_t <= 1;
    sda_t <= 1;
    state <= idle;
    busy  <= 1'b0;
    ack_err <= 1'b0;
    done    <= 1'b0;
   end
else
   begin
                case(state)
                
                //////////////idle state
                      idle:
                      begin
                            done  <= 1'b0;
                            if(newd == 1'b1)
                               begin
                               data_addr  <= {addr,op};
                               data_tx    <= din;
                               busy  <= 1'b1;
                               state <= start;
                               ack_err <= 1'b0;
                               end
                            else
                               begin
                               data_addr  <= 0;
                               data_tx    <= 0;
                               busy  <= 1'b0;
                               state <= idle;
                               ack_err <= 1'b0;
                               end
                      end
                  /////////////////////////////////////////////////////    
                     start: 
                     begin
                         sda_en <= 1'b1; ///send start to slave
                         case(pulse)
                         0: begin scl_t <= 1'b1; sda_t <= 1'b1; end
                         1: begin scl_t <= 1'b1; sda_t <= 1'b1; end
                         2: begin scl_t <= 1'b1; sda_t <= 1'b0; end
                         3: begin scl_t <= 1'b1; sda_t <= 1'b0; end
                         endcase
                         
                             if(count1  == clk_count1*4 - 1)
                             begin
                                state <= write_addr;
                                scl_t <= 1'b0;
                             end
                             else
                                state <= start;
                     end
                 ///////////////////////////////////////////     
                   write_addr: 
                   begin
                      sda_en <= 1'b1;  ///send addr to slave
                      if(bitcount <= 7)
                         begin
                                 case(pulse)
                                 0: begin scl_t <= 1'b0; sda_t <= 1'b0; end
                                 1: begin scl_t <= 1'b0; sda_t <= data_addr[7 - bitcount]; end
                                 2: begin scl_t <= 1'b1;  end
                                 3: begin scl_t <= 1'b1;  end
                                 endcase
                                 if(count1  == clk_count1*4 - 1)
                                 begin
                                    state <= write_addr;
                                    scl_t <= 1'b0;
                                    bitcount <= bitcount + 1;
                                 end
                                 else
                                 begin
                                    state <= write_addr;
                                 end
                             
                         end
                      else
                        begin
                        state <= ack_1;
                        bitcount <= 0;
                        sda_en <= 1'b0;
                        end
                   end   
                   
                   
                   //////////////////////////////////////
                   
                   ack_1 : 
                   begin
                        sda_en <= 1'b0; ///recv ack from slave
                                case(pulse)
                                0:
                                begin
                                    scl_en <= 1'b0;
                                    if(count1 == 20)
                                    begin
                                        r_scl <= scl;
                                    end
                                    else
                                    begin
                                        r_scl <= r_scl;
                                    end
                               end
                               1:
                               begin
                                    scl_en <= 1'b1;
                                    scl_t <= (r_scl == 1'b1) ? 1'b0 : 1'b0;
                                    sda_t <= 1'b00;
                                    r_ack <= sda;
                               end
                               2:
                               begin
                                    scl_en <= 1'b1;
                                    scl_t <= (r_scl == 1'b1) ? 1'b1: 1'b0;
                               end
                               3:
                               begin
                                    scl_en <= 1'b1;
                                    scl_t <= (r_scl == 1'b1) ? 1'b1 : 1'b1;
                               end
                               
                           endcase
                                    
                                    
                   
                       if(count1  == clk_count1*4 - 1)
                                  begin
                                        
                                      if(r_scl == 1'b0)
                                      begin
                                            state <= ack_1;
                                      end
                                         
                                      else if(r_ack == 1'b0 && data_addr[0] == 1'b0)
                                        begin
                                        state <= write_data;
                                        sda_t <= 1'b0;
                                        sda_en <= 1'b1; /////write data to slave
                                        bitcount <= 0;
                                        end
                                      else if (r_ack == 1'b0 && data_addr[0] == 1'b1)
                                      begin
                                        state <= read_data;
                                        sda_t <= 1'b1;
                                        sda_en <= 1'b0; ///read data from slave
                                        bitcount <= 0;
                                      end
                                      else
                                      begin
                                        state <= stop;
                                        sda_en <= 1'b1; ////send stop to slave
                                        ack_err <= 1'b1;
                                      end
                                  end
                                 else
                                  begin
                                    state <= ack_1;
                                  end
                     
                   end
                   
                 write_data: 
                 begin
                   ///write data to slave
                  if(bitcount <= 7)
                         begin
                                 case(pulse)
                                 0: begin scl_t <= 1'b0;   end
                                 1: begin scl_t <= 1'b0;sda_en <= 1'b1; sda_t <= data_tx[7 - bitcount];                                  end
                                 2: begin scl_t <= 1'b1;  end
                                 3: begin scl_t <= 1'b1;  end
                                 endcase
                                 if(count1  == clk_count1*4 - 1)
                                 begin
                                    state <= write_data;
                                    scl_t <= 1'b0;
                                    bitcount <= bitcount + 1;
                                 end
                                 else
                                 begin
                                    state <= write_data;
                                 end
                             
                         end
                      else
                        begin
                        state <= ack_2;
                        bitcount <= 0;
                        sda_en <= 1'b0; ///read from slave
                        end
                 
                 
                 end 
                 ///////////////////////////// read_data
                 
                 read_data: 
                 begin
                 sda_en <= 1'b0; ///read from slave
                 if(bitcount <= 7)
                         begin
                                 case(pulse)
                                 0: begin scl_t <= 1'b0; sda_t <= 1'b0; end
                                 1: begin scl_t <= 1'b0; sda_t <= 1'b0; end
                                 2: begin scl_t <= 1'b1; rx_data[7:0] <= (count1 == 200) ? {rx_data[6:0],sda} : rx_data; end
                                 3: begin scl_t <= 1'b1;  end
                                 endcase
                                 if(count1  == clk_count1*4 - 1)
                                 begin
                                    state <= read_data;
                                    scl_t <= 1'b0;
                                    bitcount <= bitcount + 1;
                                 end
                                 else
                                 begin
                                    state <= read_data;
                                 end
                             
                         end
                      else
                        begin
                        state <= master_ack;
                        bitcount <= 0;
                        sda_en <= 1'b1; ///master will send ack to slave
                        end
                 
                 
                 
                 end
                 ////////////////////master ack -> send nack
                 master_ack : 
                   begin
                      sda_en <= 1'b1;
                      
                                case(pulse)
                                 0: begin scl_t <= 1'b0; sda_t <= 1'b1; end
                                 1: begin scl_t <= 1'b0; sda_t <= 1'b1; end
                                 2: begin scl_t <= 1'b1; sda_t <= 1'b1; end 
                                 3: begin scl_t <= 1'b1; sda_t <= 1'b1; end
                                 endcase
                   
                       if(count1  == clk_count1*4 - 1)
                                  begin
                                      sda_t <= 1'b0;
                                      state <= stop;
                                      sda_en <= 1'b1; ///send stop to slave
                                      
                                  end
                                 else
                                  begin
                                    state <= master_ack;
                                  end
                     
                   end
                 
                 
                 
                 /////////////////ack 2
                 
                  ack_2 : 
                   begin
                     sda_en <= 1'b0; ///recv ack from slave
                                case(pulse)
                                 0: begin scl_t <= 1'b0; sda_t <= 1'b0; end
                                 1: begin scl_t <= 1'b0; sda_t <= 1'b0; end
                                 2: begin scl_t <= 1'b1; sda_t <= 1'b0; r_ack <= sda; end ///recv ack from slave
                                 3: begin scl_t <= 1'b1;  end
                                 endcase
                   
                       if(count1  == clk_count1*4 - 1)
                                  begin
                                      sda_t <= 1'b0;
                                      sda_en <= 1'b1; ///send stop to slave
                                      if(r_ack == 1'b0 )
                                        begin
                                        state <= stop;
                                        ack_err <= 1'b0;
                                        end
                                      else
                                        begin
                                        state <= stop;
                                        ack_err <= 1'b1;
                                        end
                                  end
                                 else
                                  begin
                                    state <= ack_2;
                                  end
                     
                   end
 
                /////////////////////////////////////////////stop  
                   stop: 
                     begin
                     sda_en <= 1'b1; ///send stop to slave
                         case(pulse)
                         0: begin scl_t <= 1'b1; sda_t <= 1'b0; end
                         1: begin scl_t <= 1'b1; sda_t <= 1'b0; end
                         2: begin scl_t <= 1'b1; sda_t <= 1'b1; end
                         3: begin scl_t <= 1'b1; sda_t <= 1'b1; end
                         endcase
                         
                             if(count1  == clk_count1*4 - 1)
                             begin
                                state <= idle;
                                scl_t <= 1'b0;
                                busy <= 1'b0;
                                sda_en <= 1'b1; ///send start to slave
                                done   <= 1'b1;
                             end
                             else
                                state <= stop;
                     end
                     
                     //////////////////////////////////////////////
                      
                 default : state <= idle;
               endcase
   end
end
 
assign sda = (sda_en == 1) ? (sda_t == 0) ? 1'b0 : 1'b1 : 1'bz; /// en = 1 -> write to slave else read
////// if sda_en == 1 then if sda_t == 0 pull line low else release so that pull up make line high
/*
if(sda_en)
   if(!sda_t)
      sda = 0
   else
      sda = z
else
   sda = z
*/
assign scl = (scl_en == 1'b1) ? (scl_t == 0) ? 1'b0 : 1'b1 : 1'bz;
assign dout = rx_data;
endmodule
 
 
///////////////////// Slave
`timescale 1ns / 1ps
 
module i2c_Slave(
input clk,rst,stretch,
inout sda,scl,
output reg ack_err, done
    );
  
typedef enum logic [2:0] {idle = 0, read_addr = 1, send_ack1 = 2, send_data = 3, master_ack = 4, read_data = 5, send_ack2 = 6, wait_stretch = 7} state_type;
state_type state = idle;    
 
reg [7:0] mem [128];
reg [7:0] r_addr;
reg [6:0] addr;
reg r_mem = 0;
reg w_mem = 0;
reg [7:0] dout;
reg [7:0] din;
reg sda_t;
reg sda_en;
reg [3:0] bitcnt = 0;
 
reg scl_en = 0;
reg scl_t = 0;
 
 
///////////// initialize mem
always@(posedge clk)
begin
  if(rst)
  begin
      for(int i = 0 ; i < 128; i++)
        begin
        mem[i] = i;
        end
      dout <= 8'h0;
  end
  else if (r_mem == 1'b1)
   begin
      dout <= mem[addr];
   end
  else if (w_mem == 1'b1)
   begin
      mem[addr] <= din;
   end 
   
end
 
/////////////////////////pulse_gen logic
parameter sys_freq = 40000000;
parameter i2c_freq = 100000;
 
 
parameter clk_count4 = (sys_freq/i2c_freq);
parameter clk_count1 = clk_count4/4;
integer count1 = 0;
reg i2c_clk = 0;
 
///////4x clock
reg [1:0] pulse = 0;
always@(posedge clk)
begin
      if(rst)
       begin
       pulse <= 0;
       end
      else if(count1  == clk_count1 - 1)
       begin
       pulse <= 1;
       count1 <= count1 + 1;
       end
      else if(count1  == clk_count1*2 - 1)
       begin
       pulse <= 2;
       count1 <= count1 + 1;
       end
      else if(count1  == clk_count1*3 - 1)
       begin
       pulse <= 3;
       count1 <= count1 + 1;
       end
      else if(count1  == clk_count1*4 - 1)
       begin
       pulse <= 0;
       count1 <= 0;
       end
      else
       begin
       count1 <= count1 + 1;
       end
end
 
 
reg r_ack;
 
always@(posedge clk)
begin
if(rst)
 begin
                  bitcnt <= 0;
                  state  <= idle;
                  r_addr <= 7'b0000000;
                  sda_en <= 1'b0;
                  sda_t <= 1'b0;
                  addr  <= 0;
                  r_mem <= 0;
                  din   <= 8'h00; 
                  ack_err <= 0;
                  done    <= 1'b0;
 end
 
 else
    begin
      case(state)
               idle: begin
                 scl_en <= 1'b0;
                 sda_en <= 1'b0;
                  if(scl == 1'b1 && sda == 1'b0 && pulse == 2'b11 && count1 == 399) ///detect start and edge
                    state <= read_addr;
                   else
                    state <= idle;
               end
               
               read_addr: 
               begin
                         sda_en <= 1'b0;  ///read addr to slave
                         scl_en <= 1'b0;
                              if(bitcnt <= 7)
                                 begin
                                         case(pulse)
                                         0: begin  end
                                         1: begin  end
                                         2: begin   r_addr <= (count1 == 200) ? {r_addr[6:0],sda} : r_addr; end 
                                         3: begin  end
                                         endcase
                                         if(count1  == clk_count1*4 - 1)
                                         begin
                                            state <= read_addr;
                                            bitcnt <= bitcnt + 1;
                                         end
                                         else
                                         begin
                                            state <= read_addr;
                                         end
                                     
                                 end
                              else
                                begin
                                if(stretch == 1'b1)
                                  begin
                                   state <= wait_stretch;
                                   scl_en <= 1'b1;
                                   bitcnt <= 0;
                                  end
                                else
                                  begin
                                    scl_en <= 1'b0;
                                    state  <= send_ack1;
                                    bitcnt <= 0;
                                    sda_en <= 1'b1;
                                    addr <= r_addr[7:1];
                                 end
                                end
                       
                      end
                      /////////////////////////// send ack
                      wait_stretch :
                       begin
                         
                                    case(pulse)
                                         0: begin scl_en <= 1'b1;  scl_t <= 1'b0; end
                                         1: begin scl_en <= 1'b1;  scl_t <= 1'b0;  end
                                         2: begin scl_en <= 1'b0;  end 
                                         3: begin  end
                                     endcase
                                  if(count1  == clk_count1*4 - 1)
                                       begin
                                          if(stretch == 1'b1)
                                           begin
                                           state <= wait_stretch;
                                           end
                                          else
                                            begin
                                            state <= send_ack1;
                                            scl_en <= 1'b0;
                                            sda_en <= 1'b1;
                                            end
                                         end
                                  else
                                       begin
                                       state <= wait_stretch;
                                       end
                                    
                       
                       
                       end
                      
                      
                      send_ack1: 
                      begin
                                    sda_en <= 1'b1;
                                    case(pulse)
                                         0: begin scl_en <= 1'b1; scl_t <= 1'b1; sda_t <= 1'b0;  end
                                         1: begin scl_en <= 1'b0; end
                                         2: begin  end 
                                         3: begin  end
                                     endcase
                                  if(count1  == clk_count1*4 - 1)
                                       begin
                                          if(r_addr[0] == 1'b1) //read
                                            begin
                                            state <= send_data;
                                            r_mem <= 1'b1;
                                            end
                                          else
                                            begin
                                             state <= read_data;
                                             r_mem <= 1'b0;
                                            end
                                         end
                                  else
                                       begin
                                       state <= send_ack1;
                                       end
                                    
                                    
                      end
                      
                      
                      ///////////////////////read data
                      
                       read_data: 
                        begin
                          sda_en <= 1'b0;  ///read addr to slave
                              if(bitcnt <= 7)
                                 begin
                                         case(pulse)
                                         0: begin  end
                                         1: begin  end
                                         2: begin   din <= (count1 == 200) ? {din[6:0],sda} : din; end 
                                         3: begin  end
                                         endcase
                                         if(count1  == clk_count1*4 - 1)
                                         begin
                                            state <= read_data;
                                            bitcnt <= bitcnt + 1;
                                         end
                                         else
                                         begin
                                            state <= read_data;
                                         end
                                     
                                 end
                              else
                                begin
                                state  <= send_ack2;
                                bitcnt <= 0;
                                sda_en <= 1'b1;
                                w_mem  <= 1'b1;
                                end
                       
                      end
                      /////////////////////////////////////////////
                      send_ack2: 
                      begin
                                   
                                   case(pulse)
                                         0: begin  sda_t <= 1'b0; end
                                         1: begin  w_mem <= 1'b0; end
                                         2: begin  end 
                                         3: begin  end
                                     endcase
                                  if(count1  == clk_count1*4 - 1)
                                         begin
                                          state <= idle;
                                         end
                                  else
                                       begin
                                       state <= send_ack2;
                                       end
                      end
                 /////////////
                 send_data : begin
                     sda_en <= 1'b1;  ///read addr to slave
                              if(bitcnt <= 7)
                                 begin
                                         r_mem  <= 1'b0;
                                         case(pulse)
                                         0: begin    end
                                         1: begin sda_t <= (count1 == 100) ? dout[7 - bitcnt] : sda_t; end
                                         2: begin    end 
                                         3: begin    end
                                         endcase
                                         if(count1  == clk_count1*4 - 1)
                                         begin
                                            state <= send_data;
                                            bitcnt <= bitcnt + 1;
                                         end
                                         else
                                         begin
                                            state <= send_data;
                                         end
                                     
                                 end
                              else
                                begin
                                state  <= master_ack;
                                bitcnt <= 0;
                                sda_en <= 1'b0;
                                end
                     end  
                   //////////////////////////
                   master_ack: 
                   begin
                                   case(pulse)
                                         0: begin  end
                                         1: begin  end
                                         2: begin r_ack <= (count1 == 200) ? sda : r_ack; end 
                                         3: begin  end
                                     endcase
                                  if(count1  == clk_count1*4 - 1)
                                         begin
                                               if(r_ack == 1'b1) ///nack
                                                   begin
                                                   ack_err <= 1'b0;
                                                   state <= idle;
                                                   done  <= 1'b1;
                                                   end
                                               else
                                                    begin
                                                    ack_err <= 1'b1;
                                                    state   <= idle;
                                                    done    <= 1'b1;
                                                    end
                                         end
                                  else
                                       begin
                                       state <= master_ack;
                                       end
                   
                   
                   end
                 
             
      
      default: state <= idle;
      
      endcase
    end
end
 
assign sda = (sda_en == 1'b1) ? sda_t : 1'bz;
assign scl = (scl_en == 1'b1) ? scl_t : 1'bz;
 
endmodule
 
////////////////top
 
`timescale 1ns / 1ps
 
module i2c_top(
input clk, rst, newd, op, stretch,
input [6:0] addr,
input [7:0] din,
output [7:0] dout,
output busy,ack_err,
output done
);
wire sda, scl;
wire ack_errm, ack_errs;
 
i2c_master master (clk, rst, newd, addr, op, sda, scl, din, dout, busy, ack_errm , done);
i2c_Slave slave (clk, rst, stretch, sda, scl, ack_errs, );
 
assign ack_err = ack_errs | ack_errm;
 
 
endmodule
 

            
      
/////////////////////////////////////////////////////////////////////////////////////////////////////////

                
    
module i2c_top_tb;
 
reg clk = 0, rst = 0, newd = 0, op;
reg stretch = 0;
reg [6:0] addr;
reg [7:0] din;
wire [7:0] dout;
wire busy,ack_err;
wire done;
i2c_top dut (clk,rst, newd, op,stretch, addr, din, dout, busy, ack_err, done);
 
always #5 clk = ~clk;
 
initial begin
rst = 1;
repeat(5) @(posedge clk);
rst = 0;
//////////// write operation
 
@(posedge clk);
newd = 1;
stretch = 0;
op = 0;
addr = $urandom_range(0,10);
din  =  $urandom_range(1,5);
repeat(5) @(posedge clk);
@(posedge done);
$display("[WR] din : %0d addr: %0d",din, addr);
@(posedge clk);
 
 
 
@(posedge clk);
newd = 1;
stretch = 1;
op = 0;
addr = $urandom_range(0,10);
din  =  $urandom_range(1,5);
wait(dut.master.state == 3);
repeat(1200)@(posedge clk);
stretch = 0;
@(posedge done);
$display("[WR] din : %0d addr: %0d",din, addr);
$stop;
end
 
endmodule
    
        





