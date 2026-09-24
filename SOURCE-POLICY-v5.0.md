# CHÍNH SÁCH PHÁT TRIỂN CỘNG ĐỒNG VÀ MÃ NGUỒN CÓ KIỂM SOÁT

**Mã tài liệu:** `SOURCE-POLICY-v5.0`  
**Áp dụng:** Từ VietLicenSure v4.9 và tiếp tục áp dụng cho v5.0  
**Cập nhật:** 24/09/2026  
**Chủ sở hữu:** Thanh Việt  
**Bản quyền:** Copyright © 2026 Thanh Việt. Mọi quyền được bảo lưu.

> **Trạng thái tài liệu:** Đây là chính sách hiện hành và là nguồn sự thật chính về việc sử dụng bản thực thi, tiếp cận mã nguồn và đóng góp cho VietLicenSure. Khi có nội dung khác nhau giữa tài liệu này và tài liệu giới thiệu, bản này được ưu tiên đối với chính sách mã nguồn. Tính toàn vẹn của từng bản phát hành vẫn phải được xác minh bằng manifest, chữ ký và checksum đi kèm chính gói đó.

## 1. Mục tiêu và nguyên tắc

VietLicenSure được phát triển và cung cấp miễn phí nhằm hỗ trợ người dùng cá nhân, giáo dục, nghiên cứu, cộng đồng và hoạt động nội bộ hợp pháp của tổ chức.

Dự án khuyến khích cộng đồng tham gia thông qua báo lỗi, đề xuất tính năng, cải thiện tài liệu, bản dịch, kiểm thử, dữ liệu mẫu đã làm sạch và các đóng góp kỹ thuật được chấp thuận.

Kể từ v4.9, VietLicenSure áp dụng mô hình **phát triển cùng cộng đồng với mã nguồn có kiểm soát**. Mã nguồn không được phát hành theo giấy phép mã nguồn mở như GPL, MIT hoặc Apache. Việc phần mềm được cung cấp miễn phí hay tiếp nhận đóng góp không tạo ra quyền tự động truy cập, sao chép, sửa đổi, phân phối, tạo sản phẩm phái sinh hoặc thương mại hóa mã nguồn.

Chính sách này hướng tới bốn mục tiêu:

1. bảo vệ quyền sở hữu trí tuệ và nguồn gốc sản phẩm;
2. bảo vệ người dùng khỏi bản sửa đổi hoặc đóng gói lại không được kiểm soát;
3. duy trì tính toàn vẹn của chuỗi build, ký, đóng gói và phát hành chính thức;
4. tạo điều kiện cho kiểm tra độc lập theo phạm vi và từng giai đoạn phù hợp.

## 2. Lý do áp dụng chính sách kiểm soát

Chính sách được áp dụng sau khi tác giả phát hiện VietLicenSure hoặc sản phẩm tiền thân có dấu hiệu bị sao chép, chỉnh sửa, đổi tên, đổi thương hiệu hoặc đóng gói lại thành sản phẩm khác khi chưa được cho phép.

Những hành vi đó có thể:

- chiếm dụng công sức và tài sản trí tuệ;
- làm người dùng nhầm lẫn về tác giả và nguồn phát hành;
- khiến bản đã bị sửa bị hiểu nhầm là bản chính thức;
- làm suy giảm tính toàn vẹn, khả năng kiểm chứng và mức an toàn của sản phẩm.

Nội dung này không nhằm kết luận một tranh chấp cụ thể hoặc thay thế quyết định của cơ quan có thẩm quyền.

## 3. Phạm vi mã nguồn và tài sản được kiểm soát

Chính sách áp dụng cho toàn bộ mã triển khai từ v4.9 trở đi, bao gồm nhưng không giới hạn:

- mã giao diện và logic nghiệp vụ;
- quy tắc nhận diện, phân tích và khắc phục;
- module, plugin và dữ liệu kỹ thuật nội bộ;
- thành phần build, ký, đóng gói, cập nhật và phát hành;
- bộ kiểm thử, test harness và fixture nội bộ;
- kiến trúc, tài liệu kỹ thuật nội bộ và tài sản phát triển chưa được công bố;
- mã hoặc cấu hình được cấp cho một nhóm kiểm tra theo quyền truy cập hạn chế.

Tài liệu sử dụng, chính sách công khai, manifest, hash, chứng thư công bố, ghi chú phát hành và kênh tiếp nhận phản hồi có thể được công khai khi tác giả xác định phù hợp.

