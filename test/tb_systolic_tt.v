`timescale 1ns/1ps
module tb_systolic_tt;
    reg clk=0, rst=1; always #5 clk = ~clk;
    reg weight_valid=0, weight_last=0; reg [15:0] weight_data=0; wire weight_ready;
    reg act_valid=0, act_last=0; reg [15:0] act_data=0;
    wire [15:0] result_data; wire result_valid, result_last, weights_loaded;
    systolic_tt_top dut(.clk(clk),.rst(rst),.weight_valid(weight_valid),.weight_ready(weight_ready),
      .weight_last(weight_last),.weight_data(weight_data),.act_valid(act_valid),.act_ready(),
      .act_last(act_last),.act_data(act_data),.result_data(result_data),.result_valid(result_valid),
      .result_ready(1'b1),.result_last(result_last),.weights_loaded(weights_loaded));
    integer errors=0; integer got=0;
    // Expected for W=[[2,0],[0,3]], A rows [1,2] then [3,4]: C rows [2,6] then [6,12]
    always @(posedge clk) if (result_valid) begin
        got = got + 1;
        if (got==1 && result_data !== 16'h0602) begin $display("FAIL row0 got %h exp 0602", result_data); errors=errors+1; end
        if (got==2 && result_data !== 16'h0C06) begin $display("FAIL row1 got %h exp 0C06", result_data); errors=errors+1; end
        if (result_valid) $display("result beat %0d: %h (c0=%0d c1=%0d) last=%b", got, result_data, $signed(result_data[7:0]), $signed(result_data[15:8]), result_last);
    end
    initial begin
        repeat(2) @(posedge clk); rst=0; @(posedge clk);
        // Load weights reverse row order: row1 {W11,W10}={3,0} first, then row0 {W01,W00}={0,2} last
        weight_valid=1; weight_data=16'h0300; weight_last=0; @(posedge clk);
        weight_data=16'h0002; weight_last=1; @(posedge clk);
        weight_valid=0; weight_last=0; @(posedge clk);
        // Stream A rows: {A[m][1],A[m][0]}
        act_valid=1; act_data=16'h0201; act_last=0; @(posedge clk);
        act_data=16'h0403; act_last=1; @(posedge clk);
        act_valid=0; act_last=0;
        repeat(8) @(posedge clk);
        if (errors==0 && got==2) $display("TB PASS: 2 result rows, bit-exact vs golden model");
        else $display("TB FAIL: errors=%0d got=%0d", errors, got);
        $finish;
    end
endmodule
