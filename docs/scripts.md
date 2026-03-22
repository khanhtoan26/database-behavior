Để biết mình nói đúng hay không, bạn không cần tin vào lý thuyết, hãy tin vào con số thực tế trên máy của bạn.
Cách kiểm chứng dễ nhất là dùng Hint để "ép" Database làm ngược lại những gì nó muốn. Bạn hãy làm thí nghiệm này trên một bảng lớn (> 1 triệu dòng):
1. Thí nghiệm "Ép xác" (Index vs Full Scan)
Giả sử bạn có cột Status với Selectivity tệ (chiếm 80% bảng).

* Bước 1: Chạy bình thường (Database sẽ chọn Full Scan). Ghi lại thời gian (ví dụ: 1s).
* Bước 2: Dùng Hint để ép nó dùng Index (thứ mà bạn nghĩ là tốt).
* Trong SQL Server: SELECT * FROM Table WITH (INDEX(Index_Status)) WHERE Status = 'Active'
   * Trong MySQL: SELECT * FROM Table USE INDEX (Index_Status) WHERE Status = 'Active'
   * Trong Oracle: SELECT /*+ INDEX(Table Index_Status) */ * FROM Table WHERE Status = 'Active'
* Kết quả: Bạn sẽ thấy thời gian chạy vọt lên 5s, 10s hoặc hơn. Lúc này bạn sẽ tin tại sao Selectivity tệ thì Index là thảm họa. [1, 2]

2. Kiểm chứng bằng "Giá đơn vị" (Execution Plan)
Khi bạn bật EXPLAIN (hoặc Display Estimated Execution Plan), hãy nhìn vào cột Cost.

* Database Engine thực chất là một "cỗ máy tính toán chi phí".
* Nó tính: Cost = (Số lần đọc đĩa) * (Giá mỗi lần đọc).
* Nếu bạn thấy Cost của Index Scan cao hơn Cost của Full Table Scan, đó là bằng chứng toán học cho việc tại sao nó không dùng Index. [3, 4]

3. Cách nhớ cực nhanh (Mẹo thực tế)
Thay vì nhớ mớ lý thuyết, hãy nhớ hình ảnh này:

* Cardinality: Là "Số lượng món trong thực đơn".
* Selectivity: Là "Số người thực tế gọi món đó".
* The Tipping Point: Nếu 100 người vào quán mà 90 người gọi Phở, đầu bếp sẽ nấu một nồi to (Full Scan). Nếu chỉ có 1 người gọi, họ mới nấu riêng một bát (Index Scan). [5]

Lý thuyết có thể sai, nhưng thời gian thực thi (Execution Time) và I/O không bao giờ nói dối.
Bạn có muốn mình đưa ra đoạn code SQL cụ thể để bạn tạo 1 triệu dòng ảo và tự tay kiểm chứng cái "điểm lật" này ngay trên máy không?
Đã gửi
Viết cho
