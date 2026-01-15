#!/bin/bash
# scripts/view-logs.sh
# DESC: KISA 하드닝 로그 뷰어

set -euo pipefail

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 스크립트 디렉토리
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 로그 디렉토리
LOG_DIR="/var/log/kisa-hardening"

# 사용법
usage() {
    cat << EOF
사용법: $0 [옵션]

KISA 하드닝 로그 뷰어

옵션:
    -h, --help              도움말 표시
    -l, --latest            최신 로그만 표시
    -a, --all               모든 로그 표시
    -f, --file FILE         특정 로그 파일 표시
    -n, --lines NUM         최근 N줄만 표시 (기본: 100)
    -e, --errors            에러만 표시
    -w, --warnings          경고만 표시
    -s, --summary           요약만 표시
    --list                  로그 파일 목록

예시:
    $0                      # 최신 로그의 요약 표시
    $0 -l                   # 최신 로그 전체
    $0 -l -e                # 최신 로그의 에러만
    $0 -n 50                # 최근 50줄
    $0 --list               # 로그 파일 목록

EOF
    exit 0
}

# 로그 파일 목록
list_logs() {
    echo -e "${CYAN}=== KISA 하드닝 로그 파일 ===${NC}"
    echo ""
    
    if [ ! -d "$LOG_DIR" ]; then
        echo -e "${YELLOW}로그 디렉토리가 없습니다: $LOG_DIR${NC}"
        exit 0
    fi
    
    local count=0
    for log_file in "$LOG_DIR"/kisa-hardening-*.log; do
        if [ -f "$log_file" ]; then
            local size=$(du -h "$log_file" | cut -f1)
            local modified=$(stat -c %y "$log_file" | cut -d'.' -f1)
            echo -e "${BLUE}$(basename "$log_file")${NC}"
            echo "  크기: $size | 수정일: $modified"
            count=$((count + 1))
        fi
    done
    
    if [ $count -eq 0 ]; then
        echo -e "${YELLOW}로그 파일이 없습니다${NC}"
    else
        echo ""
        echo "총 $count개 로그 파일"
    fi
}

# 최신 로그 파일 찾기
get_latest_log() {
    if [ ! -d "$LOG_DIR" ]; then
        echo ""
        return 1
    fi
    
    local latest=$(ls -t "$LOG_DIR"/kisa-hardening-*.log 2>/dev/null | head -1)
    echo "$latest"
}

# 로그 포맷팅
format_log_line() {
    local line="$1"
    
    # 색상 적용
    if echo "$line" | grep -q "\[ERROR\]"; then
        echo -e "${RED}$line${NC}"
    elif echo "$line" | grep -q "\[WARNING\]"; then
        echo -e "${YELLOW}$line${NC}"
    elif echo "$line" | grep -q "\[SUCCESS\]"; then
        echo -e "${GREEN}$line${NC}"
    elif echo "$line" | grep -q "\[SECTION\]"; then
        echo -e "${CYAN}$line${NC}"
    else
        echo "$line"
    fi
}

# 로그 표시
show_log() {
    local log_file="$1"
    local filter="${2:-all}"
    local lines="${3:-0}"
    
    if [ ! -f "$log_file" ]; then
        echo -e "${RED}로그 파일을 찾을 수 없습니다: $log_file${NC}"
        exit 1
    fi
    
    echo -e "${CYAN}=== $(basename "$log_file") ===${NC}"
    echo ""
    
    local content=""
    
    # 줄 수 제한
    if [ "$lines" -gt 0 ]; then
        content=$(tail -n "$lines" "$log_file")
    else
        content=$(cat "$log_file")
    fi
    
    # 필터 적용
    case "$filter" in
        errors)
            content=$(echo "$content" | grep "\[ERROR\]")
            ;;
        warnings)
            content=$(echo "$content" | grep "\[WARNING\]")
            ;;
        summary)
            content=$(echo "$content" | grep -E "\[SECTION\]|\[SUMMARY\]")
            ;;
        all)
            ;;
    esac
    
    # 포맷팅 및 출력
    while IFS= read -r line; do
        format_log_line "$line"
    done <<< "$content"
}

