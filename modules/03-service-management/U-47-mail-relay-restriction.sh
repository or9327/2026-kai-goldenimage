#!/bin/bash
# modules/03-service-management/U-47-mail-relay-restriction.sh
# DESC: 메일 릴레이 제한 (localhost만 허용)

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-47"
MODULE_NAME="메일 릴레이 제한"
MODULE_CATEGORY="서비스 관리"
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
    local has_mail_service=false
    
    # Sendmail 확인
    if [ -f /etc/mail/sendmail.cf ]; then
        has_mail_service=true
        log_info "Sendmail 설정 확인"
        
        # promiscuous_relay 확인 (있으면 안됨)
        if [ -f /etc/mail/sendmail.mc ]; then
            if grep -q "^FEATURE(\`promiscuous_relay')" /etc/mail/sendmail.mc; then
                log_warning "Sendmail: promiscuous_relay 활성화됨 (모든 릴레이 허용)"
                needs_update=true
            fi
        fi
        
        # access 파일 확인
        if [ -f /etc/mail/access ]; then
            local relay_count=$(grep -v "^#" /etc/mail/access | grep -c "RELAY")
            log_info "Sendmail: /etc/mail/access에 $relay_count개 RELAY 설정"
        fi
    fi
    
    # Postfix 확인
    if [ -f /etc/postfix/main.cf ]; then
        has_mail_service=true
        log_info "Postfix 설정 확인"
        
        # mynetworks 확인
        local mynetworks=$(grep "^mynetworks" /etc/postfix/main.cf | cut -d= -f2 | tr -d ' ')
        
        if [ -n "$mynetworks" ]; then
            log_info "Postfix: mynetworks = $mynetworks"
            
            # 안전하지 않은 설정 확인
            if echo "$mynetworks" | grep -qE "0\.0\.0\.0/0|::/0"; then
                log_warning "Postfix: 모든 네트워크에서 릴레이 허용"
                needs_update=true
            fi
        else
            log_info "Postfix: mynetworks 기본값 사용 (안전)"
        fi
    fi
    
    # Exim 확인
    for exim_conf in /etc/exim/exim.conf /etc/exim4/exim4.conf.template /etc/exim4/update-exim4.conf.conf; do
        if [ -f "$exim_conf" ]; then
            has_mail_service=true
            log_info "Exim 설정 확인: $exim_conf"
            
            # relay_from_hosts 확인
            if grep -q "relay_from_hosts" "$exim_conf"; then
                local relay_hosts=$(grep "relay_from_hosts" "$exim_conf" | grep -v "^#")
                log_info "Exim: $relay_hosts"
            fi
        fi
    done
    
    if [ "$has_mail_service" = false ]; then
        log_success "✓ 메일 서비스 미설치"
        return 0
    fi
    
    if [ "$needs_update" = false ]; then
        log_success "✓ 메일 릴레이 제한 설정 안전"
        return 0
    else
        log_warning "설정 변경 필요"
        return 1
    fi
}

# 2. 백업 수행
perform_backup() {
    log_info "설정 파일 백업 중..."
    
    local files_to_backup=(
        "/etc/mail/sendmail.cf"
        "/etc/mail/sendmail.mc"
        "/etc/mail/access"
        "/etc/postfix/main.cf"
        "/etc/exim/exim.conf"
        "/etc/exim4/exim4.conf.template"
        "/etc/exim4/update-exim4.conf.conf"
    )
    
    for file in "${files_to_backup[@]}"; do
        if [ -f "$file" ]; then
            backup_file "$file" "$MODULE_ID"
        fi
    done
}

