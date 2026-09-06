# VietLicenSure v5.0 — Phần mềm Kiểm tra và Quản lý Bản quyền Hệ thống

Ngày build kỹ thuật: `2026-09-06`
Ngày phát hành: `06/09/2026`
Trạng thái phát hành: `v5.0 chính thức đổi thương hiệu; phiên bản kỹ thuật 5.0.0.1`
ProductVersion/FileVersion: `5.0.0.1`
Trạng thái: `ManagedSigned`; launcher ghim đúng signer và certificate SHA-256

## Giới thiệu

Ngày 06/09/2026, v5.0 chính thức đổi tên từ **Tool Kiểm Tra Máy Tính — Công cụ kiểm tra cấu hình máy và bản quyền phần mềm** thành **VietLicenSure — Phần mềm Kiểm tra và Quản lý Bản quyền Hệ thống**. VietLicenSure vẫn là dòng v5.0 và giữ đầy đủ chức năng của bản trước; gói hiện tại dùng phiên bản kỹ thuật `5.0.0.1`.

Tên gọi kết hợp **Viet** (do người Việt phát triển), **Licen** (`License` — giấy phép/bản quyền phần mềm) và **Sure** (rõ ràng, có kiểm chứng trong phạm vi bằng chứng kỹ thuật). Phần mềm tập trung nâng cấp trải nghiệm sử dụng, khả năng kiểm tra–nhận diện, quy trình khắc phục an toàn, báo cáo và bảo vệ dữ liệu. VietLicenSure hoạt động Offline theo mặc định, không tự tải inventory hoặc báo cáo lên Internet và chỉ dùng Online khi người dùng chủ động cho phép.

## Cập nhật kỹ thuật v5.0.0.1 ngày 06/09/2026

- Trợ lý lập chỉ mục toàn bộ HDSD và toàn bộ lịch sử phiên bản Việt–Anh theo từng mục, dùng được Offline; phạm vi chức năng bao phủ toàn bộ Tool chứ không chỉ Khôi phục key OEM.
- Hỏi một phiên bản có hồ sơ sẽ nhận đầy đủ mục thay đổi; hỏi hai phiên bản sẽ nhận đối chiếu trực tiếp, không suy diễn ngoài tài liệu. Các cụm “bản hiện tại” và “mới nhất” được ánh xạ đúng tới v5.0.0.1.
- Bổ sung mục lịch sử riêng cho bản phát hành kỹ thuật v5.0.0.1 và ma trận kiểm thử mọi mốc ghi nhận từ v1.0.0 đến phiên bản hiện tại.
- Mọi mục HDSD có thể được gọi đúng theo tên: 10 chức năng chính, bốn lựa chọn khắc phục/backup, quản lý giấy phép cục bộ–doanh nghiệp và tám tác vụ của Trung tâm Báo cáo & Bảo đảm.
- Khôi phục các mốc v1.0.0–v1.0.9 bị lược bỏ và sửa nội dung v1.1.0–v3.3 theo hồ sơ phát hành gốc; xác định rõ không có hồ sơ v2.0–v2.3.
- Giải thích đầy đủ quy trình OEM: kiểm tra OA3 chỉ đọc, che key, xác nhận quyền/edition, áp dụng bằng cơ chế Windows chính thức và hậu kiểm tối đa ba lần; đây là một phần của độ phủ toàn bộ chức năng.
- Bổ sung kiểm thử chống nhầm phiên bản Windows/Office/PowerShell/.NET với lịch sử Tool, kiểm thử mọi mục chức năng và kiểm thử toàn vẹn chỉ mục tài liệu.

## Cập nhật kỹ thuật ngày 05/09/2026

- Sửa Trung tâm Báo cáo và Trung tâm Bảo đảm để dùng palette an toàn trên cả giao diện Sáng/Tối.
- Khi xử lý, mở ngay timeline tiến trình riêng nhưng vẫn giữ và cập nhật khu Hoạt động gần đây.
- Cho phép chọn đúng phần mềm Paid/Subscription/Trial; lựa chọn thủ công và hậu kiểm được khóa theo chính lineage đã chọn, không mở rộng sang phần mềm khác hoặc toàn máy.
- Không hiện thao tác xử lý mục còn lại nếu không có ID còn lại chính xác; bằng chứng mạnh chỉ dừng đúng PID/path/hash rồi cách ly executable sau khi tái xác minh danh tính.
- Thông báo thiếu chính sách nhà phát hành plugin nay giải thích đây là khóa bảo mật bình thường, chỉ dẫn cấu hình an toàn và không còn hiển thị như lỗi ứng dụng.
- Đồng bộ Hướng dẫn Việt/Anh, Trợ lý cục bộ và mô tả đủ tám chức năng của Trung tâm Báo cáo & Bảo đảm.

