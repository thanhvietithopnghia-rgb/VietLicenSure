# Central Dashboard v1

## Mục tiêu

Central Dashboard là giao diện web chính thức, chỉ đọc, chạy trên máy chủ VietLicenSure trong LAN. Dashboard dùng dữ liệu Agent/Server hiện có để IT Manager xem nhanh tình trạng fleet mà không phải kiểm tra từng máy bằng dòng lệnh.

## Phạm vi chính thức

- Hiển thị tổng số máy, Online, Stale, Offline và Cần xem lại.
- Hiển thị máy trạm, IP báo cáo gần nhất, lần kết nối cuối, trạng thái kỹ thuật Windows/Office và kênh kích hoạt.
- Cảnh báo máy lâu không báo cáo, trạng thái kỹ thuật chưa đạt và Last5 thay đổi giữa hai lần inventory.
- Giao diện Việt/Anh, tự làm mới mỗi 60 giây và có nút làm mới thủ công.
- Trạng thái entitlement luôn tách khỏi kích hoạt kỹ thuật và mặc định là `NotVerified`.

## Ranh giới an toàn

- Chỉ đọc: Dashboard không có endpoint tạo lệnh, nhập key, sửa máy trạm hoặc thay đổi cấu hình.
- Không lưu/hiển thị full product key, secret ghép nối, mã quản trị, đường dẫn báo cáo hay ClientId đầy đủ.
- Không CDN, telemetry hoặc cloud; HTML/CSS/JS được phục vụ bởi listener nội bộ.
- API cần bearer token ngẫu nhiên, thời hạn ngắn, lưu trên server dưới dạng SHA-256 và khóa theo IP ở lần dùng đầu.
- Token được chuyển cho trình duyệt bằng URL fragment, xóa khỏi thanh địa chỉ ngay khi trang tải và chỉ giữ trong `sessionStorage`.
- HTTP nội bộ chưa thay thế TLS; Dashboard chỉ dùng trên LAN tin cậy. Hỗ trợ HTTPS/reverse proxy là giới hạn hiện hành.

## Tiêu chí PASS

1. Không có token: trang tĩnh mở được nhưng API trả `401` và không lộ dữ liệu fleet.
2. Token sai/hết hạn/dùng từ IP khác: API trả `401`.
3. Token đúng: API chỉ trả các trường allow-list của Dashboard.
4. Không có chuỗi full key 25 ký tự, secret, AdminVerifier, ClientId đầy đủ hoặc `LatestReportPath` trong phản hồi.
5. Phân loại thời gian nhất quán: Online `<=90 phút`, Stale `>90 phút và <=24 giờ`, Offline `>24 giờ` hoặc thời gian không hợp lệ.
6. UI VI/EN hiển thị tốt ở desktop/mobile, không dùng `innerHTML` cho dữ liệu máy trạm và không tải tài nguyên ngoài.
7. Regression Enterprise, Safety, Offline/i18n, localization và payload đều PASS.
8. Windows VM chứng minh listener sau reboot vẫn phục vụ Dashboard, token/API hoạt động và cleanup trả lab về checkpoint sạch.

## Ngoài phạm vi hiện hành

- Điều khiển từ xa, tự sửa hoặc triển khai key.
- RBAC nhiều vai trò, SSO/AD, HTTPS tích hợp và truy cập Internet.
- Kết luận pháp lý về quyền sở hữu giấy phép.
