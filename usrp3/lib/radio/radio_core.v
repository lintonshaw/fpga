
// Copyright 2014 Ettus Research

// radio_core
//  Contains all clock-rate DSP components, all radio and hardware controls and settings
//  Designed to connect to a noc_shell

// FIXME Issues:
//   vita time fed to noc_shell for command timing?  or separate radio_ctrl_proc?
//   same for spi_ready
//   put rx and tx on separate ports?
//   multiple rx?

module radio_core
  #(parameter BASE = 0,
    parameter RADIO_NUM = 0)
   (input clk, input reset,
    // Interface to the physical radio (ADC, DAC, controls)
    input [31:0] rx, output [31:0] tx,
    inout [31:0] db_gpio,
    inout [31:0] fp_gpio,
    output [7:0] sen, output sclk, output mosi, input miso,
    output [7:0] misc_outs, output [2:0] leds,
    input pps,
    output sync_dacs,
    
    // Interface to the noc_shell
    input set_stb, input [7:0] set_addr, input [31:0] set_data, output reg [63:0] rb_data,
    output [63:0] vita_time,
    
    input [31:0] tx_tdata, input tx_tlast, input tx_tvalid, output tx_tready,
    input [127:0] tx_tuser,
    
    output [31:0] rx_tdata, output rx_tlast, output rx_tvalid, input rx_tready,
    output [127:0] rx_tuser
    );

   localparam BASE_RX = BASE + 32;
   localparam BASE_TX = BASE + 64;
   
   // Control Section
   //   most misc settings here, keeps time, etc.
   //   FIXME -- how do we handle conflict of this vs. toplevel noc_shell handling of settings bus?
   //   FIXME -- should timekeeping even be handled here, or should it be handled by ZPU or another NoC block?

   wire [63:0] 	  rb_data_rx, rb_data_tx;
   wire [31:0] 	  fp_gpio_readback, gpio_readback, spi_readback;
   wire 	  run_rx, run_tx;
   wire 	  spi_ready;
   wire [31:0] 	  test_readback;
   
   wire [2:0] 	  rb_addr;
   wire [63:0] 	  vita_time_lastpps;
   wire 	  loopback;
   
   localparam SR_DACSYNC   = BASE + 8'd0;
   localparam SR_LOOPBACK  = BASE + 8'd1;
   localparam SR_TEST      = BASE + 8'd2;
   localparam SR_SPI       = BASE + 8'd3;
   localparam SR_GPIO      = BASE + 8'd6;
   localparam SR_MISC_OUTS = BASE + 8'd11;
   localparam SR_READBACK  = BASE + 8'd12;
   localparam SR_LEDS      = BASE + 8'd13;
   localparam SR_FP_GPIO   = BASE + 8'd18;
   localparam SR_TIME      = BASE + 8'd23;

   // Radio Readback Mux
   always @*
     case(rb_addr)
       3'd0 : rb_data <= { spi_readback, gpio_readback};
       3'd1 : rb_data <= vita_time;
       3'd2 : rb_data <= vita_time_lastpps;
       3'd3 : rb_data <= {rx, test_readback};
       3'd4 : rb_data <= {32'h0, fp_gpio_readback};
       3'd5 : rb_data <= {tx,rx};
       3'd6 : rb_data <= {32'h0,RADIO_NUM[31:0]};
       default : rb_data <= 64'd0;
     endcase // case (rb_addr)

   // Write this register with any value to create DAC sync operation
   setting_reg #(.my_addr(SR_DACSYNC), .width(1)) sr_dacsync
     (.clk(clk), .rst(reset), .strobe(set_stb), .addr(set_addr), .in(set_data),
      .out(), .changed(sync_dacs));

   // FIXME
   // Set this register to loop TX data directly to RX data.
   setting_reg #(.my_addr(SR_LOOPBACK), .width(1)) sr_loopback
     (.clk(clk), .rst(reset), .strobe(set_stb), .addr(set_addr), .in(set_data),
      .out(loopback), .changed());

   // Set this register to put a test value on the readback mux.
   setting_reg #(.my_addr(SR_TEST), .width(32)) sr_test
     (.clk(clk), .rst(reset), .strobe(set_stb), .addr(set_addr), .in(set_data),
      .out(test_readback), .changed());

   setting_reg #(.my_addr(SR_READBACK), .width(3)) sr_rdback
     (.clk(clk), .rst(reset), .strobe(set_stb), .addr(set_addr), .in(set_data),
      .out(rb_addr), .changed());

   setting_reg #(.my_addr(SR_MISC_OUTS), .width(8), .at_reset(8'h0)) sr_misc
     (.clk(clk), .rst(reset), .strobe(set_stb), .addr(set_addr), .in(set_data),
      .out(misc_outs), .changed());

   simple_spi_core #(.BASE(SR_SPI), .WIDTH(8), .CLK_IDLE(0), .SEN_IDLE(8'hFF)) radio_spi
     (.clock(clk), .reset(reset),
      .set_stb(set_stb), .set_addr(set_addr), .set_data(set_data),
      .readback(spi_readback), .ready(spi_ready),
      .sen(sen), .sclk(sclk), .mosi(mosi), .miso(miso),
      .debug());

   gpio_atr #(.BASE(SR_GPIO), .WIDTH(32)) gpio_atr
     (.clk(clk),.reset(reset),
      .set_stb(set_stb),.set_addr(set_addr),.set_data(set_data),
      .rx(run_rx), .tx(run_tx),
      .gpio(db_gpio), .gpio_readback(gpio_readback) );

   gpio_atr #(.BASE(SR_FP_GPIO), .WIDTH(32)) fp_gpio_atr
     (.clk(clk),.reset(reset),
      .set_stb(set_stb),.set_addr(set_addr),.set_data(set_data),
      .rx(run_rx), .tx(run_tx),
      .gpio(fp_gpio), .gpio_readback(fp_gpio_readback) );

   gpio_atr #(.BASE(SR_LEDS), .WIDTH(3), .default_ddr(3'b111), .default_idle(3'b000)) gpio_leds
     (.clk(clk),.reset(reset),
      .set_stb(set_stb),.set_addr(set_addr),.set_data(set_data),
      .rx(run_rx), .tx(run_tx),
      .gpio(leds), .gpio_readback() );
