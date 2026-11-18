# Systolic-TT — 2×2 INT8 weight-stationary systolic array

PERURI Chip Hackathon 2026 submission (AI / Edge Accelerator theme), implemented
and simulation-verified in the Sandbox Chip Merah Putih
(https://chip.peruri.co.id/simulator), project `Systolic-TT-2x2-INT8`.

## Design

- 2×2 weight-stationary systolic array for INT8 matrix multiplication `C = A × W`
- Each PE: one signed INT8 weight register + one signed MAC
  (`psum_out = psum_in + act_in × weight_reg`), activations flow west→east,
  partial sums north→south, weights shift north→south during load
- Top level: FSM `S_LOAD → S_STREAM`, activation skew (row r delayed r cycles),
  output deskew (column c delayed N−1−c), 18-bit accumulation, saturation to
  INT8 at the array edge (never wraparound), one global `pipe_en` for backpressure
- Latency: 2N−1 = 3 cycles from consumed activation beat to valid result beat
- Weight load order: rows presented in reverse (row N−1 first, row 0 last),
  `weight_last` on the second beat
- Interface: parallel ready/valid, 16-bit beats (two INT8 per beat):
  `weight_data` / `act_data` / `result_data`, active-high synchronous `rst`

## Files

- `src/systolic_tt.v` — modules `pe_tt`, `pe_array_tt`, `systolic_tt_top`
- `test/tb_systolic_tt.v` — self-checking testbench

## Verified result

Sandbox simulation (Simulasi #2, 18 Nov 2026): **PASS**

- Load W = [[2,0],[0,3]] as beats `16'h0300`, `16'h0002`
- Stream A = [[1,2],[3,4]] as beats `16'h0201`, `16'h0403`
- Results `16'h0602`, `16'h0C06` → C = [[2,6],[6,12]], bit-exact vs golden model

Note: the sandbox's in-browser simulation compiles only the currently selected
file, so running the testbench in the UI needs the DUT merged into the testbench
file (that merged copy lives in the sandbox project). This repo keeps the clean
multi-file layout for the synthesis pipeline (iverilog / Yosys / OpenLane).

## Provenance

Adapted from the open-source `smitarekar/systolic-mm-accelerator` (MIT) —
a 4×4 Q8.8 weight-stationary array — scoped down to 2×2 INT8 for the tile /
pin budget, as described in the hackathon proposal.
