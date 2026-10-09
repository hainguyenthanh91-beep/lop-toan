# Lớp Toán – app điểm danh & chấm điểm

App Android chạy **offline**, dữ liệu lưu ngay trong điện thoại (SQLite). Không cần mạng, không cần CH Play.

## Các mục trong app

| Tab | Chức năng |
|---|---|
| **Hôm nay** | Lịch dạy hôm nay (theo thứ), nút điểm danh nhanh, số em vắng, số bài chưa chấm xong, danh sách em **cần chú ý** (vắng 2–3 buổi liên tiếp, TB 3 bài gần nhất < 5) |
| **Lớp học** | 8–9 lớp, mỗi lớp có 4 tab: Học sinh · Điểm danh · Bài tập · Thống kê (xếp loại, biểu đồ TB lớp, bảng xếp hạng). Nhập danh sách HS bằng cách dán từ Excel/Zalo. Xuất bảng điểm ra Excel (CSV) |
| **Học sinh** | Tìm kiếm không dấu, lọc theo lớp, sắp theo điểm / chuyên cần. Mỗi em có **trang riêng**: ĐTB có hệ số, xếp hạng lớp, % chuyên cần, % nộp bài, **biểu đồ điểm** (so với TB lớp), **biểu đồ TB theo tháng**, lịch sử vắng, bảng điểm + nhận xét, học phí, nút gọi / Zalo / SMS phụ huynh |
| **Phiếu báo cáo** | Từ trang học sinh → tạo **ảnh phiếu báo kết quả** (tháng này / tháng trước / cả khóa) kèm nhận xét → gửi thẳng qua Zalo |
| **Học phí** | Chọn tháng, tick đã đóng, tổng đã thu / chưa thu, nút nhắn nhắc học phí |
| **Cài đặt** | Tên giáo viên, tên trung tâm, **sao lưu / khôi phục** (file .json), tạo dữ liệu mẫu để xem thử |

Điểm danh: mặc định cả lớp **có mặt**, chạm vào em nào thì chuyển thành **vắng**, nhấn giữ để chọn *đi muộn / vắng có phép* và ghi chú.

Chấm điểm: nhập điểm cả lớp trên một màn hình, bấm "Tiếp" trên bàn phím là nhảy xuống em sau; có nút *chưa nộp* và *nhận xét* cho từng em. Hỗ trợ thang điểm khác 10 (tự quy về hệ 10 khi tính TB) và hệ số ×1 ×2 ×3.

---

## Cách lấy file APK (không cần cài gì trên máy tính)

GitHub sẽ build APK miễn phí cho bạn.

1. Tạo tài khoản tại **github.com** (nếu chưa có).
2. Bấm **New repository** → đặt tên `lop-toan` → chọn **Public** (để điện thoại tải APK không cần đăng nhập; dữ liệu học sinh **không** nằm trên GitHub, chỉ có mã nguồn) → **Create repository**.
3. Trong repo mới, bấm **uploading an existing file** → giải nén file zip, kéo **toàn bộ nội dung** bên trong thư mục `lop_toan` (gồm cả thư mục `.github`) vào trang → **Commit changes**.
   > Nếu thư mục `.github` không lên: bấm **Add file → Create new file**, gõ tên `.github/workflows/build-apk.yml`, dán nội dung file đó vào, rồi Commit.
4. Mở tab **Actions** → đợi lần build có dấu ✅ xanh (khoảng 8–12 phút).
5. Trên điện thoại, vào trang repo → mục **Releases** (cột bên phải) → tải `LopToan-vN.apk` → mở file → cho phép *Cài ứng dụng không rõ nguồn gốc* → Cài đặt.

Nếu build báo ❌ đỏ: bấm vào lần build đó → bước bị đỏ → copy đoạn lỗi gửi cho Claude để sửa.

### Cập nhật phiên bản mới

Sửa code → upload lại các file đã sửa → GitHub tự build bản mới (vN+1). Cài đè lên bản cũ là được, **dữ liệu vẫn giữ nguyên** (app được ký bằng khóa cố định trong thư mục `keys/` — đừng xóa thư mục này).

### Tự build trên máy tính (tùy chọn)

Nếu máy đã có Flutter 3.29+ và Android SDK:

```bash
flutter create --platforms=android --org vn.thayhai --project-name lop_toan .
python3 tools/patch_android.py
flutter build apk --release
```

File ra ở `build/app/outputs/flutter-apk/app-release.apk`.

---

## Lưu ý quan trọng về dữ liệu

Dữ liệu chỉ nằm trong điện thoại. **Gỡ app = mất dữ liệu.** Hãy vào *Cài đặt → Sao lưu ngay* mỗi tuần và gửi file lên Zalo "Cloud của tôi" hoặc Google Drive. Khi đổi máy: cài app → *Khôi phục từ file sao lưu*.

## Cấu trúc mã nguồn

```
lib/
  main.dart            giao diện chính, 5 tab
  db.dart              cơ sở dữ liệu SQLite + mọi truy vấn
  utils.dart           màu sắc, định dạng ngày/điểm/tiền, xử lý tên tiếng Việt
  widgets.dart         các thành phần giao diện dùng chung
  screens/
    home.dart          tab Hôm nay
    classes.dart       danh sách lớp + form thêm/sửa lớp
    class_detail.dart  chi tiết lớp (HS, điểm danh, bài tập, thống kê)
    attendance.dart    màn hình điểm danh
    grading.dart       tạo bài tập + nhập điểm cả lớp
    student.dart       trang riêng từng học sinh + biểu đồ
    report_card.dart   phiếu báo cáo xuất ảnh
    students_tab.dart  tab Học sinh (tìm kiếm)
    student_edit.dart  form thêm/sửa học sinh
    fees.dart          tab Học phí
    settings.dart      tab Cài đặt, sao lưu
tools/patch_android.py  chỉnh khung Android (tên app, icon, khóa ký)
.github/workflows/      cấu hình GitHub tự build APK
```
