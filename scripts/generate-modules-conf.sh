#!/bin/bash
# scripts/generate-modules-conf.sh
# CSV 파일로부터 modules.conf 생성

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CSV_FILE="${ROOT_DIR}/kisa-items.csv"
OUTPUT_FILE="${ROOT_DIR}/config/modules.conf"

if [ ! -f "$CSV_FILE" ]; then
    echo "ERROR: CSV 파일을 찾을 수 없습니다: $CSV_FILE"
    exit 1
fi

echo "# config/modules.conf" > "$OUTPUT_FILE"
echo "# 모듈 활성화/비활성화 설정" >> "$OUTPUT_FILE"
echo "# 형식: MODULE_ID=enabled|disabled" >> "$OUTPUT_FILE"
echo "# 자동 생성: $(date '+%Y-%m-%d %H:%M:%S')" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

current_category=""

# CSV 파일 읽기 (헤더 제외)
tail -n +2 "$CSV_FILE" | while IFS=',' read -r category item severity code cat_code; do
    # 카테고리가 변경되면 섹션 헤더 추가
    if [ "$category" != "$current_category" ]; then
        echo "" >> "$OUTPUT_FILE"
        echo "# $category" >> "$OUTPUT_FILE"
        current_category="$category"
    fi
    
    # 모듈 설정 추가
    # U-01만 구현되었으므로 U-01만 enabled, 나머지는 disabled
    if [ "$code" = "U-01" ]; then
        echo "$code=enabled  # $item (중요도: $severity)" >> "$OUTPUT_FILE"
    else
        echo "$code=disabled # $item (중요도: $severity)" >> "$OUTPUT_FILE"
    fi
done

echo "" >> "$OUTPUT_FILE"
echo "# 생성 완료: 총 67개 항목" >> "$OUTPUT_FILE"

echo "✓ modules.conf 파일 생성 완료: $OUTPUT_FILE"
echo ""
echo "현재 활성화된 모듈:"
grep "=enabled" "$OUTPUT_FILE" | wc -l
echo ""
echo "현재 비활성화된 모듈:"
grep "=disabled" "$OUTPUT_FILE" | wc -l