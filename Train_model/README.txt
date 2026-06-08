╔══════════════════════════════════════════════════════════════════╗
║         QUY TRÌNH ĐO ĐỘ TƯƠI TRỨNG — HƯỚNG DẪN CHI TIẾT       ║
║         Tang Nano 20K + AS7263 + Python MLP                     ║
╚══════════════════════════════════════════════════════════════════╝

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CHUẨN BỊ MỘT LẦN DUY NHẤT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Cài Python packages:
  pip install pyserial pandas numpy matplotlib seaborn scikit-learn

Nạp firmware lên Tang Nano 20K:
  - Compile top.sv + as7263_driver.sv + i2c_byte.sv + uart_tx_simple.sv
  - Nạp bitstream qua Gowin Programmer
  - LED xanh trên board sẽ nhấp nháy khi AS7263 đang đo

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
NGÀY 0 — HÔM NAY (mới mua trứng về)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

MỤC TIÊU: Đo 10 trứng, lưu NIR + HU ngày 0

BƯỚC 1 — Đánh số trứng
  - Lấy bút marker, đánh số 01..10 lên vỏ trứng
  - Cân mỗi quả, ghi vào sổ: egg_01=58g, egg_02=61g...
  - Bảo quản ở nhiệt độ phòng 25°C, tránh nắng

BƯỚC 2 — Đo NIR bằng Tang Nano 20K
  a. Cắm Tang Nano 20K vào máy tính qua USB
  b. Mở terminal, chạy:
       python 1_uart_logger.py
  c. Chọn COM port (thường là COM3 hoặc /dev/ttyUSB0)
  d. Nhập thông tin:
       Ngày bảo quản: 0
       Mã trứng: egg_01
       Cân nặng: 58
       HU: (Enter để bỏ qua — đo sau)
  e. Đặt trứng tiếp xúc trực tiếp với cảm biến AS7263
     (phần xích đạo của trứng, giữa hai đầu nhọn và tù)
  f. Chờ 5–10 giây để nhận ~5 lần đo ổn định
  g. Nhấn Ctrl+C để dừng và chuyển trứng tiếp theo
  h. Lặp lại b–g cho egg_02..egg_10

BƯỚC 3 — Đo HU (Haugh Unit) tay
  Công thức: HU = 100 × log10(H − 1.7×W^0.37 + 7.57)
    H = chiều cao lòng trắng (mm)
    W = cân nặng trứng (g)

  Cách đo:
  a. Cân trứng → ghi W
  b. Đập nhẹ trứng lên kính phẳng / mặt bàn sạch
  c. Dùng thước hoặc caliper đo chiều cao lòng trắng tại
     3 điểm cách lòng đỏ 1cm → lấy trung bình → H
  d. Tính HU (hoặc dùng bảng tính online "Haugh Unit calculator")

  Điển hình ngày 0: HU ≈ 85–95 (Grade AA)

BƯỚC 4 — Cập nhật HU vào CSV
  Mở file egg_data.csv bằng Excel hoặc Notepad
  Tìm dòng egg_01, điền HU vào cột HU
  Lưu file

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
NGÀY 3, 6, 9, 12, 15, 18, 21, 24, 27 — LẶP LẠI
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Mỗi 3 ngày, lấy 1 trứng mới từ nhóm dự trữ:

BƯỚC 5 — Lặp lại Bước 2+3+4 với:
  Ngày bảo quản: 3 (hoặc 6, 9...)
  Mã trứng: egg_11 (trứng mới, đánh số tiếp)

  Lịch đo:
  Hôm nay (ngày 0):  egg_01..10   → 10 trứng
  Ngày 3:            egg_11..20   → 10 trứng mới
  Ngày 6:            egg_21..30   → ...
  Ngày 9:            egg_31..40
  Ngày 12:           egg_41..50
  Ngày 15:           egg_51..60
  Ngày 18:           egg_61..70   ← Grade B bắt đầu xuất hiện
  Ngày 21:           egg_71..80
  Ngày 24:           egg_81..90
  Ngày 27:           egg_91..100

  → Tổng: 100 trứng trong 27 ngày

  💡 Lưu ý: Mua đủ 100 trứng NGAY HÔM NAY,
     cất ở phòng 25°C, không để tủ lạnh.
     Cứ 3 ngày lấy ra đo 10 quả.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SAU KHI CÓ ĐỦ DỮ LIỆU (≥ 5 mốc ngày, ≥ 50 trứng có HU)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

BƯỚC 6 — Xem đồ thị phân tích
  python 2_analysis.py
  → Mở thư mục plots/ để xem:
     1_nir_spectrum_by_day.png    — phổ 6 kênh theo ngày
     2_hu_by_day_boxplot.png      — HU boxplot
     3_channel_vs_hu_scatter.png  — tương quan kênh vs HU
     4_radar_by_grade.png         — radar chart theo grade

BƯỚC 7 — Train model và export FPGA
  python 3_train_model.py
  → Xem kết quả R², RMSE, RPD
  → Nếu RPD > 2.5: model tốt, tiếp tục
  → Nếu RPD < 2.0: thu thập thêm dữ liệu

  Files tạo ra:
    mlp_weights.sv   → copy vào project Gowin
    mlp_weights.mem  → dùng với BRAM initialization

BƯỚC 8 — Tích hợp vào FPGA
  a. Copy mlp_weights.sv vào thư mục src/ của project
  b. Thêm module mlp_infer.sv (tôi sẽ viết khi bạn cần)
  c. Kết nối:
     as7263_driver → mlp_infer → uart_tx_simple
  d. UART output: "HU:73 GRADE:AA FRESH:92%\r\n"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CẤU TRÚC FILE CSV
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  timestamp,day,egg_id,R,S,T,U,V,W,HU,weight_g,note
  2024-01-01 08:00:00,0,egg_01,2591,2226,3140,3888,3345,3664,89.5,58.2,
  2024-01-01 08:01:00,0,egg_01,2588,2229,3145,3892,3341,3661,89.5,58.2,

  → Mỗi trứng có nhiều dòng (nhiều lần đo)
  → Script sẽ tự động lấy trung bình

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TIÊU CHUẨN HAUGH UNIT (bài báo Table 1)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Grade AA : HU ≥ 72   → Rất tươi (0–9 ngày ở 25°C)
  Grade A  : HU 60–72  → Tươi     (9–15 ngày)
  Grade B  : HU < 60   → Hết tươi (> 15 ngày)
  HU < 30  → Hỏng, không ăn được

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
MỤC TIÊU HIỆU SUẤT MODEL (theo bài báo)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  R² > 0.85   → Model tốt
  RMSEP < 6   → Sai số HU < 6 đơn vị (chấp nhận được)
  RPD > 2.5   → Xuất sắc (bài báo đạt 3.12)
  Accuracy > 85% phân loại Grade

  Lưu ý: Bài báo dùng 389 bước sóng, AS7263 chỉ có 6.
  Kỳ vọng R² ≈ 0.75–0.88 với 6 kênh — vẫn đủ dùng thực tế.
