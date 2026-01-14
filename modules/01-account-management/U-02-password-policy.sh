#!/bin/bash
# modules/01-account-management/U-02-password-policy.sh
# DESC: 비밀번호 관리정책 설정

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-02"
MODULE_NAME="비밀번호 관리정책 설정"
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
    
    local needs_update=false
    
    # /etc/login.defs 확인
    if [ -f /etc/login.defs ]; then
        local max_days=$(grep "^PASS_MAX_DAYS" /etc/login.defs | awk '{print $2}')
        local min_days=$(grep "^PASS_MIN_DAYS" /etc/login.defs | awk '{print $2}')
        
        log_info "현재 PASS_MAX_DAYS: ${max_days:-없음}"
        log_info "현재 PASS_MIN_DAYS: ${min_days:-없음}"
        
        if [ "$max_days" != "90" ] || [ "$min_days" != "1" ]; then
            needs_update=true
        fi
    else
        log_warning "/etc/login.defs 파일을 찾을 수 없음"
        needs_update=true
    fi
    
    # /etc/security/pwquality.conf 확인
    if [ -f /etc/security/pwquality.conf ]; then
        local minlen=$(grep "^minlen" /etc/security/pwquality.conf | awk '{print $3}')
        log_info "현재 minlen: ${minlen:-없음}"
        
        if [ "$minlen" != "8" ]; then
            needs_update=true
        fi
    else
        log_warning "/etc/security/pwquality.conf 파일을 찾을 수 없음"
        needs_update=true
    fi
    
    if [ "$needs_update" = false ]; then
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
    
    backup_file "/etc/login.defs" "$MODULE_ID"
    
    if [ -f /etc/security/pwquality.conf ]; then
        backup_file "/etc/security/pwquality.conf" "$MODULE_ID"
    fi
    
    # Ubuntu/Debian
    if [ -f /etc/pam.d/common-password ]; then
        backup_file "/etc/pam.d/common-password" "$MODULE_ID"
    fi
    
    # RHEL/CentOS
    if [ -f /etc/pam.d/system-auth ]; then
        backup_file "/etc/pam.d/system-auth" "$MODULE_ID"
    fi
}

