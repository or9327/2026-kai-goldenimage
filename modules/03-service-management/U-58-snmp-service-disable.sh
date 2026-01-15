#!/bin/bash
# modules/03-service-management/U-58-snmp-service-disable.sh
# DESC: SNMP 서비스 비활성화

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-58"
MODULE_NAME="SNMP 서비스 비활성화"
MODULE_CATEGORY="서비스 관리"
MODULE_SEVERITY="중"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# SNMP 서비스 목록
SNMP_SERVICES=(
    "snmpd"
    "snmptrapd"
)

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    local needs_update=false
    local active_services=""
    
    for service in "${SNMP_SERVICES[@]}"; do
        if systemctl list-units --all --type=service 2>/dev/null | grep -q "$service"; then
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                log_warning "$service: 활성화됨"
                active_services="${active_services} ${service}"
                needs_update=true
            else
                log_info "$service: 비활성화됨"
            fi
        fi
    done
    
    # 패키지 확인
    if dpkg -l | grep -qE "^ii.*snmpd"; then
        log_info "snmpd 패키지 설치됨"
    fi
    
    ACTIVE_SERVICES="$active_services"
    
    if [ "$needs_update" = false ]; then
        log_success "✓ SNMP 서비스가 비활성화됨"
        return 0
    else
        log_warning "설정 변경 필요"
        return 1
    fi
}

# 2. 백업 수행
perform_backup() {
    log_info "백업 단계 생략"
}

# 3. 설정 적용
apply_hardening() {
    log_info "보안 설정 적용 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] SNMP 서비스 비활성화 시뮬레이션"
        return 0
    fi
    
    if [ -z "$ACTIVE_SERVICES" ]; then
        log_info "활성화된 SNMP 서비스 없음"
        return 0
    fi
    
    local changes_made=false
    
    # Step 1: SNMP 서비스 비활성화
    log_info "Step 1: SNMP 서비스 비활성화"
    
    for service in "${SNMP_SERVICES[@]}"; do
        if systemctl list-units --all --type=service 2>/dev/null | grep -q "$service"; then
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
    
    # Step 2: snmpd 패키지 제거 (선택적)
    if [ "${REMOVE_SNMP_PACKAGE:-false}" = true ]; then
        log_info "Step 2: snmpd 패키지 제거"
        
        if dpkg -l | grep -q "^ii.*snmpd"; then
            if apt-get remove -y snmpd 2>/dev/null; then
                log_success "✓ snmpd 패키지 제거"
                changes_made=true
            fi
        fi
    else
        log_info "Step 2: snmpd 패키지 유지 (제거하려면 REMOVE_SNMP_PACKAGE=true)"
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
    
    for service in "${SNMP_SERVICES[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_error "✗ $service: 여전히 활성화됨"
            validation_failed=true
        else
            log_success "✓ $service: 비활성화됨"
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
        log_info "이미 보안 요구사항을 충족합니다"
        exit 0
    fi
    
    # 백업 생략
    
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
    log_info "=== SNMP 서비스 비활성화 완료 ==="
    log_info "SNMP는 네트워크 관리 프로토콜로 정보 노출 위험이 있습니다."
    log_info ""
    log_info "확인 명령어:"
    log_info "  systemctl status snmpd snmptrapd"
    log_info ""
    log_info "SNMP 서버로 사용하는 경우:"
    log_info "  - U-59: SNMP v3 사용 (인증 및 암호화)"
    log_info "  - U-60: Community String 복잡성 설정"
    log_info "  - U-61: SNMP 접근 제어 설정"
    log_info ""
    log_info "참고:"
    log_info "  - 클라우드 환경에서는 일반적으로 불필요"
    log_info "  - 모니터링은 CloudWatch 등 관리형 서비스 사용 권장"
    log_info ""
}

# 스크립트 실행
main "$@"
