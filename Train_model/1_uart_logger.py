import serial
import serial.tools.list_ports
import csv
import os
import re
from datetime import datetime

BAUD_RATE   = 115200
CSV_FILE    = "egg_data.csv"   # file lưu dữ liệu

def list_ports():
    """Liệt kê tất cả COM port đang kết nối"""
    ports = serial.tools.list_ports.comports()
    if not ports:
        print("  Không tìm thấy COM port nào!")
        return []
    for p in ports:
        print(f"  {p.device:12s} — {p.description}")
    return [p.device for p in ports]


def parse_line(line: str):
    """
    Phân tích 1 dòng UART thành dict 6 kênh.
    Input : "R:0A1F S:08B2 T:0C44 U:0F30 V:0D11 W:0E50"
    Output: {'R':2591,'S':2226,'T':3140,'U':3888,'V':3345,'W':3664}
    Trả về None nếu dòng không hợp lệ.
    """
    pattern = r'R:([0-9A-Fa-f]{4})\s+S:([0-9A-Fa-f]{4})\s+T:([0-9A-Fa-f]{4})\s+U:([0-9A-Fa-f]{4})\s+V:([0-9A-Fa-f]{4})\s+W:([0-9A-Fa-f]{4})'
    m = re.search(pattern, line.strip())
    if not m:
        return None
    keys = ['R','S','T','U','V','W']
    return {k: int(v, 16) for k, v in zip(keys, m.groups())}


def init_csv(filepath):
    """Tạo file CSV với header nếu chưa tồn tại"""
    if not os.path.exists(filepath):
        with open(filepath, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow([
                'timestamp',
                'day',          # ngày bảo quản (nhập tay)
                'egg_id',       # mã trứng (nhập tay)
                'R', 'S', 'T', 'U', 'V', 'W',
                'HU',           # Haugh Unit đo tay (nhập sau)
                'weight_g',     # cân nặng trứng (g)
                'note'          # ghi chú
            ])
        print(f"  Đã tạo file CSV mới: {filepath}")
    else:
        print(f"  Tiếp tục ghi vào file: {filepath}")


def get_session_info():
    """Hỏi thông tin phiên đo từ người dùng"""
    print("\n" + "─"*50)
    print("THÔNG TIN PHIÊN ĐO")
    print("─"*50)

    while True:
        try:
            day = int(input("  Ngày bảo quản (0,3,6,9,...,27): ").strip())
            if day < 0 or day > 30:
                print("  Vui lòng nhập số từ 0 đến 30")
                continue
            break
        except ValueError:
            print("  Vui lòng nhập số nguyên")

    egg_id = input("  Mã trứng (vd: egg_01): ").strip()
    if not egg_id:
        egg_id = f"egg_{datetime.now().strftime('%H%M%S')}"

    weight = input("  Cân nặng trứng (g), Enter để bỏ qua: ").strip()
    weight = float(weight) if weight else ""

    hu = input("  HU đo tay (nếu đã đo), Enter để bỏ qua: ").strip()
    hu = float(hu) if hu else ""

    note = input("  Ghi chú (Enter để bỏ qua): ").strip()

    return {
        'day': day,
        'egg_id': egg_id,
        'weight': weight,
        'hu': hu,
        'note': note
    }


def select_port():
    """Chọn COM port"""
    print("\n" + "─"*50)
    print("CÁC COM PORT ĐANG CÓ:")
    ports = list_ports()
    if not ports:
        return None

    if len(ports) == 1:
        port = ports[0]
        print(f"  Tự động chọn: {port}")
        return port

    port = input(f"  Nhập tên port (vd: COM3 hoặc /dev/ttyUSB0): ").strip()
    return port


def main():
    print("╔══════════════════════════════════════════════╗")
    print("║     EGG FRESHNESS — UART DATA LOGGER         ║")
    print("╚══════════════════════════════════════════════╝")

    # Chọn port
    port = select_port()
    if not port:
        input("\nKhông có port. Nhấn Enter để thoát.")
        return

    # Thông tin phiên đo
    session = get_session_info()

    # Khởi tạo CSV
    init_csv(CSV_FILE)

    # Kết nối serial
    print(f"\n  Đang kết nối {port} @ {BAUD_RATE} baud...")
    try:
        ser = serial.Serial(port, BAUD_RATE, timeout=3)
    except Exception as e:
        print(f"  LỖI kết nối: {e}")
        input("  Nhấn Enter để thoát.")
        return

    print(f"  ✓ Đã kết nối!")
    print(f"\n  Đang nhận dữ liệu... Nhấn Ctrl+C để dừng và lưu\n")
    print("  " + "─"*44)

    samples = []
    count   = 0

    try:
        while True:
            raw = ser.readline()
            if not raw:
                continue

            try:
                line = raw.decode('utf-8', errors='ignore').strip()
            except Exception:
                continue

            # Bỏ qua dòng HW version
            if line.startswith("HW:"):
                print(f"  [INFO] Firmware: {line}")
                continue

            data = parse_line(line)
            if data is None:
                if line:
                    print(f"  [SKIP] {line}")
                continue

            count += 1
            ts = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

            # In ra màn hình
            vals = "  ".join([f"{k}:{v:5d}" for k, v in data.items()])
            print(f"  #{count:3d}  {vals}")

            # Lưu vào danh sách
            row = {
                'timestamp': ts,
                'day':       session['day'],
                'egg_id':    session['egg_id'],
                **data,
                'HU':        session['hu'],
                'weight_g':  session['weight'],
                'note':      session['note']
            }
            samples.append(row)

            # Tự động lưu mỗi 5 mẫu
            if count % 5 == 0:
                _flush(samples, CSV_FILE)
                print(f"  → Đã lưu {count} mẫu vào {CSV_FILE}")

    except KeyboardInterrupt:
        print(f"\n\n  Đã dừng. Tổng: {count} mẫu.")

    finally:
        ser.close()
        if samples:
            _flush(samples, CSV_FILE)
            print(f"  ✓ Đã lưu vào {CSV_FILE}")

            # In tóm tắt
            if count > 0:
                print(f"\n  Tóm tắt phiên đo:")
                print(f"    Trứng     : {session['egg_id']}")
                print(f"    Ngày      : {session['day']}")
                print(f"    Số mẫu   : {count}")
                for ch in ['R','S','T','U','V','W']:
                    vals = [s[ch] for s in samples]
                    avg  = sum(vals) / len(vals)
                    print(f"    {ch}        : avg={avg:.0f}  min={min(vals)}  max={max(vals)}")


def _flush(samples, filepath):
    """Ghi danh sách samples vào CSV (append mode)"""
    with open(filepath, 'a', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=[
            'timestamp','day','egg_id',
            'R','S','T','U','V','W',
            'HU','weight_g','note'
        ])
        for row in samples:
            writer.writerow(row)
    samples.clear()


if __name__ == "__main__":
    main()
