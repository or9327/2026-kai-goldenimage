#!/bin/bash
# modules/03-service-management/U-45-mail-service-check.sh
# DESC: 메일 서비스 점검 (Sendmail/Postfix/Exim)

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-45"
MODULE_NAME="메일 서비스 점검"
MODULE_CATEGORY="서비스 관리"
MODULE_SEVERITY="중"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# 메일 서비스 목록
MAIL_SERVICES=(
    "sendmail"
    "postfix"
    "exim4"
)

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    local mail_service_found=false
    local active_mail_service=""
    
    # Sendmail 확인
    if systemctl list-units --all --type=service 2>/dev/null | grep -q "sendmail"; then
        mail_service_found=true
        
        if systemctl is-active --quiet sendmail 2>/dev/null; then
            log_info "Sendmail: 활성화됨"
            active_mail_service="sendmail"
            
            # 버전 확인
            if command -v sendmail &>/dev/null; then
                local version=$(sendmail -d0 -bt < /dev/null 2>&1 | head -1)
                log_info "  버전: $version"
            fi
        else
            log_info "Sendmail: 설치되었으나 비활성화됨"
        fi
    fi
    
    # Postfix 확인
    if systemctl list-units --all --type=service 2>/dev/null | grep -q "postfix\|master"; then
        mail_service_found=true
        
        if systemctl is-active --quiet postfix 2>/dev/null || pgrep -x master &>/dev/null; then
            log_info "Postfix: 활성화됨"
            active_mail_service="postfix"
            
            # 버전 확인
            if command -v postconf &>/dev/null; then
                local version=$(postconf mail_version 2>/dev/null | cut -d= -f2)
                log_info "  버전:$version"
            fi
        else
            log_info "Postfix: 설치되었으나 비활성화됨"
        fi
    fi
    
    # Exim 확인
    if systemctl list-units --all --type=service 2>/dev/null | grep -q "exim"; then
        mail_service_found=true
        
        if systemctl is-active --quiet exim4 2>/dev/null || pgrep -x exim4 &>/dev/null; then
            log_info "Exim: 활성화됨"
            active_mail_service="exim4"
            
            # 버전 확인
            if command -v exim4 &>/dev/null; then
                local version=$(exim4 -bV 2>&1 | head -1)
                log_info "  버전: $version"
            fi
        else
            log_info "Exim: 설치되었으나 비활성화됨"
        fi
    fi
    
    MAIL_SERVICE_FOUND="$mail_service_found"
    ACTIVE_MAIL_SERVICE="$active_mail_service"
    
    if [ "$mail_service_found" = false ]; then
        log_success "✓ 메일 서비스 미설치"
        return 0
    elif [ -z "$active_mail_service" ]; then
        log_success "✓ 메일 서비스 비활성화됨"
        return 0
    else
        log_warning "메일 서비스 활성화됨"
        return 1
    fi
}

# 2. 백업 수행
perform_backup() {
    log_info "백업 단계 생략 (검증 전용 모듈)"
}

# 3. 설정 적용
apply_hardening() {
    log_info "메일 서비스 분석 중..."
    
    if [ -z "$ACTIVE_MAIL_SERVICE" ]; then
        log_info "활성화된 메일 서비스 없음"
        return 0
    fi
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] 메일 서비스 비활성화 시뮬레이션"
        return 0
    fi
    
    # 자동 비활성화 옵션
    if [ "${AUTO_DISABLE_MAIL:-false}" = true ]; then
        log_info "메일 서비스 비활성화 중..."
        
        case "$ACTIVE_MAIL_SERVICE" in
            sendmail)
                systemctl stop sendmail 2>/dev/null
                systemctl disable sendmail 2>/dev/null
                log_success "✓ Sendmail 비활성화"
                ;;
            postfix)
                systemctl stop postfix 2>/dev/null
                systemctl disable postfix 2>/dev/null
                log_success "✓ Postfix 비활성화"
                ;;
            exim4)
                systemctl stop exim4 2>/dev/null
                systemctl disable exim4 2>/dev/null
                log_success "✓ Exim 비활성화"
                ;;
        esac
    else
        log_warning ""
        log_warning "========================================="
        log_warning "메일 서비스가 활성화되어 있습니다"
        log_warning "========================================="
        log_warning ""
        log_warning "현재 메일 서비스: $ACTIVE_MAIL_SERVICE"
        log_warning ""
        log_warning "이 서버를 메일 서버로 사용하지 않는 경우 비활성화를 권장합니다."
        log_warning ""
        log_warning "비활성화 방법:"
        log_warning "  1. 수동 비활성화:"
        log_warning "     sudo systemctl stop $ACTIVE_MAIL_SERVICE"
        log_warning "     sudo systemctl disable $ACTIVE_MAIL_SERVICE"
        log_warning ""
        log_warning "  2. 자동 비활성화 (주의!):"
        log_warning "     sudo AUTO_DISABLE_MAIL=true ./kisa-hardening.sh -m U-45"
        log_warning ""
        log_warning "메일 서버로 사용하는 경우:"
        log_warning "  - 보안 패치를 최신 상태로 유지하세요"
        log_warning "  - U-46: 스팸 방지 설정"
        log_warning "  - U-47: 릴레이 제한 설정"
        log_warning ""
        
        case "$ACTIVE_MAIL_SERVICE" in
            sendmail)
                log_warning "Sendmail 보안:"
                log_warning "  - 홈페이지: http://www.sendmail.org/"
                log_warning "  - 최신 버전 확인 및 패치 적용"
                ;;
            postfix)
                log_warning "Postfix 보안:"
                log_warning "  - 홈페이지: https://www.postfix.org/"
                log_warning "  - 패키지 관리자로 업데이트: sudo apt update && sudo apt upgrade postfix"
                ;;
            exim4)
                log_warning "Exim 보안:"
                log_warning "  - 홈페이지: https://www.exim.org/"
                log_warning "  - 패키지 관리자로 업데이트: sudo apt update && sudo apt upgrade exim4"
                ;;
        esac
        
        log_warning ""
    fi
    
    log_success "메일 서비스 분석 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 생략 (검증 전용 모듈)"
    return 0
}

# 메인 실행 흐름
main() {
    # 현재 상태 확인
    if check_current_status; then
        log_info "메일 서비스가 없거나 비활성화되어 있습니다"
        exit 0
    fi
    
    # 백업 생략 (검증 전용)
    
    # 분석 수행
    if ! apply_hardening; then
        log_error "분석 실패"
        exit 1
    fi
    
    log_success "[$MODULE_ID] $MODULE_NAME - 완료"
    
    # 추가 안내
    log_info ""
    log_info "=== 메일 서비스 점검 완료 ==="
    log_info "이 모듈은 메일 서비스를 검증만 합니다."
    log_info ""
    log_info "메일 서버 사용 여부 판단:"
    log_info "  - 메일 서버: 보안 패치 필수, U-46/U-47 적용"
    log_info "  - 일반 서버: 비활성화 권장"
    log_info "  - 웹 서버: 비활성화 권장"
    log_info ""
    log_info "확인 명령어:"
    log_info "  # 메일 서비스 상태"
    log_info "  systemctl status sendmail postfix exim4"
    log_info ""
    log_info "  # 메일 큐 확인"
    log_info "  mailq"
    log_info ""
}

# 스크립트 실행
main "$@"
