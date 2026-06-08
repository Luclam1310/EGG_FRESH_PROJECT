"""
╔══════════════════════════════════════════════════════════════════════╗
║  EGG FRESHNESS AI - FIX TRIỆT ĐỂ CHO TANG NANO 20K                  ║
║  Sửa lỗi quantization: Q8 features + Q16 bias                        ║
║                                                                      ║
║  Sơ đồ quantization ĐÚNG:                                             ║
║    W (weights): float * 256  → signed int16 (Q8)                     ║
║    B (bias):    float * 65536 → signed int32 (Q16)                   ║
║    MEAN raw:    float * 256  → int (Q8)                               ║
║    MEAN ratio:  float * 65536 → int (Q16)                             ║
║    STD_INV:     65536/std    → int (Q16) — không đổi                  ║
║                                                                      ║
║  Pre-processing ĐÚNG trong FPGA:                                     ║
║    raw[k]:   feat[k] = ((raw<<8) - MEAN_Q8) * STD_INV >> 16          ║
║    ratio[k]: ratio_q16 = (raw<<16)/total                             ║
║              feat[k+6] = (ratio_q16 - MEAN_Q16) * STD_INV >> 24     ║
║                                                                      ║
║  Layer math ĐÚNG:                                                    ║
║    acc = B_q16 + sum(feat_q8 * W_q8)  → acc is Q16 (float*65536)    ║
║    output_q8 = ReLU(acc >> 8)         → Q8 (float*256)               ║
║    final day = acc_final >> 16                                        ║
╚══════════════════════════════════════════════════════════════════════╝
"""

import os, sys
import numpy as np
import pandas as pd
from sklearn.neural_network import MLPRegressor
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
from sklearn.metrics import r2_score, mean_squared_error

CSV_FILE      = "egg_data.csv"
CHANNELS      = ['R', 'S', 'T', 'U', 'V', 'W']
HIDDEN_LAYERS = (16, 8)
MAX_ITER      = 3000

def load_and_prepare(filepath):
    if not os.path.exists(filepath):
        print(f"LỖI: Không tìm thấy {filepath}"); sys.exit(1)
    df = pd.read_csv(filepath)
    X_raw   = df[CHANNELS].values.astype(float)
    total   = X_raw.sum(axis=1, keepdims=True)
    X_ratio = X_raw / (total + 1e-9)
    X = np.hstack([X_raw, X_ratio])
    y = df['day'].values.astype(float)
    return X, y

def train_model(X, y):
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
    scaler = StandardScaler()
    X_train_s = scaler.fit_transform(X_train)
    X_test_s  = scaler.transform(X_test)
    print(f"Đang huấn luyện MLP {HIDDEN_LAYERS}...")
    model = MLPRegressor(hidden_layer_sizes=HIDDEN_LAYERS, activation='relu',
                         solver='adam', max_iter=MAX_ITER, random_state=42)
    model.fit(X_train_s, y_train)
    y_pred = model.predict(X_test_s)
    print(f"R2={r2_score(y_test,y_pred):.4f}, RMSE={np.sqrt(mean_squared_error(y_test,y_pred)):.2f}")
    return model, scaler

def q8_16bit(arr):
    """Quantize float array to Q8 = float*256, stored as int16"""
    return np.clip(np.round(arr * 256), -32768, 32767).astype(int)

def q16_32bit(arr):
    """Quantize float array to Q16 = float*65536, stored as int32"""
    return np.clip(np.round(arr * 65536), -(2**30), 2**30 - 1).astype(int)

def export_to_fpga(model, scaler):
    print("\nĐang xuất file mlp_weights.sv (phiên bản sửa lỗi)...")

    # === Quantize weights và biases ===
    layers_W = [q8_16bit(W) for W in model.coefs_]
    layers_B = [q16_32bit(b) for b in model.intercepts_]

    # === Quantize scaler ===
    # MEAN raw (k=0..5): Q8 = mean * 256  (LỖI CŨ: int(round(mean)) mất precision!)
    mean_raw_q8    = [int(round(v * 256))   for v in scaler.mean_[:6]]
    # MEAN ratio (k=6..11): Q16 = mean * 65536  (không đổi)
    mean_ratio_q16 = [int(round(v * 65536)) for v in scaler.mean_[6:]]
    # STD_INV: Q16 = 65536/std  (không đổi)
    std_inv_q16    = [int(round(65536.0 / v)) if v > 1e-6 else 65536
                      for v in scaler.scale_]

    with open("mlp_weights.sv", 'w', encoding='utf-8') as f:
        f.write("package mlp_weights_pkg;\n\n")

        # --- Scaler: MEAN raw (Q8) ---
        f.write("  // Mean của kênh raw (R,S,T,U,V,W) — Q8 format: mean * 256\n")
        f.write("  // QUAN TRỌNG: dùng *256 để giữ precision (ví dụ mean=0.5 → 128)\n")
        f.write("  parameter int SCALER_MEAN_RAW [0:5] = '{\n    ")
        f.write(', '.join(map(str, mean_raw_q8)))
        f.write("\n  };\n\n")

        # --- Scaler: MEAN ratio (Q16) ---
        f.write("  // Mean của kênh ratio — Q16 format: mean * 65536\n")
        f.write("  parameter int SCALER_MEAN_RATIO [0:5] = '{\n    ")
        f.write(', '.join(map(str, mean_ratio_q16)))
        f.write("\n  };\n\n")

        # --- Scaler: STD_INV (Q16) ---
        f.write("  // Nghịch đảo std-dev — Q16 format: 65536 / std\n")
        f.write("  parameter int SCALER_STD_INV [0:11] = '{\n    ")
        f.write(', '.join(map(str, std_inv_q16)))
        f.write("\n  };\n\n")

        # --- Layer weights & biases ---
        for i, (Wq, Bq) in enumerate(zip(layers_W, layers_B)):
            n_in, n_out = Wq.shape
            f.write(f"  // Layer {i}: ({n_in}, {n_out})\n")
            f.write(f"  // W: signed [15:0] — Q8 (float * 256)\n")
            f.write(f"  // B: signed [31:0] — Q16 (float * 65536)\n")
            f.write(f"  parameter signed [15:0] W{i+1} [{n_in-1}:0][{n_out-1}:0] = '{{\n")
            for i_row, row in enumerate(Wq):
                vals  = ', '.join([f"16'sh{v & 0xFFFF:04X}" for v in row])
                comma = "," if i_row < len(Wq) - 1 else ""
                f.write(f"    {{{vals}}}{comma}\n")
            f.write("  };\n\n")

            f.write(f"  parameter signed [31:0] B{i+1} [{len(Bq)-1}:0] = '{{\n    ")
            f.write(', '.join([f"32'sh{v & 0xFFFFFFFF:08X}" for v in Bq]))
            f.write("\n  };\n\n")

        f.write("endpackage\n")

    print("✓ Đã tạo mlp_weights.sv")
    print(f"  MEAN_RAW_Q8:    {mean_raw_q8}")
    print(f"  MEAN_RATIO_Q16: {mean_ratio_q16}")
    print(f"  Layers W: int16 (Q8), B: int32 (Q16)")

def main():
    X, y = load_and_prepare(CSV_FILE)
    model, scaler = train_model(X, y)
    export_to_fpga(model, scaler)

if __name__ == "__main__":
    main()