## Cập nhật lịch sử và bài giới thiệu

- Khôi phục lịch sử đầy đủ của các phiên bản công khai từ v1.0 đến v5.0 trong cả tài liệu tiếng Việt và tiếng Anh.
- Viết lại mục v5.0 theo hướng ngắn gọn, chỉ nêu các nâng cấp cốt lõi và xác định rõ v5.0 là bản nâng cấp tiếp theo của v4.9.
- Đồng bộ bài giới thiệu GitHub theo cùng nội dung; không tạo phiên bản mới hoặc nhãn bản dựng nội bộ.

## Nội dung chính của v5.0

- Ba mức quét Quick, Standard và Deep với ngân sách và phạm vi an toàn.
- Danh sách phần mềm cần xem xét được sắp xếp **Cao → Trung bình → Thấp**.
- Phần mềm trả phí, thuê bao hoặc dùng thử chưa xác minh luôn được nhắc kiểm tra giấy phép, không tự kết luận vi phạm.
- Thành phần hệ thống, runtime, codec, extension nền, trình cài đặt, add-in, gói hỗ trợ và trình gỡ driver chỉ nằm trong kiểm kê/báo cáo, không xuất hiện ở cửa sổ xử lý.
- Catalog tích hợp và Online `1.6.3.0` có 94 nhóm sản phẩm, được ký CMS, kiểm tra schema và chống hạ phiên bản.
- Khắc phục tách riêng Windows, Microsoft Office và phần mềm khác; bắt buộc xem trước, Dry Run, backup, xác nhận và hậu kiểm.
- Báo cáo HTML/PDF/JSON/XML được tạo cục bộ và che định danh phần cứng trong bản chia sẻ mặc định.
- Hỗ trợ giao diện responsive, DPI cao, Light/Dark, timeline, plugin khai báo có chữ ký, CLI headless và quản trị nhiều máy.
- Trung tâm **Việc cần xử lý** gom kết quả theo Cao → Trung bình → Thấp và mở đúng thao tác liên quan.
- Tìm kiếm, lọc và so sánh với lần quét trước cùng chế độ: Mới xuất hiện, Đã hết hoặc Không đổi.
- Trung tâm sao lưu–khôi phục kiểm tra HMAC/SHA-256 trước khi cho phép khôi phục.
- Gói hỗ trợ chỉ nhận báo cáo đã che dữ liệu, tạo bản xem trước và loại thông tin nhạy cảm khỏi log chia sẻ.
- Điều hướng chức năng tách rõ **Trở về** và **Đóng**: Trở về quay đúng bước trước và giữ lựa chọn còn hợp lệ; Đóng kết thúc toàn bộ phiên chức năng rồi trở về màn hình chính.
- Mọi phần mềm đều có thể dùng **Mở / tìm trang chính thức**: mở URL HTTPS đã xác minh trong catalog hoặc tìm kiếm an toàn theo tên và nhà phát hành khi chưa có URL trực tiếp.

## Toàn vẹn và lưu ý khi chạy

- EXE, provenance, catalog và update manifest đều có chữ ký hoặc hash đối chiếu.
- Launcher kiểm tra Authenticode, signer được ghim, BuildId và payload trước khi mở thao tác thay đổi hệ thống.
- Bản hiện tại có Authenticode hợp lệ và timestamp DigiCert nhưng dùng chứng thư tự ký được ghim; Windows vẫn có thể hiện `Unknown publisher` hoặc SmartScreen.
- Không tắt Defender hoặc SmartScreen để ép chạy tệp không xác minh được.
- Người dùng đang giữ EXE v5.0.0.0 có thể tải v5.0.0.1 và thay thế thủ công; dữ liệu cũ được giữ làm nguồn migration chỉ đọc.

## Giới hạn công khai

- Đây không phải danh tính code-signing public-CA.
- Gói Microsoft Store được chuẩn bị riêng và chưa thay thế bản ManagedSigned/Pilot hiện tại.
- `Chưa xác minh` không đồng nghĩa phần mềm vi phạm; cần kiểm tra giấy phép, tài khoản hoặc chứng từ chính thức.