# 3. 설정 적용
apply_hardening() {
    log_info "보안 설정 적용 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] 메일 릴레이 제한 설정 시뮬레이션"
        return 0
    fi
    
    local changes_made=false
    
    # Step 1: Sendmail 설정
    if [ -f /etc/mail/sendmail.mc ]; then
        log_info "Step 1: Sendmail 릴레이 제한 설정"
        
        # promiscuous_relay 제거
        if grep -q "^FEATURE(\`promiscuous_relay')" /etc/mail/sendmail.mc; then
            sed -i "/^FEATURE(\`promiscuous_relay')/d" /etc/mail/sendmail.mc
            log_success "✓ promiscuous_relay 제거"
            
            # sendmail.cf 재생성
            if command -v m4 &>/dev/null; then
                m4 /etc/mail/sendmail.mc > /etc/mail/sendmail.cf 2>/dev/null
                log_success "✓ sendmail.cf 재생성"
            fi
            
            changes_made=true
        fi
        
        # access 파일 기본 설정 확인
        if [ ! -f /etc/mail/access ]; then
            log_info "Step 1-2: /etc/mail/access 기본 설정 생성"
            
            cat > /etc/mail/access << 'EOF'
# Mail relay access control
# Only allow localhost to relay
localhost.localdomain   RELAY
localhost               RELAY
127.0.0.1               RELAY
EOF
            
            # access.db 생성
            if command -v makemap &>/dev/null; then
                makemap hash /etc/mail/access.db < /etc/mail/access 2>/dev/null
                log_success "✓ /etc/mail/access 생성 (localhost만 허용)"
            fi
            
            changes_made=true
        fi
        
        # Sendmail 재시작
        if [ "$changes_made" = true ] && systemctl is-active --quiet sendmail 2>/dev/null; then
            systemctl restart sendmail 2>/dev/null
            log_success "✓ Sendmail 서비스 재시작"
        fi
    fi
    
    # Step 2: Postfix 설정
    if [ -f /etc/postfix/main.cf ]; then
        log_info "Step 2: Postfix 릴레이 제한 설정"
        
        # mynetworks 확인 및 설정
        if ! grep -q "^mynetworks" /etc/postfix/main.cf; then
            # mynetworks 설정 추가 (localhost만)
            echo "" >> /etc/postfix/main.cf
            echo "# KISA U-47: Restrict mail relay to localhost only" >> /etc/postfix/main.cf
            echo "mynetworks = 127.0.0.0/8 [::1]/128" >> /etc/postfix/main.cf
            log_success "✓ mynetworks 설정 추가 (localhost만)"
            changes_made=true
        else
            # 기존 mynetworks 확인
            local mynetworks=$(grep "^mynetworks" /etc/postfix/main.cf | cut -d= -f2)
            
            if echo "$mynetworks" | grep -qE "0\.0\.0\.0/0|::/0"; then
                log_warning "⚠ mynetworks에 모든 네트워크 포함"
                log_warning "  수동으로 확인 필요: /etc/postfix/main.cf"
            else
                log_success "✓ mynetworks 설정 안전"
            fi
        fi
        
        # Postfix 재시작
        if [ "$changes_made" = true ] && systemctl is-active --quiet postfix 2>/dev/null; then
            postfix reload 2>/dev/null
            log_success "✓ Postfix 설정 다시 로드"
        fi
    fi
    
    # Step 3: Exim 설정
    for exim_conf in /etc/exim4/update-exim4.conf.conf /etc/exim4/exim4.conf.template; do
        if [ -f "$exim_conf" ]; then
            log_info "Step 3: Exim 릴레이 제한 설정"
            
            # dc_relay_nets 확인 (Debian/Ubuntu)
            if [ -f /etc/exim4/update-exim4.conf.conf ]; then
                if ! grep -q "^dc_relay_nets=" /etc/exim4/update-exim4.conf.conf; then
                    echo "dc_relay_nets='127.0.0.1'" >> /etc/exim4/update-exim4.conf.conf
                    log_success "✓ dc_relay_nets 설정 추가 (localhost만)"
                    changes_made=true
                    
                    # 설정 업데이트
                    if command -v update-exim4.conf &>/dev/null; then
                        update-exim4.conf 2>/dev/null
                        log_success "✓ Exim 설정 업데이트"
                    fi
                fi
            fi
            
            # Exim 재시작
            if [ "$changes_made" = true ] && systemctl is-active --quiet exim4 2>/dev/null; then
                systemctl restart exim4 2>/dev/null
                log_success "✓ Exim 서비스 재시작"
            fi
            
            break
        fi
    done
    
    if [ "$changes_made" = false ]; then
        log_info "변경할 설정이 없습니다 (기본 설정이 이미 안전함)"
    fi
    
    log_success "설정 적용 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 중..."
    
    local validation_failed=false
    
    # Sendmail 검증
    if [ -f /etc/mail/sendmail.mc ]; then
        if grep -q "^FEATURE(\`promiscuous_relay')" /etc/mail/sendmail.mc; then
            log_error "✗ Sendmail: promiscuous_relay 여전히 활성화"
            validation_failed=true
        else
            log_success "✓ Sendmail: promiscuous_relay 비활성화"
        fi
    fi
    
    # Postfix 검증
    if [ -f /etc/postfix/main.cf ]; then
        local mynetworks=$(grep "^mynetworks" /etc/postfix/main.cf | cut -d= -f2)
        
        if [ -n "$mynetworks" ]; then
            if echo "$mynetworks" | grep -qE "0\.0\.0\.0/0|::/0"; then
                log_warning "⚠ Postfix: 광범위한 네트워크 허용"
            else
                log_success "✓ Postfix: mynetworks 설정 안전"
            fi
        else
            log_success "✓ Postfix: 기본 설정 사용 (안전)"
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
    log_info "=== 메일 릴레이 제한 설정 완료 ==="
    log_info "기본적으로 localhost만 메일 릴레이를 사용할 수 있습니다."
    log_info ""
    log_info "확인 명령어:"
    log_info "  # Sendmail"
    log_info "  cat /etc/mail/access"
    log_info ""
    log_info "  # Postfix"
    log_info "  postconf mynetworks"
    log_info ""
    log_info "  # Exim"
    log_info "  grep relay_nets /etc/exim4/update-exim4.conf.conf"
    log_info ""
    log_info "외부 네트워크 추가 (수동):"
    log_info "  # Sendmail"
    log_info "  echo '192.168.1.0/24 RELAY' >> /etc/mail/access"
    log_info "  makemap hash /etc/mail/access.db < /etc/mail/access"
    log_info ""
    log_info "  # Postfix"
    log_info "  postconf -e 'mynetworks = 127.0.0.0/8 192.168.1.0/24'"
    log_info "  postfix reload"
    log_info ""
    log_info "  # Exim"
    log_info "  vi /etc/exim4/update-exim4.conf.conf"
    log_info "  # dc_relay_nets='127.0.0.1 ; 192.168.1.0/24'"
    log_info "  update-exim4.conf && systemctl restart exim4"
    log_info ""
}

# 스크립트 실행
main "$@"
