# Hướng dẫn tham gia và tiếp cận mã nguồn có kiểm soát từ v4.9

Áp dụng cho mã nguồn VietLicenSure từ v4.9 trở đi; bản hiện hành là VietLicenSure `v5.0`, phát hành ngày `08/09/2026`.

## Mô hình phát triển

VietLicenSure được cung cấp miễn phí và phát triển cùng cộng đồng thông qua báo lỗi, đề xuất, tài liệu, bản dịch, kiểm thử và đóng góp kỹ thuật. Kể từ v4.9, mã nguồn không còn được công khai, không được phát hành theo giấy phép mã nguồn mở và được tác giả Thanh Việt quản lý theo cơ chế truy cập có kiểm soát. Bản thực thi chính thức tiếp tục được cung cấp miễn phí tại:

<https://github.com/thanhvietithopnghia-rgb/VietLicenSure/releases/download/v5.0/VietLicenSure-v5.0.exe>

Tệp thực thi của nhánh phát triển hiện tại là `VietLicenSure-v5.0.exe`. Chỉ artifact có Authenticode, timestamp và provenance hợp lệ mới được công bố là Stable.

Việc kiểm soát truy cập được áp dụng sau khi tác giả phát hiện VietLicenSure hoặc phiên bản tiền thân bị sao chép, chỉnh sửa, đổi tên/đổi thương hiệu hoặc đóng gói lại rồi phát hành thành một phần mềm khác khi chưa được tác giả cho phép hay ủy quyền. Chính sách nhằm bảo vệ công sức, chất xám, nguồn gốc sản phẩm, tính toàn vẹn của bản phát hành và tránh để người dùng hiểu nhầm bản đã bị sửa là bản chính thức. Thông báo này không nêu danh tính bên thứ ba và không thay thế kết luận của cơ quan có thẩm quyền về một tranh chấp cụ thể.

Phạm vi được kiểm soát gồm mã giao diện, logic nghiệp vụ, quy tắc nhận diện/khắc phục, thành phần build–đóng gói–phát hành, kiểm thử, tài liệu kỹ thuật nội bộ và các tài sản phát triển chưa công bố từ v4.9 trở đi. Tài liệu sử dụng, chính sách, manifest/hash phát hành và kênh phản hồi vẫn được công khai khi phù hợp.

## Tham gia không cần truy cập mã nguồn

Cộng đồng có thể gửi báo lỗi, đề xuất tính năng, tài liệu, bản dịch, kịch bản kiểm thử và mẫu dữ liệu đã loại thông tin nhạy cảm qua các kênh sau:

- báo lỗi: <https://github.com/thanhvietithopnghia-rgb/VietLicenSure/issues/new/choose>;
- hỏi đáp và đề xuất: <https://github.com/thanhvietithopnghia-rgb/VietLicenSure/discussions>;
- lỗ hổng bảo mật: <https://github.com/thanhvietithopnghia-rgb/VietLicenSure/security/advisories/new>;
- yêu cầu truy cập mã nguồn: `thanhvietit.hopnghia@gmail.com`.

Việc tiếp nhận đóng góp không tự chuyển quyền sở hữu và không cấp quyền đối với mã nguồn chưa công bố. Không gửi mã nguồn được kiểm soát, bí mật, dữ liệu cá nhân hoặc lỗ hổng chưa khắc phục qua Issues/Discussions công khai.

## Ai có thể yêu cầu truy cập

Cá nhân hoặc tổ chức có mục đích thiện chí có thể gửi yêu cầu cho một trong các trường hợp:

- học tập hoặc nghiên cứu;
- đánh giá bảo mật và phối hợp tiết lộ có trách nhiệm;
- kiểm định kỹ thuật;
- đề xuất sửa lỗi hoặc đóng góp tính năng;
- rà soát khả năng tích hợp trong phạm vi được tác giả xem xét riêng.

Người muốn tham khảo, học tập hoặc làm việc trực tiếp với mã phải xin ý kiến tác giả trước. Quyền truy cập chỉ có hiệu lực sau khi tác giả chấp thuận **bằng văn bản**, theo đúng mục đích, phạm vi, thời hạn, người được truy cập và điều kiện ghi trong chấp thuận.

## Nội dung nên có trong yêu cầu

Gửi email tới `thanhvietit.hopnghia@gmail.com` và nêu rõ:

1. họ tên, tổ chức và thông tin liên hệ;
2. mục đích nghiên cứu/đánh giá/đóng góp;
3. phạm vi thành phần cần xem;
4. thời gian dự kiến cần truy cập;
5. người sẽ được truy cập và biện pháp bảo vệ dữ liệu nguồn;
6. đầu ra dự kiến, cách công bố kết quả và kế hoạch tiết lộ lỗ hổng nếu có;
7. xác nhận tuân thủ `SOURCE-POLICY-v4.9.md`, `LICENSE-NOTICE.txt` và điều kiện bổ sung trong văn bản chấp thuận.

