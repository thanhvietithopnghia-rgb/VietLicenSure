# CHÍNH SÁCH MÃ NGUỒN CÓ KIỂM SOÁT — VIETLICENSURE v5.0

**Cập nhật:** 02/11/2026<br>
**Chủ sở hữu:** Thanh Việt<br>
**Trạng thái:** Chính sách hiện hành, thay thế cách hiểu trước đây về việc không công bố bất kỳ mã nguồn v4.9+ nào.

## 1. Mô hình công bố

VietLicenSure áp dụng mô hình **proprietary partial source / source-available có kiểm soát**. Dự án không được cấp phép theo GPL, MIT, Apache hoặc giấy phép open-source khác.

Quyền xem phần mã được công bố không đồng nghĩa quyền sao chép, sửa đổi, phân phối, mirror, tạo sản phẩm phái sinh, thương mại hóa, đổi thương hiệu hoặc dùng làm dữ liệu huấn luyện. Các quyền đó chỉ phát sinh khi có văn bản chấp thuận riêng của chủ sở hữu.

## 2. Phạm vi được công bố

Giai đoạn công bố chọn lọc bắt đầu ngày 02/11/2026 theo quyết định của chủ sở hữu. Chỉ các tệp nằm trong `PARTIAL-SOURCE-MANIFEST.json` được coi là partial source chính thức:

- report schema và offline/reporting policy;
- schema dữ liệu công khai;
- verifier và công cụ tài liệu không chứa lõi;
- fixture đã làm sạch nếu được bổ sung bằng manifest trong tương lai;
- tài liệu kỹ thuật phục vụ xác minh độc lập.

Mỗi lần bổ sung hoặc loại bỏ tệp phải cập nhật manifest, checksum, đánh giá rủi ro và lịch sử công bố.

## 3. Phạm vi không được công bố

Không công bố:

- UI và business logic đầy đủ;
- detection, classification, remediation và elevated broker;
- plugin/update internals và catalog nội bộ;
- build, signing, packaging và release pipeline;
- test harness/fixture nội bộ chưa làm sạch;
- khóa riêng, credential, dữ liệu thiết bị hoặc evidence nhạy cảm;
- mã hoặc cấu hình được cấp cho reviewer theo NDA.

Các thành phần này được lưu trong repository riêng tư có kiểm soát.

## 4. Quyền sử dụng partial source

Người xem được phép:

- đọc và đánh giá phần mã công bố;
- kiểm hash, manifest và provenance công khai;
- trích dẫn đoạn ngắn cho mục đích báo lỗi hoặc review có trách nhiệm;
- gửi báo lỗi, đề xuất và security report qua kênh chính thức.

Nếu chưa có chấp thuận bằng văn bản, người xem không được:

- sao chép hoặc phân phối lại toàn bộ hay phần đáng kể;
- sửa đổi, build, đóng gói hoặc phát hành biến thể;
- tích hợp vào sản phẩm/dịch vụ khác;
- tạo sản phẩm phái sinh hoặc thương mại hóa;
- dùng mã làm dữ liệu huấn luyện, fine-tuning hoặc benchmark sinh mã;
- xóa ghi nhận tác giả, đổi thương hiệu hoặc tuyên bố quyền sở hữu.

## 5. Bản thực thi và chuỗi phát hành

Bản EXE chính thức tiếp tục được cung cấp theo điều khoản binary riêng. Partial source không phải source-complete build kit và không được dùng để tuyên bố có thể tái tạo toàn bộ EXE.

Danh tính bản phát hành phải được xác minh bằng `RELEASE-MANIFEST.json`, checksum, CMS provenance, Authenticode và release notes. Kênh hiện tại là Official Self-Signed; đây không phải public-CA/EV/Store trust.

## 6. Truy cập mã lõi

Yêu cầu audit, nghiên cứu hoặc review cần mã lõi phải gửi bằng văn bản tới `thanhvietit.hopnghia@gmail.com`. Quyền truy cập chỉ phát sinh sau khi phạm vi, người truy cập, thời hạn, NDA và biện pháp bảo vệ được chấp thuận.

## 7. Tiết lộ bảo mật

Không đăng công khai credential, product key, dữ liệu cá nhân, mã lõi được cấp riêng hoặc lỗ hổng chưa phối hợp. Sử dụng GitHub Security Advisories hoặc email chính thức.

## 8. Thay đổi chính sách

Chủ sở hữu có thể mở rộng, thu hẹp hoặc tạm dừng partial source theo rủi ro bảo mật, pháp lý và lạm dụng thực tế. Mọi thay đổi chỉ có hiệu lực khi được cập nhật bằng văn bản trong repo công khai và manifest tương ứng.

Copyright © 2026 Thanh Việt. All rights reserved.
