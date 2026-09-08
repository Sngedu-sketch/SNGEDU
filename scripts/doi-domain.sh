#!/usr/bin/env bash
# ============================================================
# ĐỔI DOMAIN CHO TOÀN BỘ SITE — CHỈ CẦN CHẠY 1 LỆNH
#
# Vì đây là site tĩnh (không có build tool), các thẻ SEO như
# canonical, og:url, sitemap.xml, robots.txt... phải là chữ THẬT
# nằm trong HTML để Google đọc được — không thể thay bằng biến
# JavaScript. Script này giúp đổi domain ở TẤT CẢ các file đó
# chỉ bằng 1 lệnh, thay vì phải sửa tay từng dòng.
#
# CÁCH DÙNG:
#   cd SNGEDU-full
#   bash scripts/doi-domain.sh https://sngedu.site https://tenmien-moi.com
#
# LƯU Ý SAU KHI ĐỔI:
#   1. Domain Supabase KHÔNG nằm trong script này — sửa ở
#      assets/js/supabase-config.js (đã tách riêng sẵn).
#   2. Đổi secret SITE_URL trong Supabase Project Settings >
#      Edge Functions > Secrets (dùng cho email + link thanh toán SePay).
#   3. Cập nhật lại Return URL trên dashboard cổng thanh toán SePay
#      nếu domain đổi (thanh-toan-thanh-cong/loi/huy.html).
#   4. Bump CACHE_VERSION trong sw.js để buộc trình duyệt tải lại cache mới.
# ============================================================

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Cách dùng: bash scripts/doi-domain.sh <domain-cu> <domain-moi>"
  echo "Vi du:     bash scripts/doi-domain.sh https://sngedu.site https://tenmien-moi.com"
  exit 1
fi

OLD_URL="$1"
NEW_URL="$2"

# Bỏ dấu / ở cuối nếu người dùng lỡ gõ thừa, để tránh double-slash khi ghép chuỗi.
OLD_URL="${OLD_URL%/}"
NEW_URL="${NEW_URL%/}"

# Domain trần (không có https://) — dùng cho các chỗ chỉ ghi tên miền, vd trong footer.
OLD_HOST="${OLD_URL#http://}"
OLD_HOST="${OLD_HOST#https://}"
NEW_HOST="${NEW_URL#http://}"
NEW_HOST="${NEW_HOST#https://}"

cd "$(dirname "$0")/.."   # đứng ở thư mục gốc SNGEDU-full dù chạy script từ đâu

FILES=$(grep -rlE "$(printf '%s' "$OLD_URL" | sed 's/[.[\*^$/]/\\&/g')|$(printf '%s' "$OLD_HOST" | sed 's/[.[\*^$/]/\\&/g')" \
  --include="*.html" --include="*.xml" --include="*.txt" --include="*.json" . || true)

if [ -z "$FILES" ]; then
  echo "Không tìm thấy chỗ nào chứa domain cũ ($OLD_URL). Không có gì để đổi."
  exit 0
fi

echo "Sẽ đổi domain trong các file sau:"
echo "$FILES" | sed 's/^/  - /'
echo ""

for f in $FILES; do
  # Đổi dạng đầy đủ có schema trước (https://sngedu.site -> https://tenmien-moi.com)
  sed -i "s#${OLD_URL}#${NEW_URL}#g" "$f"
  # Rồi đổi các chỗ chỉ ghi domain trần còn sót (vd trong footer "· sngedu.site")
  sed -i "s#${OLD_HOST}#${NEW_HOST}#g" "$f"
done

echo ""
echo "✅ Xong. Đã đổi $(echo "$FILES" | wc -l | tr -d ' ') file."
echo "⚠️  Đừng quên 4 việc thủ công liệt kê ở đầu file script này (Supabase, SITE_URL secret, SePay, sw.js)."
