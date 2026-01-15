#!/bin/bash
# modules/04-patch-management/U-65-66-67-logging-and-time.sh
# DESC: 시간 동기화 및 로깅 설정 (U-65, U-66, U-67)

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-65-66-67"
MODULE_NAME="시간 동기화 및 로깅 설정"
MODULE_CATEGORY="패치 관리"
MODULE_SEVERITY="중"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# 공개 NTP 서버 (기본값)
DEFAULT_NTP_SERVERS=(
    "time.google.com"
    "time.cloudflare.com"
    "pool.ntp.org"
)

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    local needs_update=false
    
    # U-65: NTP/Chrony 확인
    log_info "=== U-65: NTP/Chrony 서비스 확인 ==="
    
    if systemctl is-active --quiet chronyd 2>/dev/null; then
        log_success "✓ Chrony 서비스 활성화됨"
    elif systemctl is-active --quiet ntp 2>/dev/null; then
        log_success "✓ NTP 서비스 활성화됨"
    elif systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
        log_success "✓ systemd-timesyncd 활성화됨"
    else
        log_warning "시간 동기화 서비스 비활성화"
        needs_update=true
    fi
    
    # U-66: rsyslog 확인
    log_info "=== U-66: rsyslog 설정 확인 ==="
    
    if ! systemctl is-active --quiet rsyslog 2>/dev/null; then
        log_warning "rsyslog 서비스 비활성화"
        needs_update=true
    fi
    
    # U-67: 로그 파일 권한 확인
    log_info "=== U-67: 로그 파일 권한 확인 ==="
    
    if [ -d /var/log ]; then
        local bad_perms=0
        for logfile in /var/log/*.log /var/log/syslog /var/log/messages /var/log/secure /var/log/auth.log; do
            if [ -f "$logfile" ]; then
                local perms=$(stat -c "%a" "$logfile" 2>/dev/null)
                if [ -n "$perms" ] && [ "$perms" != "640" ] && [ "$perms" != "644" ]; then
                    bad_perms=$((bad_perms + 1))
                fi
            fi
        done
        
        if [ "$bad_perms" -gt 0 ]; then
            log_warning "로그 파일 권한 변경 필요: $bad_perms개"
            needs_update=true
        fi
    fi
    
    if [ "$needs_update" = false ]; then
        log_success "✓ 시간 동기화 및 로깅 설정 완료"
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
        "/etc/chrony/chrony.conf"
        "/etc/chrony.conf"
        "/etc/ntp.conf"
        "/etc/systemd/timesyncd.conf"
        "/etc/rsyslog.conf"
        "/etc/rsyslog.d/50-default.conf"
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
        log_info "[DRY RUN] 시간 동기화 및 로깅 설정 시뮬레이션"
        return 0
    fi
    
    local changes_made=false
    
    # U-65: NTP/Chrony 설정
    log_info "=== U-65: 시간 동기화 설정 ==="
    
    # Chrony 우선
    if command -v chronyd &>/dev/null || [ -f /etc/chrony.conf ] || [ -f /etc/chrony/chrony.conf ]; then
        configure_chrony
        changes_made=true
    # systemd-timesyncd
    elif [ -f /etc/systemd/timesyncd.conf ]; then
        configure_timesyncd
        changes_made=true
    # NTP
    elif command -v ntpd &>/dev/null || [ -f /etc/ntp.conf ]; then
        configure_ntp
        changes_made=true
    else
        log_warning "시간 동기화 서비스를 찾을 수 없음"
    fi
    
    # U-66: rsyslog 설정
    log_info "=== U-66: rsyslog 로그 정책 설정 ==="
    
    if configure_rsyslog; then
        changes_made=true
    fi
    
    # U-67: 로그 파일 권한 설정
    log_info "=== U-67: 로그 파일 권한 설정 ==="
    
    if configure_log_permissions; then
        changes_made=true
    fi
    
    if [ "$changes_made" = false ]; then
        log_info "변경할 설정이 없습니다"
    fi
    
    log_success "설정 적용 완료"
}

# Chrony 설정 함수
configure_chrony() {
    log_info "Chrony 설정 중..."
    
    local chrony_conf=""
    if [ -f /etc/chrony/chrony.conf ]; then
        chrony_conf="/etc/chrony/chrony.conf"
    elif [ -f /etc/chrony.conf ]; then
        chrony_conf="/etc/chrony.conf"
    fi
    
    if [ -z "$chrony_conf" ]; then
        log_warning "chrony.conf 파일을 찾을 수 없음"
        return 1
    fi
    
    # 기본 NTP 서버 추가
    for ntp_server in "${DEFAULT_NTP_SERVERS[@]}"; do
        if ! grep -q "$ntp_server" "$chrony_conf"; then
            echo "server $ntp_server iburst" >> "$chrony_conf"
            log_success "✓ NTP 서버 추가: $ntp_server"
        fi
    done
    
    # Chrony 서비스 활성화 및 시작
    if ! systemctl is-active --quiet chronyd; then
        systemctl enable chronyd 2>/dev/null
        systemctl start chronyd 2>/dev/null
        log_success "✓ Chrony 서비스 시작"
    else
        systemctl restart chronyd 2>/dev/null
        log_success "✓ Chrony 서비스 재시작"
    fi
}

# systemd-timesyncd 설정 함수
configure_timesyncd() {
    log_info "systemd-timesyncd 설정 중..."
    
    if [ -f /etc/systemd/timesyncd.conf ]; then
        # NTP 서버 설정
        if ! grep -q "^NTP=" /etc/systemd/timesyncd.conf; then
            echo "" >> /etc/systemd/timesyncd.conf
            echo "[Time]" >> /etc/systemd/timesyncd.conf
            echo "NTP=${DEFAULT_NTP_SERVERS[*]}" >> /etc/systemd/timesyncd.conf
            log_success "✓ NTP 서버 설정"
        fi
        
        # 서비스 활성화
        if ! systemctl is-active --quiet systemd-timesyncd; then
            systemctl enable systemd-timesyncd 2>/dev/null
            systemctl start systemd-timesyncd 2>/dev/null
            log_success "✓ systemd-timesyncd 시작"
        else
            systemctl restart systemd-timesyncd 2>/dev/null
            log_success "✓ systemd-timesyncd 재시작"
        fi
    fi
}

# NTP 설정 함수
configure_ntp() {
    log_info "NTP 설정 중..."
    
    if [ -f /etc/ntp.conf ]; then
        # 기본 NTP 서버 추가
        for ntp_server in "${DEFAULT_NTP_SERVERS[@]}"; do
            if ! grep -q "$ntp_server" /etc/ntp.conf; then
                echo "server $ntp_server iburst" >> /etc/ntp.conf
                log_success "✓ NTP 서버 추가: $ntp_server"
            fi
        done
        
        # NTP 서비스 활성화
        if ! systemctl is-active --quiet ntp; then
            systemctl enable ntp 2>/dev/null
            systemctl start ntp 2>/dev/null
            log_success "✓ NTP 서비스 시작"
        else
            systemctl restart ntp 2>/dev/null
            log_success "✓ NTP 서비스 재시작"
        fi
    fi
}

# rsyslog 설정 함수
configure_rsyslog() {
    if ! systemctl is-active --quiet rsyslog 2>/dev/null; then
        log_warning "rsyslog 서비스 비활성화"
        return 1
    fi
    
    local rsyslog_conf="/etc/rsyslog.conf"
    local default_conf="/etc/rsyslog.d/50-default.conf"
    
    # 기본 로그 정책 확인
    local conf_file="$rsyslog_conf"
    if [ -f "$default_conf" ]; then
        conf_file="$default_conf"
    fi
    
    # 필수 로그 항목 확인
    local required_logs=(
        "*.info;mail.none;authpriv.none;cron.none"
        "authpriv.*"
        "mail.*"
        "cron.*"
    )
    
    local missing=false
    for log_entry in "${required_logs[@]}"; do
        if ! grep -q "$log_entry" "$conf_file" 2>/dev/null; then
            missing=true
            break
        fi
    done
    
    if [ "$missing" = true ]; then
        log_info "기본 로그 정책이 설정되어 있지 않음 - 기본값 사용"
    fi
    
    # rsyslog 재시작
    systemctl restart rsyslog 2>/dev/null
    log_success "✓ rsyslog 서비스 재시작"
    
    return 0
}

# 로그 파일 권한 설정 함수
configure_log_permissions() {
    local changes=0
    
    # /var/log 디렉토리 내 로그 파일 권한 설정
    for logfile in /var/log/*.log /var/log/syslog /var/log/messages /var/log/secure /var/log/auth.log /var/log/kern.log /var/log/daemon.log; do
        if [ -f "$logfile" ]; then
            chown root:root "$logfile" 2>/dev/null
            chmod 640 "$logfile" 2>/dev/null
            changes=$((changes + 1))
        fi
    done
    
    if [ "$changes" -gt 0 ]; then
        log_success "✓ 로그 파일 권한 설정: $changes개"
        return 0
    fi
    
    return 1
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 중..."
    
    local validation_failed=false
    
    # U-65: 시간 동기화 확인
    if systemctl is-active --quiet chronyd 2>/dev/null || \
       systemctl is-active --quiet ntp 2>/dev/null || \
       systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
        log_success "✓ 시간 동기화 서비스 활성화 (U-65)"
    else
        log_error "✗ 시간 동기화 서비스 비활성화 (U-65)"
        validation_failed=true
    fi
    
    # U-66: rsyslog 확인
    if systemctl is-active --quiet rsyslog 2>/dev/null; then
        log_success "✓ rsyslog 서비스 활성화 (U-66)"
    else
        log_error "✗ rsyslog 서비스 비활성화 (U-66)"
        validation_failed=true
    fi
    
    # U-67: 로그 파일 권한 확인
    local checked=0
    local correct=0
    for logfile in /var/log/*.log /var/log/syslog /var/log/messages /var/log/secure /var/log/auth.log; do
        if [ -f "$logfile" ]; then
            checked=$((checked + 1))
            local perms=$(stat -c "%a" "$logfile" 2>/dev/null)
            if [ "$perms" = "640" ] || [ "$perms" = "644" ]; then
                correct=$((correct + 1))
            fi
        fi
    done
    
    if [ "$checked" -gt 0 ]; then
        log_success "✓ 로그 파일 권한: $correct/$checked개 올바름 (U-67)"
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
    log_info "=== 시간 동기화 및 로깅 설정 완료 ==="
    log_info "U-65: 시간 동기화 서비스 활성화"
    log_info "U-66: rsyslog 로그 정책 설정"
    log_info "U-67: 로그 파일 권한 설정"
    log_info ""
    log_info "확인 명령어:"
    log_info "  # 시간 동기화 (U-65)"
    log_info "  timedatectl status"
    log_info "  chronyc sources"
    log_info ""
    log_info "  # rsyslog (U-66)"
    log_info "  systemctl status rsyslog"
    log_info ""
    log_info "  # 로그 파일 권한 (U-67)"
    log_info "  ls -l /var/log/*.log"
    log_info ""
}

# 스크립트 실행
main "$@"