## 4. Quyền sử dụng bản thực thi chính thức

Người dùng được phép:

- tải và sử dụng miễn phí bản thực thi chính thức, nguyên trạng;
- sử dụng cho mục đích hợp pháp cá nhân, giáo dục, nghiên cứu, cộng đồng và nội bộ tổ chức;
- chia sẻ đường dẫn tải chính thức để người khác tự tải và xác minh;
- kiểm tra chữ ký, SHA-256, manifest và thông tin nguồn gốc của bản phát hành;
- gửi báo lỗi, đề xuất, tài liệu, bản dịch hoặc phản hồi qua kênh chính thức.

Nếu chưa có chấp thuận bằng văn bản của tác giả, người dùng không được:

- đăng lại, mirror hoặc phân phối tệp thực thi từ máy chủ hay kho tệp khác;
- đóng gói VietLicenSure cùng sản phẩm khác;
- bán, cho thuê, thu phí hoặc khai thác thương mại;
- sửa đổi, vá, dịch ngược nhằm tái sử dụng mã hoặc tạo bản phái sinh;
- vượt qua cơ chế xác minh bản chính thức;
- đổi tên, đổi thương hiệu, mạo danh tác giả hoặc tuyên bố sản phẩm thuộc cá nhân/tổ chức khác;
- xóa hoặc thay đổi thông tin tác giả, bản quyền, Build ID, chữ ký, hash hoặc địa chỉ phát hành chính thức.

Khả năng kỹ thuật để sao chép, trích xuất hoặc dịch ngược không làm phát sinh quyền pháp lý tương ứng.

## 5. Lộ trình mở mã nguồn theo từng giai đoạn

Nhằm tăng tính minh bạch và hỗ trợ kiểm tra độc lập, tác giả dự kiến mở dần một số thành phần theo bốn giai đoạn.

### 5.1. Giai đoạn 1 — Kiểm soát chặt

**Thời gian dự kiến:** Từ hiện tại đến hết tháng 11/2026.

- Không công khai toàn bộ mã nguồn.
- Chỉ cấp quyền xem hạn chế khi có yêu cầu và chấp thuận bằng văn bản.
- Ưu tiên ổn định v5.0, bảo vệ chuỗi phát hành và ngăn sao chép trái phép.

### 5.2. Giai đoạn 2 — Mở có chọn lọc module không chứa lõi

**Thời gian dự kiến:** Đến hết tháng 02/2027.

Có thể công bố một số thành phần không chứa lõi, ví dụ:

- report schema;
- offline/reporting policy;
- verifier và công cụ tài liệu;
- một phần test harness hoặc fixture đã làm sạch;
- tài liệu kỹ thuật phù hợp cho việc kiểm tra độc lập.

Việc chuyển giai đoạn chỉ thực hiện khi kiểm thử nội bộ và đánh giá rủi ro đạt yêu cầu.

### 5.3. Giai đoạn 3 — Mở rộng thành phần đã ổn định

**Thời gian dự kiến:** Đến hết tháng 06/2027.

Tác giả sẽ xem xét công bố thêm các thành phần đã ổn định, đã được kiểm tra ở giai đoạn 2 và không làm lộ lõi nhạy cảm hoặc gây rủi ro nghiêm trọng.

Điều kiện gồm kết quả kiểm tra độc lập đạt yêu cầu và không phát hiện hành vi lạm dụng đáng kể.

### 5.4. Giai đoạn 4 — Mở rộng có điều kiện

**Thời gian dự kiến:** Từ tháng 07/2027 trở đi.

Tác giả có thể mở rộng phạm vi công bố, áp dụng giấy phép hạn chế hoặc đặt điều kiện sử dụng riêng. Sau khoảng sáu tháng, chính sách sẽ được đánh giá lại dựa trên:

- tình hình bảo mật;
- mức độ lạm dụng thực tế;
- hiệu quả của hoạt động kiểm tra độc lập;
- nhu cầu chính đáng của cộng đồng;
- khả năng duy trì và bảo vệ quyền lợi của dự án.

### 5.5. Giá trị của các mốc thời gian

Các mốc trên là **khung dự kiến, không phải cam kết cứng**. Tác giả có quyền gia hạn, rút ngắn, thay đổi phạm vi hoặc tạm dừng một giai đoạn nếu xuất hiện:

