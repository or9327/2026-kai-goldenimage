#!/bin/bash
# modules/03-service-management/U-46-mail-spam-prevention.sh
# DESC: 메일 서비스 스팸 방지

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-46-48"
MODULE_NAME="메일 서비스 스팸 방지 (U-46, U-48)"
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
    
    # Postfix 확인
    if [ -f /usr/sbin/postsuper ]; then
        local perms=$(stat -c "%a" /usr/sbin/postsuper)
        local other_exec=$(echo "$perms" | cut -c3)
        
        if [ "$other_exec" != "0" ] && [ "$other_exec" != "4" ]; then
            log_warning "Postfix: /usr/sbin/postsuper other 실행권한 있음 ($perms)"
            needs_update=true
        else
            log_success "✓ Postfix: /usr/sbin/postsuper 권한 올바름"
        fi
    fi
    
    # Exim 확인
    if [ -f /usr/sbin/exiqgrep ]; then
        local perms=$(stat -c "%a" /usr/sbin/exiqgrep)
        local other_exec=$(echo "$perms" | cut -c3)
        
        if [ "$other_exec" != "0" ] && [ "$other_exec" != "4" ]; then
            log_warning "Exim: /usr/sbin/exiqgrep other 실행권한 있음 ($perms)"
            needs_update=true
        else
            log_success "✓ Exim: /usr/sbin/exiqgrep 권한 올바름"
        fi
    fi
    
    # Sendmail 확인
    if [ -f /etc/mail/sendmail.cf ]; then
        if grep -q "^O PrivacyOptions=.*restrictqrun" /etc/mail/sendmail.cf; then
            log_success "✓ Sendmail: PrivacyOptions restrictqrun 설정됨"
        else
            log_warning "Sendmail: PrivacyOptions restrictqrun 미설정"
            needs_update=true
        fi
    fi
    
    if [ "$needs_update" = false ]; then
        log_success "✓ 메일 서비스 스팸 방지 설정 완료"
        return 0
    else
        log_warning "설정 변경 필요"
        return 1
    fi
}

# 2. 백업 수행
perform_backup() {
    log_info "설정 파일 백업 중..."
    
    if [ -f /etc/mail/sendmail.cf ]; then
        backup_file "/etc/mail/sendmail.cf" "$MODULE_ID"
    fi
}

