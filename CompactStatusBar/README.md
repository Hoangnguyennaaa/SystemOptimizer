# CompactStatusBar for iPhone 7 Plus (iOS 15.8.x)

Cụm biểu tượng StatusBar thông minh 3-trong-1 (Vòng cung Pin/RAM, Wi-Fi Waves/Speed, 5 Chấm Cellular) vẽ hoàn toàn bằng SwiftUI Vector Graphics, chạy đè lên StatusBar mặc định với quyền TrollStore / Jailbreak Rootless.

## Tính năng chính:
- **Biểu tượng 3-trong-1:**
  1. *Vòng cung Pin:* Hiển thị chính xác % pin, đổi màu thông minh (Xanh lá sạc / Vàng tiết kiệm điện / Đỏ < 20% / Trắng thường). Có hiệu ứng Breathing Glow khi sạc.
  2. *Tâm Wi-Fi & Tốc độ mạng:* Vẽ 3 vòng cung sóng Wi-Fi. Tự động thay thế bằng số tốc độ tải thực tế (VD: `1.4M`, `350K`) khi lưu lượng vượt quá 100 KB/s.
  3. *5 Chấm sóng di động:* Xếp đều theo đường cong đáy, tô sáng tương ứng số vạch sóng.
- **Tương tác nhanh:**
  - Chạm 1 lần: Mở HUD tóm tắt thông số phần cứng (Pin, RAM, Tốc độ, Nhiệt độ chip A10).
  - Chạm 2 lần: Hoán đổi vòng ngoài giữa % Pin và % RAM A10 Fusion đang dùng.
  - Nhấn giữ: Khóa máy ngay lập tức.
- **Tùy biến:** Tùy chọn vị trí (Góc phải / Góc trái / Ở giữa), chỉnh kích thước và độ trong suốt.