- rủi ro sao chép hoặc phát hành trái phép;
- lỗ hổng bảo mật nghiêm trọng;
- nguy cơ lộ thông tin nhạy cảm;
- hành vi lạm dụng quyền truy cập;
- yếu tố pháp lý, kỹ thuật hoặc khách quan khác.

Mọi thay đổi giai đoạn chỉ có hiệu lực sau khi được công bố chính thức bằng văn bản trên kênh phát hành và được cập nhật trong tài liệu trạng thái phát hành.

Mã được công bố ở bất kỳ giai đoạn nào vẫn thuộc quyền sở hữu của tác giả. Quyền xem không đồng nghĩa quyền sao chép, sửa đổi, chia sẻ, tạo sản phẩm phái sinh hoặc thương mại hóa, trừ khi giấy phép hoặc văn bản chấp thuận ghi rõ khác đi.

## 6. Quy trình yêu cầu truy cập mã nguồn

Yêu cầu xem mã nguồn để học tập, nghiên cứu, kiểm định, đánh giá bảo mật hoặc đóng góp phải được gửi bằng văn bản tới:

**Email:** `thanhvietit.hopnghia@gmail.com`

Yêu cầu cần nêu rõ:

1. họ tên, tổ chức và thông tin liên hệ;
2. mục đích cụ thể và kết quả dự kiến;
3. thành phần hoặc phạm vi cần xem;
4. thời hạn truy cập mong muốn;
5. danh sách người được phép truy cập;
6. môi trường và biện pháp bảo vệ mã nguồn;
7. nhu cầu sao chép, build, sửa đổi hoặc kiểm thử nếu có;
8. cam kết tuân thủ chính sách và điều kiện bổ sung.

Quyền truy cập chỉ phát sinh sau khi có chấp thuận bằng văn bản. Mỗi chấp thuận:

- chỉ dành cho đúng người hoặc tổ chức được nêu;
- không được chuyển nhượng;
- chỉ có hiệu lực trong mục đích, phạm vi, thời hạn và môi trường được duyệt;
- không mặc nhiên cho phép tải xuống, sao chép, sửa đổi hoặc công bố;
- có thể bị giới hạn, tạm dừng hoặc thu hồi khi phát hiện vi phạm hoặc rủi ro.

## 7. Giới hạn đối với người được cấp quyền truy cập

Trừ khi văn bản chấp thuận cho phép rõ ràng, người được truy cập không được:

- sao chép mã ra ngoài môi trường được cấp;
- chia sẻ tài khoản hoặc cho người chưa được duyệt xem mã;
- công bố, mirror hoặc tải mã lên kho hay dịch vụ khác;
- tạo sản phẩm phái sinh, đóng gói hoặc tích hợp vào sản phẩm/dịch vụ khác;
- bán, cho thuê, thu phí hoặc phục vụ bên thứ ba;
- dùng mã làm dữ liệu huấn luyện hoặc đầu vào cho hệ thống tạo mã chưa được tác giả chấp thuận;
- xóa thông tin tác giả, đổi thương hiệu hoặc mạo danh;
- công bố mã nhạy cảm hoặc lỗ hổng trước khi hoàn tất quy trình tiết lộ có trách nhiệm.

## 8. Đóng góp từ cộng đồng

Cộng đồng có thể đóng góp mà không cần truy cập mã nguồn bằng cách:

- báo lỗi và cung cấp bước tái hiện;
- đề xuất tính năng hoặc cải tiến trải nghiệm;
- đóng góp tài liệu và bản dịch;
- xây dựng test case;
- cung cấp dữ liệu mẫu đã loại bỏ thông tin cá nhân, bí mật và dữ liệu nhạy cảm;
- kiểm tra khả năng tương thích và xác minh bản phát hành chính thức.

Đóng góp ở cấp mã nguồn chỉ được tiếp nhận khi có thỏa thuận bằng văn bản về:

- phạm vi và nhánh làm việc;
- kênh gửi thay đổi;
- yêu cầu kiểm thử và chất lượng;
- cách ghi nhận đóng góp;
- quyền tác giả và quyền sử dụng đóng góp;
- yêu cầu bảo mật và không tiết lộ.

Việc gửi ý tưởng hoặc bản vá không tự động chuyển quyền sở hữu và không cấp quyền đối với phần còn lại của mã nguồn. Tác giả là người duy trì dự án và quyết định nội dung được đưa vào bản phát hành chính thức.

## 9. Báo lỗi, dữ liệu nhạy cảm và tiết lộ bảo mật

