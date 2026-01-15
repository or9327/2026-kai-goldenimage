#!/bin/bash
# modules/03-service-management/U-49-dns-service-check.sh
# DESC: DNS 서비스 점검

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-49-50-51"
MODULE_NAME="DNS 서비스 보안 설정"
MODULE_CATEGORY="서비스 관리"
MODULE_SEVERITY="중"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# DNS 서비스 목록
DNS_SERVICES=(
    "named"
    "bind9"
)

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    local dns_found=false
    local dns_active=""
    
    for service in "${DNS_SERVICES[@]}"; do
        if systemctl list-units --all --type=service 2>/dev/null | grep -q "$service"; then
            dns_found=true
            
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                log_info "$service: 활성화됨"
                dns_active="$service"
                
                # BIND 버전 확인
                if command -v named &>/dev/null; then
                    local version=$(named -v 2>&1 | head -1)
                    log_info "  버전: $version"
                fi
            else
                log_info "$service: 설치되었으나 비활성화됨"
            fi
        fi
    done
    
    # 패키지 확인
    if dpkg -l | grep -qE "^ii.*(bind9|named)"; then
        log_info "BIND/DNS 패키지 설치됨"
    fi
    
    DNS_ACTIVE="$dns_active"
    
    if [ "$dns_found" = false ]; then
        log_success "✓ DNS 서비스 미설치"
        return 0
    elif [ -z "$dns_active" ]; then
        log_success "✓ DNS 서비스 비활성화됨"
        return 0
    else
        log_warning "DNS 서비스 활성화됨"
        return 1
    fi
}

# 2. 백업 수행
perform_backup() {
    log_info "설정 파일 백업 중..."
    
    local files_to_backup=(
        "/etc/bind/named.conf"
        "/etc/bind/named.conf.options"
        "/etc/named.conf"
    )
    
    for file in "${files_to_backup[@]}"; do
        if [ -f "$file" ]; then
            backup_file "$file" "$MODULE_ID"
        fi
    done
}

# 3. 설정 적용
apply_hardening() {
    log_info "DNS 서비스 분석 및 보안 설정 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] DNS 서비스 설정 시뮬레이션"
        return 0
    fi
    
    if [ -z "$DNS_ACTIVE" ]; then
        log_info "활성화된 DNS 서비스 없음"
        
        # BIND가 설치되어 있으면 설정 파일에 기본 보안 설정 추가
        if [ -f /etc/bind/named.conf.options ] || [ -f /etc/named.conf ]; then
            log_info "BIND 설정 파일 발견 - 기본 보안 설정 적용"
            apply_dns_security_settings
        fi
        
        return 0
    fi
    
    local changes_made=false
    
    # 자동 비활성화 옵션
    if [ "${AUTO_DISABLE_DNS:-false}" = true ]; then
        log_info "DNS 서비스 비활성화 중..."
        
        systemctl stop "$DNS_ACTIVE" 2>/dev/null
        systemctl disable "$DNS_ACTIVE" 2>/dev/null
        log_success "✓ $DNS_ACTIVE 비활성화"
    else
        log_warning ""
        log_warning "========================================="
        log_warning "DNS 서비스가 활성화되어 있습니다"
        log_warning "========================================="
        log_warning ""
        log_warning "현재 DNS 서비스: $DNS_ACTIVE"
        log_warning ""
        log_warning "이 서버를 DNS 서버로 사용하지 않는 경우 비활성화를 권장합니다."
        log_warning ""
        log_warning "비활성화 방법:"
        log_warning "  1. 수동 비활성화:"
        log_warning "     sudo systemctl stop $DNS_ACTIVE"
        log_warning "     sudo systemctl disable $DNS_ACTIVE"
        log_warning ""
        log_warning "  2. 자동 비활성화 (주의!):"
        log_warning "     sudo AUTO_DISABLE_DNS=true ./kisa-hardening.sh -m U-49"
        log_warning ""
        log_warning "DNS 서버로 사용하는 경우:"
        log_warning "  - BIND 최신 버전 유지 필수"
        log_warning "  - ISC 홈페이지: https://www.isc.org/downloads/"
        log_warning "  - 취약점 정보: https://kb.isc.org/v1/docs/en/aa-00913"
        log_warning ""
        
        # U-50, U-51: DNS 보안 설정 적용
        apply_dns_security_settings
        
        log_warning ""
    fi
    
    log_success "DNS 서비스 분석 및 보안 설정 완료"
}

