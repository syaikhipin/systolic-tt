// Systolic-TT: 2x2 weight-stationary INT8 systolic array (PERURI submission)
// Single-file version for sandbox simulators. Core logic unchanged from proposal:
// PE = weight register + MAC, skew in / deskew out, saturate (never wrap) at edge,
// latency 2N-1 = 3 cycles, weights presented in reverse row order during load.
`timescale 1ns/1ps

module pe_tt (
    input wire clk, input wire rst, input wire pipe_en, input wire weight_load,
    input wire signed [7:0] weight_shift_in, output reg signed [7:0] weight_shift_out,
    input wire signed [7:0] west_act_in, output reg signed [7:0] east_act_out,
    input wire signed [17:0] north_psum_in, output reg signed [17:0] south_psum_out
);
    reg signed [7:0] weight_reg;
    always @(posedge clk) begin
        if (rst) begin
            weight_reg <= 0; weight_shift_out <= 0; east_act_out <= 0; south_psum_out <= 0;
        end else if (pipe_en) begin
            if (weight_load) begin
                weight_reg <= weight_shift_in; weight_shift_out <= weight_shift_in;
            end else begin
                east_act_out <= west_act_in;
                south_psum_out <= north_psum_in + (west_act_in * weight_reg);
            end
        end
    end
endmodule

module pe_array_tt (
    input wire clk, input wire rst, input wire pipe_en, input wire weight_load,
    input wire [15:0] weight_col_in,   // lane c = bits [8c +: 8]
    input wire [15:0] act_row_in,      // lane r = bits [8r +: 8]
    output wire [35:0] psum_col_out    // lane c = bits [18c +: 18]
);
    // Internal wires: act[r][c], psum[r][c]
    wire signed [7:0] act_mid [0:1][0:2];
    wire signed [17:0] psum_mid [0:2][0:1];
    wire signed [7:0] wshift [0:2][0:1];
    genvar r, c;
    generate
        for (c = 0; c < 2; c = c + 1) begin : COL
            assign wshift[0][c] = weight_col_in[8*c +: 8];
            assign psum_mid[0][c] = 18'sd0;
        end
        for (r = 0; r < 2; r = r + 1) begin : ROW
            assign act_mid[r][0] = act_row_in[8*r +: 8];
            for (c = 0; c < 2; c = c + 1) begin : CELL
                pe_tt pe (.clk(clk), .rst(rst), .pipe_en(pipe_en), .weight_load(weight_load),
                    .weight_shift_in(wshift[r][c]), .weight_shift_out(wshift[r+1][c]),
                    .west_act_in(act_mid[r][c]), .east_act_out(act_mid[r][c+1]),
                    .north_psum_in(psum_mid[r][c]), .south_psum_out(psum_mid[r+1][c]));
            end
            assign psum_col_out[18*r +: 18] = psum_mid[2][r];
        end
    endgenerate
endmodule

module systolic_tt_top (
    input wire clk, input wire rst,               // rst: synchronous, active high
    input wire weight_valid, output wire weight_ready, input wire weight_last,
    input wire [15:0] weight_data,                // one row per beat, reverse row order
    input wire act_valid, output wire act_ready, input wire act_last,
    input wire [15:0] act_data,                   // one activation row per beat: {A[m][1],A[m][0]}
    output wire [15:0] result_data, output wire result_valid, input wire result_ready, output wire result_last,
    output wire weights_loaded
);
    localparam S_LOAD = 1'b0, S_STREAM = 1'b1;
    localparam LATENCY = 3; // 2N-1, N=2
    reg state;
    wire load_fire = (state==S_LOAD) && weight_valid && weight_ready;
    wire act_fire  = (state==S_STREAM) && act_valid && act_ready;
    wire out_blocked = result_valid && !result_ready;
    wire pipe_en = (state==S_LOAD) ? weight_valid : !out_blocked;
    assign weight_ready = (state==S_LOAD);
    assign act_ready = (state==S_STREAM) && !out_blocked;
    assign weights_loaded = (state==S_STREAM);
    always @(posedge clk) begin
        if (rst) state <= S_LOAD;
        else if (load_fire && weight_last) state <= S_STREAM;
    end
    // Skew: row 0 no delay, row 1 delayed 1 cycle
    reg signed [7:0] skew1;
    always @(posedge clk) begin
        if (rst) skew1 <= 0; else if (pipe_en) skew1 <= act_data[15:8];
    end
    wire [15:0] act_row_in = {skew1, act_data[7:0]};
    wire [35:0] psum_col_out;
    pe_array_tt arr (.clk(clk), .rst(rst), .pipe_en(pipe_en), .weight_load(state==S_LOAD),
        .weight_col_in(weight_data), .act_row_in(act_row_in), .psum_col_out(psum_col_out));
    // Deskew: col 0 delayed 1, col 1 no delay
    reg signed [17:0] desk0;
    always @(posedge clk) begin
        if (rst) desk0 <= 0; else if (pipe_en) desk0 <= psum_col_out[17:0];
    end
    wire signed [17:0] deskewed [0:1];
    assign deskewed[0] = desk0;
    assign deskewed[1] = psum_col_out[35:18];
    // Saturate 18-bit -> INT8 (no wraparound)
    function signed [7:0] sat8; input signed [17:0] v; begin
        if (v > 18'sd127) sat8 = 8'sd127;
        else if (v < -18'sd128) sat8 = -8'sd128;
        else sat8 = v[7:0];
    end endfunction
    assign result_data = {sat8(deskewed[1]), sat8(deskewed[0])};
    // Valid / last tracking
    reg [LATENCY-1:0] valid_sr, last_sr;
    always @(posedge clk) begin
        if (rst) begin valid_sr <= 0; last_sr <= 0; end
        else if (pipe_en) begin
            valid_sr <= {valid_sr[LATENCY-2:0], act_fire};
            last_sr  <= {last_sr[LATENCY-2:0], act_fire && act_last};
        end
    end
    assign result_valid = valid_sr[LATENCY-1];
    assign result_last  = last_sr[LATENCY-1];
endmodule