/*
   timekeeper #(.BASE(SR_TIME)) timekeeper
     (.clk(clk), .reset(reset), .pps(pps),
      .set_stb(set_stb),.set_addr(set_addr),.set_data(set_data),
      .vita_time(vita_time), .vita_time_lastpps(vita_time_lastpps));

   */
   // radio_tx
   //   Takes in stream of tx sample packets
   //   Returns stream of tx ack packets, but no longer does its own flow control (noc_shell handles that)

   radio_tx #(.BASE(BASE_TX) radio_tx
     (.clk(clk), .reset(reset),
      .tx(tx), .run(run_tx),
      .set_stb(set_stb), .set_addr(set_addr), .set_data(set_data), .rb_data(rb_data_tx),
      .vita_time(vita_time),
      .tx_tdata(tx_tdata), .tx_tlast(tx_tlast), .tx_tvalid(tx_tvalid), .tx_tready(tx_tready),
      .tx_tuser(tx_tuser));
   
   // radio_rx
   //   Returns stream of rx sample packets
   //   Also sends rx error and ack packets back (in line?)
   //   Flow control handled by noc_shell

   wire 	loopback;
   
   // Set this register to loop TX data directly to RX data.
   setting_reg #(.my_addr(BASE + SR_LOOPBACK), .awidth(8), .width(1)) sr_loopback
     (.clk(clk), .rst(reset), .strobe(set_stb), .addr(set_addr), .in(set_data),
      .out(loopback), .changed());

   // /////////////////////////////////////////////////////////////////////////////////
   //  RX Chain

   wire 	strobe_rx;
   wire [31:0] 	sample_rx;
   wire [31:0] 	rx_corr;
   wire [23:0] 	corr_i, corr_q;
   wire [31:0] 	sample_rx = loopback ? tx_loopback : rx_corr;    // Digital Loopback TX -> RX (Pipeline immediately inside rx_frontend)
   assign strobe_rx = run_rx;
   
   rx_control_gen3 #(.BASE(BASE + SR_RX_CTRL)) rx_control_gen3
     (.clk(clk), .reset(reset), .clear(1'b0),
      .set_stb(set_stb), .set_addr(set_addr), .set_data(set_data),
      .vita_time(vita_time),
      .strobe(strobe_rx), .sample(sample_rx), .run(run_rx),
      .rx_tdata(rx_tdata), .rx_tlast(rx_tlast), .rx_tvalid(rx_tvalid), .rx_tready(rx_tready), .rx_tuser(rx_tuser));
   
   generate
      if (USE_RX_CORR==1)
	begin
	   rx_frontend #(.BASE(BASE + SR_RX_FRONT)) rx_frontend
		      (.clk(clk),.rst(reset),
		       .set_stb(set_stb),.set_addr(set_addr),.set_data(set_data),
		       .adc_a(rx[31:16]),.adc_ovf_a(1'b0),
		       .adc_b(rx[15:0]),.adc_ovf_b(1'b0),
		       .i_out(corr_i), .q_out(corr_q),
		       .run(run_rx), .debug());
	   assign rx_corr = {corr_i[23:8], corr_q[23:8]};
	end
      else
	assign rx_corr = rx;
   endgenerate
   
endmodule // radio_core