# DNS 보안 설정 적용 함수 (U-50, U-51)
apply_dns_security_settings() {
    log_info "Step: DNS 보안 설정 적용 (U-50, U-51)"
    
    local named_conf_options=""
    local named_conf=""
    
    # 설정 파일 찾기
    if [ -f /etc/bind/named.conf.options ]; then
        named_conf_options="/etc/bind/named.conf.options"
    fi
    
    if [ -f /etc/bind/named.conf ]; then
        named_conf="/etc/bind/named.conf"
    elif [ -f /etc/named.conf ]; then
        named_conf="/etc/named.conf"
    fi
    
    if [ -z "$named_conf_options" ] && [ -z "$named_conf" ]; then
        log_info "BIND 설정 파일 없음 - 스킵"
        return 0
    fi
    
    local config_file="$named_conf_options"
    [ -z "$config_file" ] && config_file="$named_conf"
    
    local changes_made=false
    
    # U-50: Zone Transfer 제한
    if ! grep -q "allow-transfer" "$config_file" 2>/dev/null; then
        log_info "U-50: allow-transfer 설정 추가"
        
        # options 블록 찾기
        if grep -q "^options {" "$config_file"; then
            # options 블록 내부에 추가
            sed -i '/^options {/a\    # KISA U-50: Zone Transfer 차단\n    allow-transfer { none; };' "$config_file"
        else
            # options 블록 생성
            cat >> "$config_file" << 'EOF'

# KISA U-50, U-51: DNS 보안 설정
options {
    # U-50: Zone Transfer 차단
    allow-transfer { none; };
};
EOF
        fi
        
        log_success "✓ allow-transfer { none; } 설정"
        changes_made=true
    else
        log_info "✓ allow-transfer 이미 설정됨 (U-50)"
    fi
    
    # U-51: 동적 업데이트 제한
    if ! grep -q "allow-update" "$config_file" 2>/dev/null; then
        log_info "U-51: allow-update 설정 추가"
        
        # options 블록 내부에 추가
        if grep -q "^options {" "$config_file"; then
            sed -i '/allow-transfer/a\    # KISA U-51: 동적 업데이트 차단\n    allow-update { none; };' "$config_file"
        else
            # allow-transfer 설정이 없는 경우
            sed -i '/^options {/a\    # KISA U-51: 동적 업데이트 차단\n    allow-update { none; };' "$config_file"
        fi
        
        log_success "✓ allow-update { none; } 설정"
        changes_made=true
    else
        log_info "✓ allow-update 이미 설정됨 (U-51)"
    fi
    
    # 설정 검증
    if [ "$changes_made" = true ]; then
        # named-checkconf로 설정 검증
        if command -v named-checkconf &>/dev/null; then
            if named-checkconf 2>/dev/null; then
                log_success "✓ BIND 설정 파일 검증 성공"
                
                # DNS 서비스 재시작
                if [ -n "$DNS_ACTIVE" ] && systemctl is-active --quiet "$DNS_ACTIVE" 2>/dev/null; then
                    systemctl restart "$DNS_ACTIVE" 2>/dev/null
                    log_success "✓ DNS 서비스 재시작"
                fi
            else
                log_error "✗ BIND 설정 파일 오류"
                return 1
            fi
        fi
    fi
    
    log_info ""
    log_info "DNS 보안 설정 완료:"
    log_info "  U-50: Zone Transfer 차단 (allow-transfer { none; })"
    log_info "  U-51: 동적 업데이트 차단 (allow-update { none; })"
    log_info ""
    log_info "필요 시 수동으로 IP 추가:"
    log_info "  sudo vi $config_file"
    log_info "  # allow-transfer { 192.168.1.10; };"
    log_info "  # allow-update { 192.168.1.0/24; };"
    log_info "  sudo systemctl restart named"
    log_info ""
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 중..."
    
    local validation_failed=false
    
    # BIND 설정 파일 확인
    for config_file in /etc/bind/named.conf.options /etc/bind/named.conf /etc/named.conf; do
        if [ -f "$config_file" ]; then
            # U-50: allow-transfer 확인
            if grep -q "allow-transfer" "$config_file"; then
                log_success "✓ allow-transfer 설정됨 (U-50)"
            else
                log_warning "⚠ allow-transfer 미설정 (U-50)"
            fi
            
            # U-51: allow-update 확인
            if grep -q "allow-update" "$config_file"; then
                log_success "✓ allow-update 설정됨 (U-51)"
            else
                log_warning "⚠ allow-update 미설정 (U-51)"
            fi
            
            break
        fi
    done
    
    if [ "$validation_failed" = true ]; then
        return 1
    fi
    
    return 0
}

