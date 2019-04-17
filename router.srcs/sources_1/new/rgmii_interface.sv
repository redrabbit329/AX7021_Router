`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/16/2019 09:31:17 PM
// Design Name: 
// Module Name: rgmii_interface
// Project Name: 
// Target Devices: xc7z020clg484-2
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

`include "constants.vh"

// write to fifo: data first, then len
// read from fifo: len first, then data

module rgmii_interface(
    input logic clk,
    input logic clk_125m,
    input logic clk_125m_90deg,
    input logic reset,
    
    // rx fifos
    // read len first, then data
    // out is one cycle after en
    // only read when avail is high
    input logic rx_data_en,
    output logic [`BYTE_WIDTH-1:0] rx_data_out,
    input logic rx_len_en,
    output logic [`LENGTH_WIDTH-1:0] rx_len_out,
    output logic rx_avail,

    // tx fifos
    // write data first, then len
    // in is in the same cycle as en
    // only write when avail is high
    input logic tx_data_en,
    output logic [`BYTE_WIDTH-1:0] tx_data_in,
    input logic tx_len_en,
    output logic [`LENGTH_WIDTH-1:0] tx_len_in,
    output logic tx_avail,
    
    // rgmii pins
    input logic [3:0] rgmii_rd,
    input logic rgmii_rx_ctl,
    input logic rgmii_rxc,
    output logic [3:0] rgmii_td,
    output logic rgmii_tx_ctl,
    output logic rgmii_txc
    );

    // rx

    logic [`BYTE_WIDTH-1:0] rx_data_in;
    logic rx_data_full;
    logic rx_data_wen;
    logic rx_data_busy;

    logic [`LENGTH_WIDTH-1:0] rx_len_in;
    logic rx_len_full;
    logic rx_len_wen;
    logic rx_len_empty;
    logic rx_len_busy;

    assign rx_avail = ~rx_len_empty;

    // stores ethernet frame data
    xpm_fifo_async #(
        .READ_DATA_WIDTH(`BYTE_WIDTH),
        .WRITE_DATA_WIDTH(`BYTE_WIDTH),
        .FIFO_WRITE_DEPTH(`MAX_FIFO_SIZE),
        .PROG_FULL_THRESH(`MAX_FIFO_SIZE - `MAX_ETHERNET_FRAME_BYTES)
    ) xpm_fifo_zsync_inst_rx_data (
        .dout(rx_data_out),
        .rd_en(rx_data_en),
        .rd_clk(clk),
        .rst(reset),

        .prog_full(rx_data_full),
        .din(rx_data_in),
        .wr_clk(rgmii_rxc),
        .wr_en(rx_data_wen),
        .wr_rst_busy(rx_data_busy)
    );

    // stores ethernet frame length
    xpm_fifo_async #(
        .READ_DATA_WIDTH(`LENGTH_WIDTH),
        .WRITE_DATA_WIDTH(`LENGTH_WIDTH),
        .FIFO_WRITE_DEPTH(`MAX_FIFO_SIZE),
        .RD_DATA_COUNT_WIDTH(16),
        .WR_DATA_COUNT_WIDTH(16),
        .PROG_FULL_THRESH(`MAX_FIFO_SIZE - 1)
    ) xpm_fifo_zsync_inst_rx_len (
        .dout(rx_len_out),
        .rd_en(rx_len_en),
        .rd_clk(clk),
        .rst(reset),

        .empty(rx_len_empty),
        .prog_full(rx_len_full),
        .din(rx_len_in),
        .wr_clk(rgmii_rxc),
        .wr_en(rx_len_wen),
        .wr_rst_busy(rx_len_busy)
    );

    logic [`BYTE_WIDTH-1:0] rgmii_rx_data;
    logic rgmii_rx_dv;
    logic rgmii_rx_dv_1;
    logic rgmii_rx_err;
    logic trans_rx;
    logic [`LENGTH_WIDTH-1:0] length;

    IDDR #(
        .DDR_CLK_EDGE("SAME_EDGE_PIPELINED")
    ) iddr_inst_rx (
        .Q1(rgmii_rx_dv),
        .Q2(rgmii_rx_err),
        .C(rgmii_rxc),
        .CE(1'b1),
        .D(rgmii_rx_ctl),
        .R(reset)
    );
    
    genvar i;
    for (i = 0;i < 4;i++) begin
        IDDR #(
            .DDR_CLK_EDGE("SAME_EDGE_PIPELINED")
        ) iddr_inst (
            .Q1(rgmii_rx_data[i]),
            .Q2(rgmii_rx_data[i+4]),
            .C(rgmii_rxc),
            .CE(1'b1),
            .D(rgmii_rd[i]),
            .R(reset)
        );
    end


    always_ff @ (posedge rgmii_rxc) begin
        rgmii_rx_dv_1 <= rgmii_rx_dv;
        if (reset == 1'b1) begin
            trans_rx <= 0;
            rgmii_rx_data <= `BYTE_WIDTH'b0;
            rx_data_wen <= 0;
            rx_data_in <= `BYTE_WIDTH'b0;
            length <= 0;
            rx_len_wen <= 1;
            rx_len_in <= `LENGTH_WIDTH'b0;
        end else begin
            // new data in
            if (rgmii_rx_ctl == 1 && rgmii_rx_dv_1 == 0) begin
                // both fifos have enough space
                if (rx_data_full == 0 && rx_len_full == 0 && rx_data_busy == 0 && rx_len_busy == 0) begin
                    trans_rx <= 1;
                end else begin
                    trans_rx <= 0;
                end
            end else if (rgmii_rx_ctl == 0 && rgmii_rx_dv_1 == 1) begin
                trans_rx <= 0;
            end
            if (trans_rx == 1'b0 && rgmii_rx_ctl == 1'b1) begin
                length <= 0;
            end else if (trans_rx == 1'b1) begin
                length <= length + 1;
            end else if (trans_rx == 1'b0 && rgmii_rx_ctl == 1'b0) begin
                length <= 0;
                // write length
                if (length != 0) begin
                    rx_len_wen <= 1;
                    rx_len_in <= length;
                end else begin
                    rx_len_wen <= 0;
                    rx_len_in <= `LENGTH_WIDTH'b0;
                end
            end 

            // write data
            if (length >= 1) begin
                rx_data_in <= rgmii_rx_data;
                rx_data_wen <= 1;
            end else begin
                rx_data_in <= `BYTE_WIDTH'b0;
                rx_data_wen <= 0;
            end
        end
    end

    // tx
    logic tx_data_dv;
    logic [`BYTE_WIDTH-1:0] tx_data_out;
    logic tx_data_ren;
    logic tx_data_full;
    logic tx_len_dv;
    logic [`LENGTH_WIDTH-1:0] tx_len_out;
    logic tx_len_ren;
    logic tx_len_full;
    logic tx_len_empty;
    logic trans_tx;

    assign rgmii_txc = clk_125m_90deg;
    assign tx_avail = ~tx_data_full & ~tx_len_full;

    // stores ethernet frame data
    xpm_fifo_async #(
        .READ_DATA_WIDTH(`BYTE_WIDTH),
        .WRITE_DATA_WIDTH(`BYTE_WIDTH),
        .FIFO_WRITE_DEPTH(`MAX_FIFO_SIZE),
        .PROG_FULL_THRESH(`MAX_FIFO_SIZE - `MAX_ETHERNET_FRAME_BYTES)
    ) xpm_fifo_zsync_inst_tx_data (
        .din(tx_data_in),
        .wr_en(tx_data_en),
        .rst(reset),
        .wr_clk(clk),

        .data_valid(tx_data_dv),
        .dout(tx_data_out),
        .rd_en(tx_data_ren),
        .prog_full(tx_data_full),
        .rd_clk(clk_125m)
    );

    // stores ethernet frame length
    xpm_fifo_async #(
        .READ_DATA_WIDTH(`LENGTH_WIDTH),
        .WRITE_DATA_WIDTH(`LENGTH_WIDTH),
        .FIFO_WRITE_DEPTH(`MAX_FIFO_SIZE),
        .RD_DATA_COUNT_WIDTH(16),
        .WR_DATA_COUNT_WIDTH(16),
        .PROG_FULL_THRESH(`MAX_FIFO_SIZE - 1)
    ) xpm_fifo_zsync_inst_tx_len (
        .din(tx_len_in),
        .wr_en(tx_len_en),
        .rst(reset),
        .wr_clk(clk),

        .data_valid(tx_len_dv),
        .dout(tx_len_out),
        .rd_en(tx_len_ren),
        .empty(tx_len_empty),
        .prog_full(tx_len_full),
        .rd_clk(clk_125m)
    );

    always @ (posedge clk_125m) begin
        if (reset == 1'b1) begin
            trans_tx <= 1;
        end else begin
            // new data out
            if (tx_len_empty == 1'b1) begin
                trans_tx <= 1;
            end else begin
                trans_tx <= 0;
            end
        end
    end
endmodule
