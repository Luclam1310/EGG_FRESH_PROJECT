import mlp_weights_pkg::*;

// ============================================================
// MLP Inference Module (FIXED)
// 
// Quantization scheme:
//   Features    : Q8  (float * 256), signed int16
//   Weights W1,W2,W3: Q8  (float * 256), signed int16
//   Biases B1,B2,B3 : Q16 (float * 65536), signed int32
//
// Layer math:
//   acc = B_q16 + sum(feat_q8 * W_q8)
//   acc is in Q16 (float * 65536)
//   output_q8 = ReLU(acc >> 8)  → Q8 (float * 256), stored in int16
//
// Final output:
//   acc_final >> 16 = day count (integer)
// ============================================================
module mlp_inference (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        i_start,
    input  logic [15:0] i_raw_channels [0:5],
    output logic [7:0]  o_score,
    output logic        o_done
);

    typedef enum logic [2:0] {IDLE, PRE_PROC, CALC_L1, CALC_L2, CALC_L3, DONE} state_t;
    state_t state;

    // Features: Q8 signed (float * 256)
    logic signed [15:0] features [0:11];
    // Layer outputs: Q8 signed (float * 256)
    logic signed [15:0] layer1_out [0:15];
    logic signed [15:0] layer2_out [0:7];
    
    integer cnt_i, cnt_j, k;

    // 64-bit accumulator for dot products
    // acc = B_q16 + sum(feat_q8 * W_q8)  => 32-bit is enough but use 64 for safety
    logic signed [63:0] acc;
    
    // Pre-processing temporaries
    logic [31:0]        v_sum;
    logic signed [31:0] v_diff_q8, v_ratio_q16, v_diff_q16;
    logic signed [63:0] v_prod;

    // ============================================================
    // Pre-processing task
    // Converts raw 16-bit channel readings to Q8 normalized features
    //
    // Raw channels (k=0..5):
    //   features[k] = ((raw[k]<<8) - MEAN_RAW[k]) * STD_INV[k] >> 16
    //   MEAN_RAW is Q8 (mean*256), STD_INV is Q16 (65536/std)
    //   Result: (raw-mean)/std * 256  = normalized_float * 256  ✓
    //
    // Ratio channels (k=6..11):
    //   ratio_q16 = (raw[k] << 16) / total        (Q16 fraction)
    //   features[k+6] = (ratio_q16 - MEAN_RATIO[k]) * STD_INV[k+6] >> 24
    //   MEAN_RATIO is Q16 (mean*65536), STD_INV is Q16
    //   Result: (ratio-mean)/std * 256  = normalized_float * 256  ✓
    // ============================================================
    task pre_processing();
    begin
        v_sum = 0;
        for (k = 0; k < 6; k = k + 1)
            v_sum = v_sum + i_raw_channels[k];
        if (v_sum == 0) v_sum = 1;

        // Raw channels → Q8 features
        for (k = 0; k < 6; k = k + 1) begin
            v_diff_q8 = ($signed({16'd0, i_raw_channels[k]}) <<< 8)
                        - $signed(SCALER_MEAN_RAW[k]);
            v_prod = $signed(v_diff_q8) * $signed(SCALER_STD_INV[k]);
            features[k] = v_prod[31:16];   // >> 16 → Q8
        end

        // Ratio channels → Q8 features
        for (k = 0; k < 6; k = k + 1) begin
            v_ratio_q16 = ($signed({16'd0, i_raw_channels[k]}) <<< 16)
                          / $signed({32'd0, v_sum});
            v_diff_q16  = v_ratio_q16 - $signed(SCALER_MEAN_RATIO[k]);
            v_prod      = $signed(v_diff_q16) * $signed(SCALER_STD_INV[k+6]);
            features[k+6] = v_prod[39:24]; // >> 24 → Q8
        end
    end
    endtask

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; o_done <= 0; o_score <= 0;
        end else begin
            case (state)
                IDLE: begin
                    o_done <= 0;
                    if (i_start) state <= PRE_PROC;
                end
                
                PRE_PROC: begin
                    pre_processing();
                    cnt_i <= 0; cnt_j <= 0; acc <= 0;
                    state <= CALC_L1;
                end

                // ------------------------------------------------
                // Layer 1: 12 inputs → 16 outputs
                // acc = B1_q16 + sum(features * W1)
                // cnt_j=0: load bias; cnt_j=1..12: accumulate
                // cnt_j=12: store ReLU(acc >> 8) → layer1_out
                // ------------------------------------------------
                CALC_L1: begin
                    if (cnt_j == 0) begin
                        acc <= $signed(B1[cnt_i]);  // B is Q16, load directly
                    end else begin
                        acc <= acc + ($signed(features[cnt_j-1]) *
                                      $signed(W1[cnt_j-1][cnt_i]));
                    end

                    if (cnt_j == 12) begin
                        // acc >> 8 converts Q16 accumulator to Q8 output
                        layer1_out[cnt_i] <= (acc > 0) ? acc[23:8] : 16'sh0000;
                        cnt_j <= 0;
                        if (cnt_i == 15) begin
                            cnt_i <= 0;
                            state <= CALC_L2;
                        end else
                            cnt_i <= cnt_i + 1;
                    end else
                        cnt_j <= cnt_j + 1;
                end

                // ------------------------------------------------
                // Layer 2: 16 inputs → 8 outputs
                // ------------------------------------------------
                CALC_L2: begin
                    if (cnt_j == 0) begin
                        acc <= $signed(B2[cnt_i]);
                    end else begin
                        acc <= acc + ($signed(layer1_out[cnt_j-1]) *
                                      $signed(W2[cnt_j-1][cnt_i]));
                    end

                    if (cnt_j == 16) begin
                        layer2_out[cnt_i] <= (acc > 0) ? acc[23:8] : 16'sh0000;
                        cnt_j <= 0;
                        if (cnt_i == 7) begin
                            cnt_i <= 0;
                            state <= CALC_L3;
                        end else
                            cnt_i <= cnt_i + 1;
                    end else
                        cnt_j <= cnt_j + 1;
                end

                // ------------------------------------------------
                // Layer 3: 8 inputs → 1 output (day count)
                // acc >> 16 = final day integer
                // ------------------------------------------------
                CALC_L3: begin
                    if (cnt_j == 0) begin
                        acc <= $signed(B3[0]);
                    end else begin
                        acc <= acc + ($signed(layer2_out[cnt_j-1]) *
                                      $signed(W3[cnt_j-1][0]));
                    end

                    if (cnt_j == 8) begin
                        // acc is Q16 → >> 16 gives day integer
                        if (acc <= 0)
                            o_score <= 8'd0;
                        else if (acc[63:16] > 25)
                            o_score <= 8'd25;
                        else
                            o_score <= acc[23:16];  // day value (0..25)
                        state <= DONE;
                    end else
                        cnt_j <= cnt_j + 1;
                end

                DONE: begin
                    o_done <= 1;
                    state  <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
