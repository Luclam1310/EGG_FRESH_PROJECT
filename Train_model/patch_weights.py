"""
patch_weights.py
Chạy sau 3_train_model.py để thêm SCALER_STD_INV vào mlp_weights.sv
Dùng: python patch_weights.py
"""
import json, re, sys, os

if not os.path.exists("weights_q8.json"):
    print("Cần chạy 3_train_model.py trước!")
    sys.exit(1)

with open("weights_q8.json") as f:
    data = json.load(f)

mean = data['scaler']['mean']   # list 12 floats
std  = data['scaler']['std']    # list 12 floats

# std_inv_q16 = (1/std) * 2^16  → int32
Q16 = 65536
std_inv = [int((1.0/s)*Q16) if s > 0 else Q16 for s in std]
mean_int = [int(round(m)) for m in mean]

insert_block = "\n  // Scaler inverse std (Q16 fixed-point: 1/std * 2^16)\n"
insert_block += f"  parameter int SCALER_STD_INV [0:11] = '{{"
insert_block += ', '.join(str(v) for v in std_inv)
insert_block += "};\n"

with open("mlp_weights.sv", "r") as f:
    src = f.read()

# Chèn sau dòng SCALER_STD
if "SCALER_STD_INV" in src:
    print("SCALER_STD_INV đã tồn tại, bỏ qua.")
else:
    src = src.replace(
        "endpackage",
        insert_block + "\nendpackage"
    )
    with open("mlp_weights.sv", "w") as f:
        f.write(src)
    print("✓ Đã thêm SCALER_STD_INV vào mlp_weights.sv")

# In summary
print(f"\nScaler mean    : {mean_int}")
print(f"Scaler std_inv : {std_inv}")
