#!/bin/bash
# modules/01-account-management/U-01-root-remote-restriction.sh
# DESC: Root 계정 원격 접속 제한

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-01"
MODULE_NAME="Root 계정 원격 접속 제한"
MODULE_CATEGORY="계정 관리"
MODULE_SEVERITY="상"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    # Telnet 서비스 확인
    if systemctl list-unit-files | grep -q telnet 2>/dev/null; then
        log_warning "Telnet 서비스 발견"
        TELNET_FOUND=true
    else
        log_success "Telnet 서비스 없음"
        TELNET_FOUND=false
    fi
    
    # SSH PermitRootLogin 확인
    local current_setting=$(sshd -T 2>/dev/null | grep "^permitrootlogin" | awk '{print $2}')
    log_info "현재 PermitRootLogin 설정: $current_setting"
    
    if [ "$current_setting" = "no" ]; then
        log_success "이미 올바르게 설정됨"
        return 0
    else
        log_warning "설정 변경 필요"
        return 1
    fi
}

# 2. 백업 수행
perform_backup() {
    log_info "설정 파일 백업 중..."
    
    backup_file "/etc/ssh/sshd_config" "$MODULE_ID"
    
    if [ -f /etc/securetty ]; then
        backup_file "/etc/securetty" "$MODULE_ID"
    fi
    
    if [ -f /etc/pam.d/login ]; then
        backup_file "/etc/pam.d/login" "$MODULE_ID"
    fi
}

# 3. 설정 적용
apply_hardening() {
    log_info "보안 설정 적용 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] Telnet 제거 시뮬레이션"
        log_info "[DRY RUN] SSH 설정 변경 시뮬레이션"
        return 0
    fi
    
    # Telnet 제거
    if [ "$TELNET_FOUND" = true ]; then
        log_info "Telnet 서비스 제거 중..."
        systemctl stop telnetd 2>/dev/null || true
        systemctl disable telnetd 2>/dev/null || true
        apt-get remove -y telnetd xinetd 2>/dev/null || true
    fi
    
    # /etc/securetty 처리
    if [ -f /etc/securetty ]; then
        log_info "/etc/securetty pts/ 주석 처리 중..."
        sed -i 's/^pts\//#pts\//' /etc/securetty
    fi
    
    # PAM 설정
    if [ -f /etc/pam.d/login ]; then
        if ! grep -q "pam_securetty.so" /etc/pam.d/login; then
            log_info "PAM securetty 모듈 추가 중..."
            sed -i '1i auth       required     pam_securetty.so' /etc/pam.d/login
        fi
    fi
    
    # SSH 설정
    log_info "SSH PermitRootLogin 설정 중..."
    
    # 기존 설정 주석 처리
    sed -i 's/^PermitRootLogin.*/#&/' /etc/ssh/sshd_config
    sed -i 's/^#PermitRootLogin.*/#&/' /etc/ssh/sshd_config
    
    # 새 설정 추가
    if ! grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
        echo "" >> /etc/ssh/sshd_config
        echo "# KISA Security Guide: $MODULE_ID" >> /etc/ssh/sshd_config
        echo "PermitRootLogin no" >> /etc/ssh/sshd_config
    fi
    
    # SSH 설정 검증
    if ! sshd -t 2>/dev/null; then
        log_error "SSH 설정 오류 발견"
        return 1
    fi
    
    # SSH 재시작
    log_info "SSH 서비스 재시작 중..."
    systemctl restart sshd
    
    log_success "설정 적용 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 중..."
    
    local validation_failed=false
    
    # SSH 설정 확인
    local new_setting=$(sshd -T 2>/dev/null | grep "^permitrootlogin" | awk '{print $2}')
    if [ "$new_setting" = "no" ]; then
        log_success "✓ SSH PermitRootLogin: no"
    else
        log_error "✗ SSH PermitRootLogin: $new_setting (예상: no)"
        validation_failed=true
    fi
    
    # Telnet 확인
    if ! systemctl is-active telnetd &>/dev/null && ! dpkg -l | grep -q telnetd 2>/dev/null; then
        log_success "✓ Telnet 서비스 제거됨"
    else
        log_error "✗ Telnet 서비스 여전히 존재"
        validation_failed=true
    fi
    
    if [ "$validation_failed" = true ]; then
        return 1
    fi
    
    return 0
}

# 메인 실행 흐름
main() {
    # 현재 상태 확인
    if check_current_status; then
        log_info "이미 보안 요구사항을 충족합니다"
        exit 0
    fi
    
    # 백업 수행
    if [ "${SKIP_BACKUP:-false}" != true ]; then
        perform_backup
    fi
    
    # 설정 적용
    if ! apply_hardening; then
        log_error "설정 적용 실패"
        exit 1
    fi
    
    # 설정 검증
    if ! validate_settings; then
        log_error "설정 검증 실패"
        exit 1
    fi
    
    log_success "[$MODULE_ID] $MODULE_NAME - 완료"
}

# 스크립트 실행
main "$@"