Tác giả có quyền chấp thuận, giới hạn hoặc từ chối yêu cầu. Việc gửi yêu cầu không tự tạo quyền truy cập.

## Khả năng mở lại mã nguồn

Hiện tại tác giả chưa cam kết ngày mở lại mã nguồn. Chính sách được xem xét định kỳ dựa trên khả năng ngăn việc sao chép/phát hành trái phép, xác minh danh tính người được cấp quyền, bảo vệ thông tin nhạy cảm, duy trì an toàn chuỗi phát hành và xử lý vi phạm. Kết quả xem xét có thể là tiếp tục đóng, mở một số thành phần, cấp quyền theo từng mục đích hoặc mở rộng công khai. Mọi thay đổi chỉ có hiệu lực khi được tác giả công bố chính thức bằng văn bản.

## Giới hạn mặc định của quyền xem

Trừ khi văn bản chấp thuận ghi rõ khác, quyền truy cập không cho phép:

- tạo bản sao ngoài phạm vi tối thiểu cần thiết trong môi trường đã được cấp;
- chia sẻ tài khoản, chuyển quyền truy cập hoặc cho người khác xem mã;
- công bố, mirror, tải lên dịch vụ khác hoặc phát tán toàn bộ/một phần mã nguồn;
- sửa đổi, tạo sản phẩm phái sinh hoặc tích hợp vào sản phẩm/dịch vụ khác;
- đóng gói lại, đổi tên, đổi thương hiệu, mạo danh tác giả hoặc xóa thông tin nguồn gốc;
- bán, cho thuê, thu phí, thương mại hóa hoặc dùng để cung cấp dịch vụ cho bên thứ ba;
- công bố mã nguồn nhạy cảm/lỗ hổng trước khi hoàn tất quy trình tiết lộ có trách nhiệm.

Khả năng clone hoặc tạo bản sao cục bộ do nền tảng kỹ thuật cung cấp không tạo thêm quyền pháp lý. Quyền xem không đồng nghĩa quyền sử dụng lại.

## Đóng góp mã nguồn được chấp thuận

Nếu yêu cầu đóng góp được duyệt, tác giả sẽ cung cấp riêng phạm vi nhánh, tiêu chuẩn kiểm thử, cách gửi thay đổi, cách ghi nhận và điều kiện quyền tác giả. Không gửi mã nguồn v4.9 lên kho công khai, issue công khai, paste service hoặc tệp đính kèm ngoài kênh được chấp thuận. Tác giả duy trì quyền xem xét, yêu cầu sửa, chấp nhận hoặc từ chối đóng góp và quyết định bản phát hành chính thức.

Những kiểm soát kỹ thuật quan trọng của v4.9 gồm:

- manifest nguồn gốc và chữ ký fail-closed cho bản chính thức;
- catalog online khai báo, ký số và chống hạ phiên bản;
- khắc phục theo trạng thái với hậu kiểm, thử lại, policy và yêu cầu Repair riêng;
- báo cáo che định danh theo mặc định.

Các cơ chế này giúp phát hiện bản bị sửa và giảm rủi ro xử lý sai; chúng không thể ngăn tuyệt đối sao chép, chụp màn hình hoặc dịch ngược mã chạy trên máy người nhận.

## Phiên bản trước v4.9

Chính sách này chỉ áp dụng cho mã nguồn từ v4.9 trở đi. Phiên bản cũ tiếp tục chịu điều khoản đi kèm tại thời điểm phát hành; không có thay đổi hồi tố đối với quyền đã được cấp hợp lệ. Việc một phiên bản từng có thể xem công khai không tự biến phiên bản đó thành mã nguồn mở nếu không có giấy phép cấp các quyền mã nguồn mở.

## Tài liệu chính sách chuẩn

- [Chính sách phát triển cộng đồng và mã nguồn có kiểm soát](SOURCE-POLICY-v4.9.md)
- [Thông báo bản quyền và điều khoản sử dụng](LICENSE-NOTICE.txt)
- [Tải trực tiếp VietLicenSure v5.0](https://github.com/thanhvietithopnghia-rgb/VietLicenSure/releases/download/v5.0/VietLicenSure-v5.0.exe)

Nếu nội dung tóm tắt này khác với văn bản chấp thuận riêng hoặc chính sách đầy đủ, văn bản chấp thuận và `SOURCE-POLICY-v4.9.md` được ưu tiên áp dụng.

© 2026 Thanh Việt. Mọi quyền được bảo lưu.