# 3. 설정 적용
apply_hardening() {
    log_info "보안 설정 적용 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] 비밀번호 정책 설정 시뮬레이션"
        return 0
    fi
    
    # Step 1: /etc/login.defs 수정
    log_info "Step 1: /etc/login.defs 설정 중..."
    
    if [ -f /etc/login.defs ]; then
        # PASS_MAX_DAYS 설정
        if grep -q "^PASS_MAX_DAYS" /etc/login.defs; then
            sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
        else
            echo "PASS_MAX_DAYS   90" >> /etc/login.defs
        fi
        
        # PASS_MIN_DAYS 설정
        if grep -q "^PASS_MIN_DAYS" /etc/login.defs; then
            sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/' /etc/login.defs
        else
            echo "PASS_MIN_DAYS   1" >> /etc/login.defs
        fi
        
        log_success "✓ /etc/login.defs 설정 완료"
    else
        log_error "/etc/login.defs 파일이 없습니다"
        return 1
    fi
    
    # Step 2: libpam-pwquality 패키지 확인 및 설치
    log_info "Step 2: libpam-pwquality 패키지 확인 중..."
    
    if ! dpkg -l | grep -q libpam-pwquality; then
        log_info "libpam-pwquality 설치 중..."
        apt-get update -qq
        apt-get install -y libpam-pwquality
    else
        log_success "✓ libpam-pwquality 이미 설치됨"
    fi
    
    # Step 3: /etc/security/pwquality.conf 수정
    log_info "Step 3: /etc/security/pwquality.conf 설정 중..."
    
    if [ ! -f /etc/security/pwquality.conf ]; then
        touch /etc/security/pwquality.conf
    fi
    
    # 기존 설정 주석 처리 후 새 설정 추가
    sed -i 's/^minlen/#&/' /etc/security/pwquality.conf
    sed -i 's/^dcredit/#&/' /etc/security/pwquality.conf
    sed -i 's/^ucredit/#&/' /etc/security/pwquality.conf
    sed -i 's/^lcredit/#&/' /etc/security/pwquality.conf
    sed -i 's/^ocredit/#&/' /etc/security/pwquality.conf
    sed -i 's/^enforce_for_root/#&/' /etc/security/pwquality.conf
    
    # KISA 권고 설정 추가
    cat >> /etc/security/pwquality.conf << 'EOF'

# KISA Security Guide: U-02
minlen = 8
dcredit = -1
ucredit = -1
lcredit = -1
ocredit = -1
enforce_for_root
EOF
    
    log_success "✓ /etc/security/pwquality.conf 설정 완료"
    
    # Step 4: PAM 설정 (Ubuntu/Debian)
    if [ -f /etc/pam.d/common-password ]; then
        log_info "Step 4: /etc/pam.d/common-password 설정 중..."
        
        # pam_pwquality.so 설정 확인
        if ! grep -q "pam_pwquality.so" /etc/pam.d/common-password; then
            # pam_unix.so 위에 pam_pwquality.so 추가
            sed -i '/pam_unix.so/i password        requisite                       pam_pwquality.so retry=3' /etc/pam.d/common-password
        fi
        
        # pam_pwhistory.so 설정 확인 및 추가
        if ! grep -q "pam_pwhistory.so" /etc/pam.d/common-password; then
            # pam_unix.so 위에 pam_pwhistory.so 추가
            sed -i '/pam_unix.so/i password        required                        pam_pwhistory.so remember=4 enforce_for_root' /etc/pam.d/common-password
        else
            # 기존 설정 업데이트
            sed -i 's/.*pam_pwhistory.so.*/password        required                        pam_pwhistory.so remember=4 enforce_for_root/' /etc/pam.d/common-password
        fi
        
        log_success "✓ /etc/pam.d/common-password 설정 완료"
    fi
    
    # Step 5: PAM 설정 (RHEL/CentOS - 참고용)
    if [ -f /etc/pam.d/system-auth ]; then
        log_info "Step 5: /etc/pam.d/system-auth 설정 중..."
        
        if ! grep -q "pam_pwquality.so" /etc/pam.d/system-auth; then
            sed -i '/pam_unix.so/i password    requisite     pam_pwquality.so try_first_pass local_users_only retry=3 authtok_type=' /etc/pam.d/system-auth
        fi
        
        if ! grep -q "pam_pwhistory.so" /etc/pam.d/system-auth; then
            sed -i '/pam_unix.so/i password    required      pam_pwhistory.so remember=4 enforce_for_root' /etc/pam.d/system-auth
        fi
        
        log_success "✓ /etc/pam.d/system-auth 설정 완료"
    fi
    
    log_success "설정 적용 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 중..."
    
    local validation_failed=false
    
    # /etc/login.defs 검증
    if [ -f /etc/login.defs ]; then
        local max_days=$(grep "^PASS_MAX_DAYS" /etc/login.defs | awk '{print $2}')
        local min_days=$(grep "^PASS_MIN_DAYS" /etc/login.defs | awk '{print $2}')
        
        if [ "$max_days" = "90" ]; then
            log_success "✓ PASS_MAX_DAYS: 90"
        else
            log_error "✗ PASS_MAX_DAYS: ${max_days} (예상: 90)"
            validation_failed=true
        fi
        
        if [ "$min_days" = "1" ]; then
            log_success "✓ PASS_MIN_DAYS: 1"
        else
            log_error "✗ PASS_MIN_DAYS: ${min_days} (예상: 1)"
            validation_failed=true
        fi
    else
        log_error "✗ /etc/login.defs 파일 없음"
        validation_failed=true
    fi
    
    # /etc/security/pwquality.conf 검증
    if [ -f /etc/security/pwquality.conf ]; then
        local minlen=$(grep "^minlen" /etc/security/pwquality.conf | tail -1 | awk '{print $3}')
        local dcredit=$(grep "^dcredit" /etc/security/pwquality.conf | tail -1 | awk '{print $3}')
        local ucredit=$(grep "^ucredit" /etc/security/pwquality.conf | tail -1 | awk '{print $3}')
        local lcredit=$(grep "^lcredit" /etc/security/pwquality.conf | tail -1 | awk '{print $3}')
        local ocredit=$(grep "^ocredit" /etc/security/pwquality.conf | tail -1 | awk '{print $3}')
        
        if [ "$minlen" = "8" ]; then
            log_success "✓ minlen: 8"
        else
            log_error "✗ minlen: ${minlen} (예상: 8)"
            validation_failed=true
        fi
        
        if [ "$dcredit" = "-1" ]; then
            log_success "✓ dcredit: -1"
        else
            log_error "✗ dcredit: ${dcredit} (예상: -1)"
            validation_failed=true
        fi
        
        if [ "$ucredit" = "-1" ]; then
            log_success "✓ ucredit: -1"
        else
            log_error "✗ ucredit: ${ucredit} (예상: -1)"
            validation_failed=true
        fi
        
        if [ "$lcredit" = "-1" ]; then
            log_success "✓ lcredit: -1"
        else
            log_error "✗ lcredit: ${lcredit} (예상: -1)"
            validation_failed=true
        fi
        
        if [ "$ocredit" = "-1" ]; then
            log_success "✓ ocredit: -1"
        else
            log_error "✗ ocredit: ${ocredit} (예상: -1)"
            validation_failed=true
        fi
        
        if grep -q "^enforce_for_root" /etc/security/pwquality.conf; then
            log_success "✓ enforce_for_root 설정됨"
        else
            log_warning "⚠ enforce_for_root 미설정"
        fi
    else
        log_error "✗ /etc/security/pwquality.conf 파일 없음"
        validation_failed=true
    fi
    
    # PAM 설정 검증
    if [ -f /etc/pam.d/common-password ]; then
        if grep -q "pam_pwquality.so" /etc/pam.d/common-password; then
            log_success "✓ pam_pwquality.so 설정됨"
        else
            log_error "✗ pam_pwquality.so 미설정"
            validation_failed=true
        fi
        
        if grep -q "pam_pwhistory.so" /etc/pam.d/common-password; then
            log_success "✓ pam_pwhistory.so 설정됨"
        else
            log_warning "⚠ pam_pwhistory.so 미설정"
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
    log_info "=== 비밀번호 정책 적용 완료 ==="
    log_info "새 정책은 다음 비밀번호 변경 시 적용됩니다."
    log_info "기존 사용자의 비밀번호 만료 기간을 즉시 적용하려면:"
    log_info "  sudo chage -M 90 -m 1 <username>"
    log_info ""
}

# 스크립트 실행
main "$@"