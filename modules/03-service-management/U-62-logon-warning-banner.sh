#!/bin/bash
# modules/03-service-management/U-62-logon-warning-banner.sh
# DESC: 로그온 경고 메시지 설정

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-62"
MODULE_NAME="로그온 경고 메시지 설정"
MODULE_CATEGORY="서비스 관리"
MODULE_SEVERITY="하"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# 기본 경고 메시지
DEFAULT_BANNER="
***************************************************************************
                            NOTICE TO USERS

This system is for authorized use only. Individuals using this computer
system without authority or in excess of their authority are subject to
having all their activities on this system monitored and recorded.

Anyone using this system expressly consents to such monitoring and is
advised that if such monitoring reveals possible evidence of criminal
activity, system personnel may provide the evidence of such monitoring
to law enforcement officials.

Unauthorized access is prohibited.
***************************************************************************
"

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    local needs_update=false
    
    # /etc/issue 확인
    if [ ! -f /etc/issue ] || [ ! -s /etc/issue ] || grep -q "Ubuntu" /etc/issue; then
        log_warning "/etc/issue: 경고 메시지 미설정"
        needs_update=true
    fi
    
    # /etc/issue.net 확인
    if [ ! -f /etc/issue.net ] || [ ! -s /etc/issue.net ] || grep -q "Ubuntu" /etc/issue.net; then
        log_warning "/etc/issue.net: 경고 메시지 미설정"
        needs_update=true
    fi
    
    # /etc/motd 확인
    if [ ! -f /etc/motd ] || [ ! -s /etc/motd ]; then
        log_info "/etc/motd: 비어있음"
    fi
    
    # SSH 배너 확인
    if [ -f /etc/ssh/sshd_config ]; then
        if ! grep -q "^Banner" /etc/ssh/sshd_config; then
            log_warning "SSH: 배너 미설정"
            needs_update=true
        fi
    fi
    
    if [ "$needs_update" = false ]; then
        log_success "✓ 경고 메시지 설정 완료"
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
        "/etc/issue"
        "/etc/issue.net"
        "/etc/motd"
        "/etc/ssh/sshd_config"
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
        log_info "[DRY RUN] 경고 메시지 설정 시뮬레이션"
        return 0
    fi
    
    local changes_made=false
    
    # 사용자 정의 배너 확인
    local banner_message="$DEFAULT_BANNER"
    if [ -n "${CUSTOM_BANNER:-}" ]; then
        banner_message="$CUSTOM_BANNER"
        log_info "사용자 정의 배너 사용"
    fi
    
    # Step 1: /etc/issue 설정
    log_info "Step 1: /etc/issue 경고 메시지 설정"
    echo "$banner_message" > /etc/issue
    log_success "✓ /etc/issue 설정"
    changes_made=true
    
    # Step 2: /etc/issue.net 설정
    log_info "Step 2: /etc/issue.net 경고 메시지 설정"
    echo "$banner_message" > /etc/issue.net
    log_success "✓ /etc/issue.net 설정"
    changes_made=true
    
    # Step 3: /etc/motd 설정 (선택적)
    if [ "${SET_MOTD:-false}" = true ]; then
        log_info "Step 3: /etc/motd 경고 메시지 설정"
        echo "$banner_message" > /etc/motd
        log_success "✓ /etc/motd 설정"
        changes_made=true
    fi
    
    # Step 4: SSH 배너 설정
    if [ -f /etc/ssh/sshd_config ]; then
        log_info "Step 4: SSH 배너 설정"
        
        if ! grep -q "^Banner" /etc/ssh/sshd_config; then
            echo "" >> /etc/ssh/sshd_config
            echo "# KISA U-62: Login warning banner" >> /etc/ssh/sshd_config
            echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config
            log_success "✓ SSH 배너 설정"
            changes_made=true
            
            # SSH 재시작
            if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
                systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
                log_success "✓ SSH 서비스 재시작"
            fi
        fi
    fi
    
    # Step 5: 메일 서버 배너 (선택적)
    # Sendmail
    if [ -f /etc/mail/sendmail.cf ]; then
        log_info "Step 5: Sendmail 배너 설정"
        if ! grep -q "^O SmtpGreetingMessage=" /etc/mail/sendmail.cf; then
            echo "O SmtpGreetingMessage=Mail Server - Authorized Use Only" >> /etc/mail/sendmail.cf
            log_success "✓ Sendmail 배너 설정"
            changes_made=true
        fi
    fi
    
    # Postfix
    if [ -f /etc/postfix/main.cf ]; then
        log_info "Step 5: Postfix 배너 설정"
        if ! grep -q "^smtpd_banner" /etc/postfix/main.cf; then
            echo "" >> /etc/postfix/main.cf
            echo "# KISA U-62: SMTP banner" >> /etc/postfix/main.cf
            echo "smtpd_banner = \$myhostname ESMTP - Authorized Use Only" >> /etc/postfix/main.cf
            log_success "✓ Postfix 배너 설정"
            changes_made=true
        fi
    fi
    
    # Step 6: FTP 서버 배너 (이미 U-53에서 설정됨)
    
    # Step 7: DNS 버전 숨김
    for named_conf in /etc/bind/named.conf.options /etc/named.conf; do
        if [ -f "$named_conf" ]; then
            log_info "Step 7: DNS 버전 숨김"
            if ! grep -q "version" "$named_conf"; then
                # options 블록에 추가
                if grep -q "^options {" "$named_conf"; then
                    sed -i '/^options {/a\    # KISA U-62: Hide DNS version\n    version "DNS Server";' "$named_conf"
                    log_success "✓ DNS 버전 숨김 설정"
                    changes_made=true
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
    
    # /etc/issue 확인
    if [ -s /etc/issue ]; then
        log_success "✓ /etc/issue: 경고 메시지 설정됨"
    else
        log_error "✗ /etc/issue: 비어있음"
        validation_failed=true
    fi
    
    # /etc/issue.net 확인
    if [ -s /etc/issue.net ]; then
        log_success "✓ /etc/issue.net: 경고 메시지 설정됨"
    else
        log_error "✗ /etc/issue.net: 비어있음"
        validation_failed=true
    fi
    
    # SSH 배너 확인
    if [ -f /etc/ssh/sshd_config ]; then
        if grep -q "^Banner" /etc/ssh/sshd_config; then
            log_success "✓ SSH: 배너 설정됨"
        else
            log_error "✗ SSH: 배너 미설정"
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
    log_info "=== 로그온 경고 메시지 설정 완료 ==="
    log_info "기본 경고 메시지가 설정되었습니다."
    log_info ""
    log_info "확인 명령어:"
    log_info "  cat /etc/issue"
    log_info "  cat /etc/issue.net"
    log_info "  grep Banner /etc/ssh/sshd_config"
    log_info ""
    log_info "사용자 정의 메시지:"
    log_info "  CUSTOM_BANNER='...' ./kisa-hardening.sh -m U-62"
    log_info ""
}

# 스크립트 실행
main "$@"