GitHub Issues và Discussions có thể được dùng cho báo lỗi, đề xuất và hỏi đáp công khai.

Không đăng công khai:

- product key, token hoặc thông tin xác thực;
- dữ liệu cá nhân hoặc dữ liệu nội bộ của tổ chức;
- mã nguồn được kiểm soát;
- báo cáo nội bộ chứa thông tin nhạy cảm;
- lỗ hổng chưa được khắc phục hoặc chưa phối hợp công bố.

Lỗ hổng bảo mật phải được gửi qua kênh báo cáo bảo mật riêng của repository hoặc email chính thức. Việc tiết lộ phải tuân thủ nguyên tắc phối hợp và có trách nhiệm.

## 10. Tính toàn vẹn của bản phát hành chính thức

Nguồn phát hành chính thức:

- **Repository:** <https://github.com/thanhvietithopnghia-rgb/VietLicenSure>
- **Trang xác minh:** <https://thanhvietithopnghia-rgb.github.io/VietLicenSure/#verify-official-build>

Trước khi sử dụng, người dùng nên đối chiếu:

- phiên bản và Build ID;
- SHA-256 của EXE;
- manifest và checksum của gói;
- thông tin tác giả và repository;
- chữ ký cùng chính sách trust của kênh phát hành.

Không nên sử dụng bản được tải từ nguồn khác hoặc có thông tin không khớp. Cơ chế xác minh giúp phát hiện bản bị thay đổi nhưng không thể ngăn tuyệt đối việc sao chép hoặc dịch ngược trên thiết bị của người dùng.

## 11. Quyền sở hữu và phiên bản trước v4.9

Chính sách này áp dụng cho mã nguồn từ v4.9 trở đi. Các phiên bản cũ tiếp tục chịu sự điều chỉnh của điều khoản đi kèm tại thời điểm phát hành.

Quyền đã được cấp hợp lệ trước đây không bị thu hồi hồi tố. Tuy nhiên, việc một phiên bản từng có thể xem công khai không tự biến phiên bản đó thành mã nguồn mở nếu không có giấy phép mã nguồn mở hợp lệ.

## 12. Miễn trừ bảo đảm và trách nhiệm người dùng

Phần mềm được cung cấp **nguyên trạng (as is)**, không có bảo đảm rõ ràng hay ngụ ý.

Người dùng chịu trách nhiệm:

- sao lưu dữ liệu và trạng thái hệ thống;
- kiểm tra nguồn gốc và tính toàn vẹn của bản tải xuống;
- tuân thủ pháp luật và chính sách của tổ chức;
- xác nhận quyền quản trị và phạm vi được phép trước khi thực hiện thao tác thay đổi hệ thống;
- đánh giá rủi ro sử dụng trong môi trường của mình.

## 13. Sửa đổi và hiệu lực chính sách

Tác giả có thể cập nhật chính sách để phản ánh thay đổi về kỹ thuật, bảo mật, pháp lý, mô hình phát hành hoặc lộ trình mở mã nguồn.

Bản cập nhật chỉ có hiệu lực sau khi được công bố trên kênh chính thức. Sự im lặng, khả năng truy cập kỹ thuật hoặc việc vô tình nhận được một bản sao không được hiểu là đã cấp quyền.

Khi có khác biệt giữa các tài liệu:

1. byte thực, manifest, chữ ký và checksum của gói quyết định danh tính artifact;
2. `RELEASE-STATUS-v5.0.md` quyết định trạng thái phát hành;
3. tài liệu này quyết định chính sách truy cập và sử dụng mã nguồn;
4. văn bản chấp thuận riêng quyết định quyền cụ thể của người được cấp quyền.

## 14. Liên hệ

- **Tác giả/chủ sở hữu:** Thanh Việt
- **Email:** `thanhvietit.hopnghia@gmail.com`
- **Repository:** <https://github.com/thanhvietithopnghia-rgb/VietLicenSure>
- **Trang xác minh:** <https://thanhvietithopnghia-rgb.github.io/VietLicenSure/#verify-official-build>

---

**Tóm tắt pháp lý ngắn:** VietLicenSure là phần mềm miễn phí nhưng không phải phần mềm mã nguồn mở. Mã nguồn được kiểm soát và có thể được mở dần theo từng giai đoạn. Mọi quyền truy cập, sao chép, sửa đổi, công bố, tạo sản phẩm phái sinh hoặc thương mại hóa chỉ phát sinh khi giấy phép hoặc văn bản chấp thuận nêu rõ.