# 메인 실행 흐름
main() {
    # 현재 상태 확인
    if check_current_status; then
        log_info "DNS 서비스가 없거나 비활성화되어 있습니다"
        
        # BIND 설정 파일이 있으면 보안 설정 적용
        if [ -f /etc/bind/named.conf.options ] || [ -f /etc/bind/named.conf ] || [ -f /etc/named.conf ]; then
            log_info "BIND 설정 파일 발견 - 기본 보안 설정 적용"
            
            # 백업 수행
            if [ "${SKIP_BACKUP:-false}" != true ]; then
                perform_backup
            fi
            
            # 보안 설정 적용
            if ! apply_hardening; then
                log_error "설정 적용 실패"
                exit 1
            fi
            
            # 드라이런 모드에서는 검증 스킵
            if [ "${DRY_RUN_MODE:-false}" != true ]; then
                validate_settings
            fi
        fi
        
        exit 0
    fi
    
    # 백업 수행
    if [ "${SKIP_BACKUP:-false}" != true ]; then
        perform_backup
    fi
    
    # 분석 수행
    if ! apply_hardening; then
        log_error "분석 실패"
        exit 1
    fi
    
    log_success "[$MODULE_ID] $MODULE_NAME - 완료"
    
    # 추가 안내
    log_info ""
    log_info "=== DNS 서비스 보안 설정 완료 ==="
    log_info "U-49: DNS 서비스 점검"
    log_info "U-50: Zone Transfer 제한"
    log_info "U-51: 동적 업데이트 제한"
    log_info ""
    log_info "적용된 기본 보안 설정:"
    log_info "  - allow-transfer { none; } (모든 Zone Transfer 차단)"
    log_info "  - allow-update { none; } (모든 동적 업데이트 차단)"
    log_info ""
    log_info "DNS 서버 사용 여부 판단:"
    log_info "  - DNS 서버 아님: 비활성화 권장"
    log_info "  - DNS 서버 사용: 보안 설정 적용됨, 필요 시 IP 추가"
    log_info ""
    log_info "확인 명령어:"
    log_info "  # DNS 서비스 상태"
    log_info "  systemctl status named bind9"
    log_info ""
    log_info "  # BIND 버전"
    log_info "  named -v"
    log_info ""
    log_info "  # Zone Transfer 설정 확인"
    log_info "  grep allow-transfer /etc/bind/named.conf.options"
    log_info ""
    log_info "  # 동적 업데이트 설정 확인"
    log_info "  grep allow-update /etc/bind/named.conf.options"
    log_info ""
}

# 스크립트 실행
main "$@"
