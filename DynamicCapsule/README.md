# DynamicCapsule (StatusIsland) for iPhone 7 Plus (iOS 15.8.x)

Ứng dụng tạo viên thuốc Dynamic Island thu nhỏ hiển thị đè lên màn hình (Overlay Window Level > StatusBar) dành cho iPhone màn hình 16:9 (iPhone 7 Plus, Apple A10 Fusion, iOS 15.8.x).

## Tính năng
- **Window Overlay xuyên thấu (Hit-testing pass-through):** Cửa sổ phủ toàn màn hình nhưng chỉ chặn cảm ứng trong vùng mép trên (`y <= 90 pt`). Toàn bộ ứng dụng bên dưới và SpringBoard hoạt động hoàn toàn bình thường.
- **Giám sát thời gian thực:**
  - Pin: % Pin, đổi màu (Xanh lá / Vàng / Đỏ), hiệu ứng tia sét khi sạc.
  - Mạng: Nhận diện WiFi / 4G LTE, đo tốc độ Download (DL) & Upload (UL) theo thời gian thực (KB/s, MB/s).
  - RAM A10 Fusion: Đo RAM khả dụng (`Free x.xx GB / 3.00 GB`) qua Mach kernel APIs `host_statistics64`.
- **Tương tác:**
  - Chạm 1 lần (Tap): Phóng to nhẹ để xem chi tiết 3 cột.
  - Nhấn giữ (Long press): Mở nhanh màn hình Cài đặt (`SettingsView`).