# 요약 표시
show_summary() {
    local log_file="$1"
    
    if [ ! -f "$log_file" ]; then
        echo -e "${RED}로그 파일을 찾을 수 없습니다: $log_file${NC}"
        exit 1
    fi
    
    echo -e "${CYAN}=== 실행 요약: $(basename "$log_file") ===${NC}"
    echo ""
    
    # 섹션 추출
    local sections=$(grep "\[SECTION\]" "$log_file" | sed 's/.*\[SECTION\] //' || echo "")
    if [ -n "$sections" ]; then
        echo -e "${BLUE}실행된 섹션:${NC}"
        echo "$sections" | while read -r section; do
            echo "  • $section"
        done
        echo ""
    fi
    
    # 성공/실패 카운트
    local success_count=$(grep -c "\[SUCCESS\]" "$log_file" 2>/dev/null || echo "0")
    local error_count=$(grep -c "\[ERROR\]" "$log_file" 2>/dev/null || echo "0")
    local warning_count=$(grep -c "\[WARNING\]" "$log_file" 2>/dev/null || echo "0")
    
    echo -e "${BLUE}실행 결과:${NC}"
    echo -e "  ${GREEN}✓ 성공: $success_count${NC}"
    echo -e "  ${RED}✗ 에러: $error_count${NC}"
    echo -e "  ${YELLOW}⚠ 경고: $warning_count${NC}"
    echo ""
    
    # 에러가 있으면 표시
    if [ "$error_count" -gt 0 ]; then
        echo -e "${RED}에러 메시지:${NC}"
        grep "\[ERROR\]" "$log_file" | sed 's/.*\[ERROR\] //' | while read -r error; do
            echo -e "  ${RED}✗ $error${NC}"
        done
        echo ""
    fi
    
    # 최근 5개 경고 표시
    if [ "$warning_count" -gt 0 ]; then
        echo -e "${YELLOW}최근 경고 (최대 5개):${NC}"
        grep "\[WARNING\]" "$log_file" | tail -5 | sed 's/.*\[WARNING\] //' | while read -r warning; do
            echo -e "  ${YELLOW}⚠ $warning${NC}"
        done
        echo ""
    fi
    
    # 로그 파일 정보
    local log_size=$(du -h "$log_file" | cut -f1)
    local log_lines=$(wc -l < "$log_file")
    echo -e "${BLUE}로그 정보:${NC}"
    echo "  파일: $(basename "$log_file")"
    echo "  크기: $log_size ($log_lines 줄)"
}

# 메인 함수
main() {
    local mode="summary"
    local filter="all"
    local lines=0
    local log_file=""
    
    # 옵션 파싱
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            -l|--latest)
                mode="latest"
                shift
                ;;
            -a|--all)
                mode="all"
                shift
                ;;
            -f|--file)
                log_file="$2"
                mode="file"
                shift 2
                ;;
            -n|--lines)
                lines="$2"
                shift 2
                ;;
            -e|--errors)
                filter="errors"
                shift
                ;;
            -w|--warnings)
                filter="warnings"
                shift
                ;;
            -s|--summary)
                mode="summary"
                shift
                ;;
            --list)
                list_logs
                exit 0
                ;;
            *)
                echo "알 수 없는 옵션: $1"
                usage
                ;;
        esac
    done
    
    # 로그 파일 결정
    if [ -z "$log_file" ]; then
        log_file=$(get_latest_log)
        if [ -z "$log_file" ]; then
            echo -e "${YELLOW}로그 파일이 없습니다${NC}"
            echo "먼저 KISA 하드닝 스크립트를 실행하세요:"
            echo "  sudo ./kisa-hardening.sh"
            exit 0
        fi
    fi
    
    # 모드별 처리
    case "$mode" in
        summary)
            show_summary "$log_file"
            ;;
        latest|file)
            show_log "$log_file" "$filter" "$lines"
            ;;
        all)
            for log in "$LOG_DIR"/kisa-hardening-*.log; do
                if [ -f "$log" ]; then
                    show_summary "$log"
                    echo ""
                fi
            done
            ;;
    esac
}

# 스크립트 실행
main "$@"