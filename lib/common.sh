#!/bin/bash
# lib/common.sh
# 공통 함수 라이브러리

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 헤더 출력
print_header() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║        KISA 보안 가이드 자동화 스크립트 (Ubuntu 24.04)        ║"
    echo "║                       67개 항목 점검                            ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "실행 시간: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "실행 사용자: $(whoami)"
    echo "호스트명: $(hostname)"
    echo ""
}

# 요약 출력
print_summary() {
    local duration=$1
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}✓ KISA 보안 가이드 적용 완료${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # 실행 결과 요약
    local total_modules=$((MODULE_SUCCESS_COUNT + MODULE_FAIL_COUNT + MODULE_SKIP_COUNT))
    echo -e "${BLUE} 실행 결과:${NC}"
    echo -e "  ${GREEN}✓ 성공:${NC} ${MODULE_SUCCESS_COUNT:-0}"
    if [ "${MODULE_FAIL_COUNT:-0}" -gt 0 ]; then
        echo -e "  ${RED}✗ 실패:${NC} ${MODULE_FAIL_COUNT:-0}"
    fi
    if [ "${MODULE_SKIP_COUNT:-0}" -gt 0 ]; then
        echo -e "  ${YELLOW}⊘ 건너뜀:${NC} ${MODULE_SKIP_COUNT:-0}"
    fi
    echo -e "  ${BLUE}⏱ 실행 시간:${NC} ${duration}초"
    echo ""
    
    # 파일 위치
    echo -e "${BLUE} 생성된 파일:${NC}"
    if [ -d "$BACKUP_DIR" ] && [ "$(ls -A $BACKUP_DIR 2>/dev/null)" ]; then
        echo -e "  ${CYAN}백업:${NC} $BACKUP_DIR"
    fi
    echo -e "  ${CYAN}로그:${NC} $LOG_FILE"
    echo ""
    
    # 추가 안내
    if [ "${MODULE_FAIL_COUNT:-0}" -gt 0 ]; then
        echo -e "${YELLOW}⚠ 실패한 모듈이 있습니다. 로그를 확인하세요:${NC}"
        echo "  ./scripts/view-logs.sh -e"
        echo ""
    fi
    
    echo -e "${BLUE} 도움말:${NC}"
    echo "  로그 확인: ./scripts/view-logs.sh"
    echo "  진행률 확인: ./scripts/check-progress.sh"
    echo ""
}

# Ubuntu 버전 확인
check_ubuntu_version() {
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        if [[ "$ID" == "ubuntu" && "$VERSION_ID" == "24.04" ]]; then
            return 0
        fi
    fi
    return 1
}

# 필수 명령어 확인
check_required_commands() {
    local required_commands=("sed" "awk" "grep" "systemctl" "dpkg")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        log_error "필수 명령어를 찾을 수 없습니다: ${missing_commands[*]}"
        exit 1
    fi
}

# 디스크 공간 확인
check_disk_space() {
    local required_space_mb=500
    local available_space=$(df -m / | awk 'NR==2 {print $4}')
    
    if [ "$available_space" -lt "$required_space_mb" ]; then
        log_error "디스크 공간 부족: ${available_space}MB (최소 ${required_space_mb}MB 필요)"
        exit 1
    fi
}

# 사용자 확인
confirm_action() {
    local response
    read -p "계속하시겠습니까? [y/N]: " response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 카테고리 제목 가져오기
get_category_title() {
    local category=$1
    case "$category" in
        "01-account-management")
            echo "계정 관리"
            ;;
        "02-file-directory")
            echo "파일 및 디렉토리 관리"
            ;;
        "03-service-management")
            echo "서비스 관리"
            ;;
        "04-patch-management")
            echo "패치 관리"
            ;;
        "05-log-management")
            echo "로그 관리"
            ;;
        *)
            echo "알 수 없음"
            ;;
    esac
}

# 모듈 설명 가져오기
get_module_description() {
    local module_path=$1
    # 모듈 파일 첫 줄에서 설명 추출
    grep -m 1 "^# DESC:" "$module_path" | sed 's/# DESC: //'
}

# 모듈 활성화 확인
is_module_enabled() {
    local module_name=$1
    
    # modules.conf에서 확인
    if [ -f "${SCRIPT_DIR}/config/modules.conf" ]; then
        if grep -q "^${module_name}=disabled" "${SCRIPT_DIR}/config/modules.conf"; then
            return 1
        fi
    fi
    
    return 0
}

# 모듈 실행 결과 기록
record_module_result() {
    local module=$1
    local status=$2
    local duration=$3
    local exit_code=${4:-0}
    
    # 결과 카운팅
    case "$status" in
        SUCCESS)
            MODULE_SUCCESS_COUNT=$((MODULE_SUCCESS_COUNT + 1))
            ;;
        FAILED)
            MODULE_FAIL_COUNT=$((MODULE_FAIL_COUNT + 1))
            ;;
        SKIP)
            MODULE_SKIP_COUNT=$((MODULE_SKIP_COUNT + 1))
            ;;
    esac
    
    # JSON 형식으로 기록
    echo "{\"module\":\"$module\",\"status\":\"$status\",\"duration\":$duration,\"exit_code\":$exit_code,\"timestamp\":\"$(date -Iseconds)\"}" >> "${LOG_BASE_DIR}/results.jsonl"
}