# 3. 설정 적용
apply_hardening() {
    log_info "보안 설정 적용 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] 메일 서비스 스팸 방지 설정 시뮬레이션"
        return 0
    fi
    
    local changes_made=false
    
    # Step 1: Postfix - postsuper 권한 제거
    if [ -f /usr/sbin/postsuper ]; then
        log_info "Step 1: Postfix postsuper 권한 설정"
        
        if chmod o-x /usr/sbin/postsuper 2>/dev/null; then
            log_success "✓ /usr/sbin/postsuper: other 실행권한 제거"
            changes_made=true
        else
            log_error "✗ /usr/sbin/postsuper: 권한 변경 실패"
        fi
    fi
    
    # Step 2: Exim - exiqgrep 권한 제거
    if [ -f /usr/sbin/exiqgrep ]; then
        log_info "Step 2: Exim exiqgrep 권한 설정"
        
        if chmod o-x /usr/sbin/exiqgrep 2>/dev/null; then
            log_success "✓ /usr/sbin/exiqgrep: other 실행권한 제거"
            changes_made=true
        else
            log_error "✗ /usr/sbin/exiqgrep: 권한 변경 실패"
        fi
    fi
    
    # Step 3: Sendmail - PrivacyOptions 설정
    if [ -f /etc/mail/sendmail.cf ]; then
        log_info "Step 3: Sendmail PrivacyOptions 설정 (U-46, U-48)"
        
        # 기존 PrivacyOptions 확인
        if grep -q "^O PrivacyOptions=" /etc/mail/sendmail.cf; then
            local current_options=$(grep "^O PrivacyOptions=" /etc/mail/sendmail.cf | cut -d= -f2)
            local needs_update=false
            
            # U-46: restrictqrun 확인
            if ! echo "$current_options" | grep -q "restrictqrun"; then
                needs_update=true
            fi
            
            # U-48: novrfy, noexpn 확인
            if ! echo "$current_options" | grep -q "novrfy"; then
                needs_update=true
            fi
            if ! echo "$current_options" | grep -q "noexpn"; then
                needs_update=true
            fi
            
            if [ "$needs_update" = true ]; then
                # 전체 옵션 설정
                sed -i 's/^O PrivacyOptions=.*/O PrivacyOptions=authwarnings, novrfy, noexpn, restrictqrun/' /etc/mail/sendmail.cf
                log_success "✓ PrivacyOptions 업데이트 (U-46, U-48)"
                changes_made=true
                
                # Sendmail 서비스 재시작
                if systemctl is-active --quiet sendmail 2>/dev/null; then
                    systemctl restart sendmail 2>/dev/null
                    log_success "✓ Sendmail 서비스 재시작"
                fi
            fi
        else
            # PrivacyOptions가 없으면 추가
            echo "O PrivacyOptions=authwarnings, novrfy, noexpn, restrictqrun" >> /etc/mail/sendmail.cf
            log_success "✓ PrivacyOptions 설정 추가 (U-46, U-48)"
            changes_made=true
            
            # Sendmail 서비스 재시작
            if systemctl is-active --quiet sendmail 2>/dev/null; then
                systemctl restart sendmail 2>/dev/null
                log_success "✓ Sendmail 서비스 재시작"
            fi
        fi
    fi
    
    # Step 4: Postfix - disable_vrfy_command 설정 (U-48)
    if [ -f /etc/postfix/main.cf ]; then
        log_info "Step 4: Postfix vrfy 명령 비활성화 (U-48)"
        
        if ! grep -q "^disable_vrfy_command" /etc/postfix/main.cf; then
            echo "" >> /etc/postfix/main.cf
            echo "# KISA U-48: Disable VRFY command" >> /etc/postfix/main.cf
            echo "disable_vrfy_command = yes" >> /etc/postfix/main.cf
            log_success "✓ disable_vrfy_command = yes"
            changes_made=true
            
            # Postfix 재시작
            if systemctl is-active --quiet postfix 2>/dev/null; then
                postfix reload 2>/dev/null
                log_success "✓ Postfix 설정 다시 로드"
            fi
        else
            # 기존 설정 확인
            if grep -q "^disable_vrfy_command.*yes" /etc/postfix/main.cf; then
                log_success "✓ disable_vrfy_command 이미 설정됨"
            else
                sed -i 's/^disable_vrfy_command.*/disable_vrfy_command = yes/' /etc/postfix/main.cf
                log_success "✓ disable_vrfy_command = yes로 변경"
                changes_made=true
                
                if systemctl is-active --quiet postfix 2>/dev/null; then
                    postfix reload 2>/dev/null
                    log_success "✓ Postfix 설정 다시 로드"
                fi
            fi
        fi
    fi
    
    # Step 5: Exim - vrfy/expn ACL 제거 (U-48)
    for exim_conf in /etc/exim/exim.conf /etc/exim4/exim4.conf.template; do
        if [ -f "$exim_conf" ]; then
            log_info "Step 5: Exim vrfy/expn ACL 제거 (U-48)"
            
            local exim_changed=false
            
            # acl_smtp_vrfy 주석 처리
            if grep -q "^acl_smtp_vrfy" "$exim_conf"; then
                sed -i 's/^acl_smtp_vrfy/#acl_smtp_vrfy/' "$exim_conf"
                log_success "✓ acl_smtp_vrfy 비활성화"
                exim_changed=true
            fi
            
            # acl_smtp_expn 주석 처리
            if grep -q "^acl_smtp_expn" "$exim_conf"; then
                sed -i 's/^acl_smtp_expn/#acl_smtp_expn/' "$exim_conf"
                log_success "✓ acl_smtp_expn 비활성화"
                exim_changed=true
            fi
            
            if [ "$exim_changed" = true ]; then
                changes_made=true
                
                # Exim 재시작
                if systemctl is-active --quiet exim4 2>/dev/null; then
                    systemctl restart exim4 2>/dev/null
                    log_success "✓ Exim 서비스 재시작"
                fi
            fi
            
            break
        fi
    done
    
    if [ "$changes_made" = false ]; then
        log_info "변경할 설정이 없습니다"
    fi
    
    log_success "설정 적용 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 중..."
    
    local validation_failed=false
    
    # Postfix 검증
    if [ -f /usr/sbin/postsuper ]; then
        local perms=$(stat -c "%a" /usr/sbin/postsuper)
        local other_exec=$(echo "$perms" | cut -c3)
        
        if [ "$other_exec" = "0" ] || [ "$other_exec" = "4" ]; then
            log_success "✓ Postfix: /usr/sbin/postsuper $perms"
        else
            log_error "✗ Postfix: /usr/sbin/postsuper $perms (other 실행권한 있음)"
            validation_failed=true
        fi
    fi
    
    # Exim 검증
    if [ -f /usr/sbin/exiqgrep ]; then
        local perms=$(stat -c "%a" /usr/sbin/exiqgrep)
        local other_exec=$(echo "$perms" | cut -c3)
        
        if [ "$other_exec" = "0" ] || [ "$other_exec" = "4" ]; then
            log_success "✓ Exim: /usr/sbin/exiqgrep $perms"
        else
            log_error "✗ Exim: /usr/sbin/exiqgrep $perms (other 실행권한 있음)"
            validation_failed=true
        fi
    fi
    
    # Sendmail 검증
    if [ -f /etc/mail/sendmail.cf ]; then
        local privopt=$(grep "^O PrivacyOptions=" /etc/mail/sendmail.cf | cut -d= -f2)
        
        if echo "$privopt" | grep -q "restrictqrun"; then
            log_success "✓ Sendmail: restrictqrun 설정됨 (U-46)"
        else
            log_error "✗ Sendmail: restrictqrun 미설정 (U-46)"
            validation_failed=true
        fi
        
        if echo "$privopt" | grep -q "novrfy" && echo "$privopt" | grep -q "noexpn"; then
            log_success "✓ Sendmail: novrfy, noexpn 설정됨 (U-48)"
        else
            log_error "✗ Sendmail: novrfy, noexpn 미설정 (U-48)"
            validation_failed=true
        fi
    fi
    
    # Postfix 검증 (U-48)
    if [ -f /etc/postfix/main.cf ]; then
        if grep -q "^disable_vrfy_command.*yes" /etc/postfix/main.cf; then
            log_success "✓ Postfix: disable_vrfy_command = yes (U-48)"
        else
            log_error "✗ Postfix: disable_vrfy_command 미설정 (U-48)"
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
    log_info "=== 메일 서비스 스팸 방지 설정 완료 ==="
    log_info "메일 큐 관련 명령어의 일반 사용자 실행이 제한되었습니다."
    log_info ""
    log_info "확인 명령어:"
    log_info "  # Postfix"
    log_info "  ls -l /usr/sbin/postsuper"
    log_info ""
    log_info "  # Exim"
    log_info "  ls -l /usr/sbin/exiqgrep"
    log_info ""
    log_info "  # Sendmail"
    log_info "  grep PrivacyOptions /etc/mail/sendmail.cf"
    log_info ""
    log_info "적용된 보안 설정:"
    log_info "  - Postfix: postsuper 명령어 일반 사용자 실행 제한"
    log_info "  - Exim: exiqgrep 명령어 일반 사용자 실행 제한"
    log_info "  - Sendmail: 메일 큐 조회 제한 (restrictqrun)"
    log_info ""
}

# 스크립트 실행
main "$@"
