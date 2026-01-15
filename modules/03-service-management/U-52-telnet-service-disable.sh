#!/bin/bash
# modules/03-service-management/U-52-telnet-service-disable.sh
# DESC: Telnet 서비스 비활성화

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-52"
MODULE_NAME="Telnet 서비스 차단"
MODULE_CATEGORY="서비스 관리"
MODULE_SEVERITY="상"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# Telnet 서비스
TELNET_SERVICES=(
    "telnet"
    "telnet.socket"
    "telnetd"
)

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    local needs_update=false
    local active_services=""
    
    # systemd 서비스 확인
    for service in "${TELNET_SERVICES[@]}"; do
        if systemctl list-units --all --type=service,socket 2>/dev/null | grep -q "$service"; then
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                log_warning "$service: 활성화됨"
                active_services="${active_services} ${service}"
                needs_update=true
            fi
        fi
    done
    
    # inetd 확인
    if [ -f /etc/inetd.conf ]; then
        if grep -v "^#" /etc/inetd.conf | grep -q "telnet"; then
            log_warning "inetd에서 telnet 활성화됨"
            needs_update=true
        fi
    fi
    
    # xinetd 확인
    if [ -f /etc/xinetd.d/telnet ]; then
        if grep -q "disable.*=.*no" /etc/xinetd.d/telnet; then
            log_warning "xinetd에서 telnet 활성화됨"
            needs_update=true
        fi
    fi
    
    # 패키지 확인
    if dpkg -l | grep -qE "^ii.*telnetd"; then
        log_warning "telnetd 패키지 설치됨"
        needs_update=true
    fi
    
    # SSH 서비스 확인
    if ! systemctl is-active --quiet sshd 2>/dev/null && ! systemctl is-active --quiet ssh 2>/dev/null; then
        log_warning "⚠ SSH 서비스가 비활성화되어 있음"
    fi
    
    ACTIVE_SERVICES="$active_services"
    
    if [ "$needs_update" = false ]; then
        log_success "✓ Telnet 서비스가 비활성화됨"
        return 0
    else
        log_warning "설정 변경 필요"
        return 1
    fi
}

# 2. 백업 수행
perform_backup() {
    log_info "설정 파일 백업 중..."
    
    if [ -f /etc/inetd.conf ]; then
        backup_file "/etc/inetd.conf" "$MODULE_ID"
    fi
    
    if [ -f /etc/xinetd.d/telnet ]; then
        backup_file "/etc/xinetd.d/telnet" "$MODULE_ID"
    fi
}

# 3. 설정 적용
apply_hardening() {
    log_info "보안 설정 적용 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] Telnet 서비스 비활성화 시뮬레이션"
        return 0
    fi
    
    local changes_made=false
    
    # Step 1: systemd 서비스 비활성화
    log_info "Step 1: systemd Telnet 서비스 비활성화"
    
    for service in "${TELNET_SERVICES[@]}"; do
        if systemctl list-units --all --type=service,socket 2>/dev/null | grep -q "$service"; then
            # 서비스 중지
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                systemctl stop "$service" 2>/dev/null
                log_success "✓ $service 중지"
            fi
            
            # 서비스 비활성화
            if systemctl is-enabled --quiet "$service" 2>/dev/null; then
                systemctl disable "$service" 2>/dev/null
                log_success "✓ $service 비활성화"
                changes_made=true
            fi
        fi
    done
    
    # Step 2: telnetd 패키지 제거
    log_info "Step 2: telnetd 패키지 제거"
    
    if dpkg -l | grep -q "^ii.*telnetd"; then
        if apt-get remove -y telnetd 2>/dev/null; then
            log_success "✓ telnetd 패키지 제거"
            changes_made=true
        fi
    fi
    
    # Step 3: inetd 설정 비활성화
    if [ -f /etc/inetd.conf ]; then
        log_info "Step 3: inetd telnet 서비스 비활성화"
        
        sed -i '/^[^#].*telnet/s/^/#/' /etc/inetd.conf
        
        # inetd 재시작
        if systemctl is-active --quiet inetd 2>/dev/null; then
            systemctl restart inetd 2>/dev/null
            log_success "✓ inetd 서비스 재시작"
        fi
        
        changes_made=true
    fi
    
    # Step 4: xinetd 설정 비활성화
    if [ -f /etc/xinetd.d/telnet ]; then
        log_info "Step 4: xinetd telnet 서비스 비활성화"
        
        sed -i 's/disable.*=.*no/disable = yes/' /etc/xinetd.d/telnet
        log_success "✓ telnet (xinetd) 비활성화"
        changes_made=true
        
        # xinetd 재시작
        if systemctl is-active --quiet xinetd 2>/dev/null; then
            systemctl restart xinetd 2>/dev/null
            log_success "✓ xinetd 서비스 재시작"
        fi
    fi
    
    # Step 5: SSH 서비스 확인 및 시작
    log_info "Step 5: SSH 서비스 확인"
    
    if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
        log_success "✓ SSH 서비스 활성화됨"
    else
        log_warning "SSH 서비스 시작 중..."
        
        # sshd 또는 ssh 서비스 시작
        if systemctl list-units --all --type=service | grep -q "sshd.service"; then
            systemctl start sshd 2>/dev/null && log_success "✓ sshd 서비스 시작"
        elif systemctl list-units --all --type=service | grep -q "ssh.service"; then
            systemctl start ssh 2>/dev/null && log_success "✓ ssh 서비스 시작"
        else
            log_warning "⚠ SSH 서비스를 찾을 수 없음"
        fi
    fi
    
    if [ "$changes_made" = false ]; then
        log_info "변경할 설정이 없습니다"
    fi
    
    log_success "설정 적용 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 중..."
    
    local validation_failed=false
    
    # systemd 서비스 확인
    for service in "${TELNET_SERVICES[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_error "✗ $service: 여전히 활성화됨"
            validation_failed=true
        fi
    done
    
    # 패키지 확인
    if dpkg -l | grep -q "^ii.*telnetd"; then
        log_warning "⚠ telnetd 패키지가 여전히 설치되어 있음"
    else
        log_success "✓ telnetd 패키지 미설치"
    fi
    
    # inetd 확인
    if [ -f /etc/inetd.conf ]; then
        if grep -v "^#" /etc/inetd.conf | grep -q "telnet"; then
            log_error "✗ inetd에서 telnet 여전히 활성화"
            validation_failed=true
        else
            log_success "✓ inetd telnet 비활성화"
        fi
    fi
    
    # SSH 확인
    if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
        log_success "✓ SSH 서비스 활성화됨"
    else
        log_warning "⚠ SSH 서비스가 비활성화되어 있음"
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
    
    # 드라이런 모드에서는 검증 스킵
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] 검증 단계 생략"
        log_success "[$MODULE_ID] $MODULE_NAME - 완료 (드라이런)"
        exit 0
    fi
    
    # 설정 검증
    if ! validate_settings; then
        log_error "설정 검증 실패"
        exit 1
    fi
    
    log_success "[$MODULE_ID] $MODULE_NAME - 완료"
    
    # 추가 안내
    log_info ""
    log_info "=== Telnet 서비스 차단 완료 ==="
    log_info "Telnet은 평문으로 통신하여 보안상 취약합니다."
    log_info "SSH를 사용하세요."
    log_info ""
    log_info "확인 명령어:"
    log_info "  # Telnet 서비스 확인"
    log_info "  systemctl status telnet.socket"
    log_info ""
    log_info "  # SSH 서비스 확인"
    log_info "  systemctl status sshd"
    log_info ""
}

# 스크립트 실행
main "$@"
