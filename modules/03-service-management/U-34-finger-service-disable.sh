#!/bin/bash
# modules/03-service-management/U-34-finger-service-disable.sh
# DESC: Finger 서비스 비활성화

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-34"
MODULE_NAME="Finger 서비스 비활성화"
MODULE_CATEGORY="서비스 관리"
MODULE_SEVERITY="중"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    local needs_update=false
    
    # finger 패키지 설치 확인
    if dpkg -l | grep -q "^ii.*finger"; then
        log_warning "finger 패키지가 설치되어 있음"
        needs_update=true
    else
        log_success "✓ finger 패키지 미설치"
    fi
    
    # inetd 설정 확인 (구형 시스템)
    if [ -f /etc/inetd.conf ]; then
        if grep -v "^#" /etc/inetd.conf | grep -q "finger"; then
            log_warning "inetd에서 finger 서비스 활성화됨"
            needs_update=true
        fi
    fi
    
    # xinetd 설정 확인
    if [ -f /etc/xinetd.d/finger ]; then
        if grep -q "disable.*=.*no" /etc/xinetd.d/finger; then
            log_warning "xinetd에서 finger 서비스 활성화됨"
            needs_update=true
        fi
    fi
    
    if [ "$needs_update" = false ]; then
        log_success "✓ Finger 서비스가 비활성화됨"
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
    
    if [ -f /etc/xinetd.d/finger ]; then
        backup_file "/etc/xinetd.d/finger" "$MODULE_ID"
    fi
}

# 3. 설정 적용
apply_hardening() {
    log_info "보안 설정 적용 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] Finger 서비스 비활성화 시뮬레이션"
        return 0
    fi
    
    local changes_made=false
    
    # Step 1: finger 패키지 제거
    if dpkg -l | grep -q "^ii.*finger"; then
        log_info "Step 1: finger 패키지 제거 중..."
        
        if apt-get remove -y finger 2>/dev/null; then
            log_success "✓ finger 패키지 제거됨"
            changes_made=true
        else
            log_warning "⚠ finger 패키지 제거 실패 (계속 진행)"
        fi
    fi
    
    # Step 2: inetd 설정 비활성화
    if [ -f /etc/inetd.conf ]; then
        log_info "Step 2: inetd finger 서비스 비활성화 중..."
        
        # finger 줄 주석 처리
        sed -i '/^[^#].*finger/s/^/#/' /etc/inetd.conf
        
        # inetd 재시작
        if systemctl is-active --quiet inetd 2>/dev/null; then
            systemctl restart inetd 2>/dev/null
            log_success "✓ inetd 서비스 재시작"
        elif service inetd status >/dev/null 2>&1; then
            service inetd restart 2>/dev/null
            log_success "✓ inetd 서비스 재시작"
        fi
        
        changes_made=true
    fi
    
    # Step 3: xinetd 설정 비활성화
    if [ -f /etc/xinetd.d/finger ]; then
        log_info "Step 3: xinetd finger 서비스 비활성화 중..."
        
        # disable = yes로 변경
        sed -i 's/disable.*=.*no/disable = yes/' /etc/xinetd.d/finger
        
        # xinetd 재시작
        if systemctl is-active --quiet xinetd 2>/dev/null; then
            systemctl restart xinetd 2>/dev/null
            log_success "✓ xinetd 서비스 재시작"
        fi
        
        changes_made=true
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
    
    # finger 패키지 확인
    if dpkg -l | grep -q "^ii.*finger"; then
        log_warning "⚠ finger 패키지가 여전히 설치되어 있음"
    else
        log_success "✓ finger 패키지 미설치"
    fi
    
    # inetd 확인
    if [ -f /etc/inetd.conf ]; then
        if grep -v "^#" /etc/inetd.conf | grep -q "finger"; then
            log_error "✗ inetd에서 finger 서비스 여전히 활성화됨"
            validation_failed=true
        else
            log_success "✓ inetd finger 서비스 비활성화"
        fi
    fi
    
    # xinetd 확인
    if [ -f /etc/xinetd.d/finger ]; then
        if grep -q "disable.*=.*yes" /etc/xinetd.d/finger; then
            log_success "✓ xinetd finger 서비스 비활성화"
        else
            log_error "✗ xinetd finger 서비스 여전히 활성화됨"
            validation_failed=true
        fi
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
    log_info "=== Finger 서비스 비활성화 완료 ==="
    log_info "Finger 서비스는 사용자 정보를 노출하여 보안 위험이 있습니다."
    log_info ""
    log_info "확인 명령어:"
    log_info "  # 패키지 설치 확인"
    log_info "  dpkg -l | grep finger"
    log_info ""
    log_info "  # 서비스 활성화 확인"
    log_info "  grep finger /etc/inetd.conf 2>/dev/null"
    log_info "  cat /etc/xinetd.d/finger 2>/dev/null"
    log_info ""
}

# 스크립트 실행
main "$@"
