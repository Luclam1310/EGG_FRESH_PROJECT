import pandas as pd
import numpy as np

# Cấu hình tạo mẫu
n_samples = 100
days = [0, 6, 12, 18, 24]
channels = ['R', 'S', 'T', 'U', 'V', 'W']

data = []

for i in range(n_samples):
    egg_id = i + 1
    day = np.random.choice(days)
    
    # Giả lập Haugh Unit (HU): Ngày 0 cao (80-95), Ngày 24 thấp (30-50)
    # HU giảm trung bình 2 đơn vị mỗi ngày
    base_hu = 90 - (day * 2) 
    hu = base_hu + np.random.normal(0, 5) # Thêm nhiễu
    hu = max(min(hu, 100), 20) # Giới hạn 20-100
    
    weight = np.random.normal(60, 5) # Trọng lượng trứng 55-65g
    
    # Giả lập giá trị NIR từ cảm biến AS7263 (Raw counts)
    # Dựa trên hình ảnh bạn đưa: Ngày 0 (đỏ) có Absorbance cao nhất -> Reflectance thấp nhất
    # Vì cảm biến đo Reflectance (phản xạ), nên Ngày 0 sẽ có giá trị counts THẤP nhất
    # Càng để lâu, counts càng TĂNG lên (giống xu hướng ngược lại của đồ thị Absorbance)
    base_values = {
        'R': 200, 'S': 250, 'T': 350, 'U': 600, 'V': 550, 'W': 500
    }
    
    row = {
        'egg_id': egg_id,
        'day': day,
        'HU': round(hu, 2),
        'weight_g': round(weight, 2)
    }
    
    # Tính toán giá trị từng kênh dựa trên ngày (mô phỏng sự thay đổi phổ)
    for ch in channels:
        # Giá trị tăng dần theo ngày (tương ứng độ hấp thụ giảm trong hình của bạn)
        change_factor = 1 + (day * 0.02) 
        val = base_values[ch] * change_factor + np.random.normal(0, 10)
        row[ch] = int(val)
        
    data.append(row)

df = pd.DataFrame(data)
df.to_csv("egg_data.csv", index=False)
print("✅ Đã tạo file 'egg_data.csv' thành công với 100 mẫu!")