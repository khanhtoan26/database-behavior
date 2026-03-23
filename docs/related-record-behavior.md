# Related Prompt

... (init context)

Giả sử có một cột status chỉ chứa 2 giá trị là active và deactive (có đánh index cột này) thì các record có giá trị là active (hoặc ngược lại) có xu hướng được nằm cùng page hay không.

# Answer

Câu hỏi rất hay và đây là một misconception khá phổ biến. Câu trả lời ngắn: không, và đây là lý do tại sao.

Secondary Index trong InnoDB hoạt động như thế nào
Cấu trúc thực tế
Secondary index trên cột status không lưu data rows — nó lưu một B+Tree riêng biệt với structure:
Secondary Index B+Tree (status):
Leaf nodes chứa: [status_value | primary_key]

Ví dụ:

┌─────────────────────────────────┐
│ "active"  | PK=1                │
│ "active"  | PK=5                │
│ "active"  | PK=9                │  ← chỉ là pointer
│ "deactive"| PK=2                │
│ "deactive"| PK=7                │
└─────────────────────────────────┘

Để lấy actual row data, InnoDB phải quay lại clustered index (double lookup).

Các records "active" có nằm cùng page không?
Không. Vì:

Data pages được tổ chức theo primary key order, không phải theo status
Record PK=1 (active) và PK=2 (deactive) gần như chắc chắn nằm cùng một data page
Record PK=1 (active) và PK=5 (active) có thể nằm ở các pages hoàn toàn khác nhau

Data pages (tổ chức theo PK):

Page 1: [PK=1, active] [PK=2, deactive] [PK=3, active] [PK=4, deactive]
Page 2: [PK=5, active] [PK=6, deactive] [PK=7, active] [PK=8, deactive]
Page 3: [PK=9, active] ...
         ↑ active và deactive xen kẽ nhau hoàn toàn

Vậy index trên status có thực sự giúp ích không?
Đây là phần thú vị. Index trên low-cardinality column như status (chỉ 2 giá trị) thường bị MySQL bỏ qua vì:
Giả sử 1 triệu rows, 500k active / 500k deactive
→ selectivity = 1/2 = 50%
→ InnoDB sẽ phán đoán: đọc sequential toàn bộ table còn nhanh hơn
   nhảy qua 500k scattered pages theo secondary index
MySQL query optimizer sẽ thường chọn full table scan thay vì dùng index này, trừ khi tỉ lệ phân bố rất lệch (ví dụ 99% deactive, 1% active — thì query WHERE status = 'active' mới có lợi).

Khi nào data thực sự "cùng page" theo một điều kiện?
Chỉ khi điều kiện đó aligned với primary key order:
sql-- Ví dụ: lưu created_at hoặc user_id làm PK prefix
-- Thì WHERE created_at BETWEEN ... sẽ tận dụng locality tốt

-- Hoặc dùng partitioning theo status
-- → mỗi partition là một không gian riêng, data thực sự tách biệt

Tóm lại
Câu hỏiTrả lờiActive records có nằm cùng page?❌ Không — pages tổ chức theo PKIndex trên status có hiệu quả?⚠️ Thường không — low cardinalityKhi nào index low-cardinality có lợi?Khi distribution rất lệch (~1-5%)Cách để "group" data theo status?Partitioning hoặc thiết kế PK có prefix
