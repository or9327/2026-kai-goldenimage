#!/bin/bash
# modules/03-service-management/U-42-43-44-unnecessary-services-disable.sh
# DESC: 불필요한 서비스 비활성화 (RPC/NIS/TFTP/Talk)

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-42-43-44"
MODULE_NAME="불필요한 서비스 비활성화"
MODULE_CATEGORY="서비스 관리"
MODULE_SEVERITY="중"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# 서비스 목록 (형식: "서비스명:모듈ID:설명")
declare -a SERVICES_TO_DISABLE=(
    # U-42: RPC 서비스 (rpcbind는 NFS 클라이언트에 필요할 수 있으므로 선택적)
    "rpc.statd:U-42:RPC statd"
    "rpc.mountd:U-42:RPC mountd"
    "rpc.lockd:U-42:RPC lockd"
    "rpc.rquotad:U-42:RPC rquotad"
    
    # U-43: NIS 서비스
    "ypserv:U-43:NIS 서버"
    "ypbind:U-43:NIS 클라이언트"
    "ypxfrd:U-43:NIS 맵 전송"
    "rpc.yppasswdd:U-43:NIS 비밀번호 변경"
    "rpc.ypupdated:U-43:NIS 업데이트"
    
    # U-44: TFTP/Talk 서비스
    "tftp:U-44:TFTP 서버"
    "tftpd:U-44:TFTP 데몬"
    "talk:U-44:Talk 서비스"
    "ntalk:U-44:Network Talk"
)

# rpcbind는 선택적으로만 비활성화
OPTIONAL_SERVICES=(
    "rpcbind:U-42:RPC 바인더 (NFS 클라이언트 필요)"
)

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    local needs_update=false
    local active_services=""
    
    # 필수 비활성화 서비스 확인
    log_info "Step 1: 불필요한 서비스 확인"
    
    for entry in "${SERVICES_TO_DISABLE[@]}"; do
        IFS=':' read -r service module_id desc <<< "$entry"
        
        if systemctl list-units --all --type=service 2>/dev/null | grep -q "$service"; then
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                log_warning "$service ($desc): 활성화됨"
                active_services="${active_services} ${service}"
                needs_update=true
            fi
        fi
    done
    
    # rpcbind 확인 (정보만)
    log_info "Step 2: 선택적 서비스 확인"
    
    if systemctl is-active --quiet rpcbind 2>/dev/null; then
        log_info "rpcbind: 활성화됨 (NFS 클라이언트 사용 시 필요)"
    fi
    
    ACTIVE_SERVICES="$active_services"
    
    if [ "$needs_update" = false ]; then
        log_success "✓ 불필요한 서비스가 비활성화됨"
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
    
    # xinetd 설정 백업
    for service in rpc.statd tftp talk ntalk; do
        if [ -f "/etc/xinetd.d/$service" ]; then
            backup_file "/etc/xinetd.d/$service" "$MODULE_ID"
        fi
    done
}

# 3. 설정 적용
apply_hardening() {
    log_info "보안 설정 적용 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] 서비스 비활성화 시뮬레이션"
        return 0
    fi
    
    local changes_made=false
    
    # Step 1: systemd 서비스 비활성화
    log_info "Step 1: systemd 서비스 비활성화"
    
    for entry in "${SERVICES_TO_DISABLE[@]}"; do
        IFS=':' read -r service module_id desc <<< "$entry"
        
        if systemctl list-units --all --type=service 2>/dev/null | grep -q "$service"; then
            # 서비스 중지
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                systemctl stop "$service" 2>/dev/null
                log_success "✓ $service 중지"
            fi
            
            # 서비스 비활성화
            if systemctl is-enabled --quiet "$service" 2>/dev/null; then
                systemctl disable "$service" 2>/dev/null
                log_success "✓ $service 비활성화 ($module_id)"
                changes_made=true
            fi
        fi
    done
    
    # Step 2: rpcbind 선택적 비활성화
    if [ "${DISABLE_RPCBIND:-false}" = true ]; then
        log_info "Step 2: rpcbind 비활성화 (선택적)"
        
        if systemctl is-active --quiet rpcbind 2>/dev/null; then
            systemctl stop rpcbind 2>/dev/null
            systemctl disable rpcbind 2>/dev/null
            log_success "✓ rpcbind 비활성화"
            changes_made=true
        fi
    else
        log_info "Step 2: rpcbind 유지 (GCP Filestore NFS 클라이언트에 필요할 수 있음)"
    fi
    
    # Step 3: inetd 설정 비활성화
    if [ -f /etc/inetd.conf ]; then
        log_info "Step 3: inetd 서비스 비활성화"
        
        # RPC 서비스 주석 처리
        sed -i '/^[^#].*rpc\./s/^/#/' /etc/inetd.conf
        
        # TFTP/Talk 서비스 주석 처리
        sed -i '/^[^#].*tftp/s/^/#/' /etc/inetd.conf
        sed -i '/^[^#].*talk/s/^/#/' /etc/inetd.conf
        sed -i '/^[^#].*ntalk/s/^/#/' /etc/inetd.conf
        
        # inetd 재시작
        if systemctl is-active --quiet inetd 2>/dev/null; then
            systemctl restart inetd 2>/dev/null
            log_success "✓ inetd 서비스 재시작"
        fi
        
        changes_made=true
    fi
    
    # Step 4: xinetd 설정 비활성화
    if [ -d /etc/xinetd.d ]; then
        log_info "Step 4: xinetd 서비스 비활성화"
        
        for service in rpc.statd tftp talk ntalk; do
            if [ -f "/etc/xinetd.d/$service" ]; then
                sed -i 's/disable.*=.*no/disable = yes/' "/etc/xinetd.d/$service"
                log_success "✓ $service (xinetd) 비활성화"
                changes_made=true
            fi
        done
        
        # xinetd 재시작
        if systemctl is-active --quiet xinetd 2>/dev/null; then
            systemctl restart xinetd 2>/dev/null
            log_success "✓ xinetd 서비스 재시작"
        fi
    fi
    
    # Step 5: 패키지 제거 (선택적)
    if [ "${REMOVE_PACKAGES:-false}" = true ]; then
        log_info "Step 5: 관련 패키지 제거"
        
        for pkg in nis tftp tftpd talk ntalk; do
            if dpkg -l | grep -q "^ii.*$pkg"; then
                apt-get remove -y "$pkg" 2>/dev/null && log_success "✓ $pkg 패키지 제거"
            fi
        done
        
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
    
    # 서비스 확인
    for entry in "${SERVICES_TO_DISABLE[@]}"; do
        IFS=':' read -r service module_id desc <<< "$entry"
        
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_error "✗ $service: 여전히 활성화됨"
            validation_failed=true
        fi
    done
    
    if [ "$validation_failed" = false ]; then
        log_success "✓ 모든 불필요한 서비스 비활성화됨"
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
    log_info "=== 불필요한 서비스 비활성화 완료 ==="
    log_info "다음 서비스들이 비활성화되었습니다:"
    log_info "  U-42: RPC 서비스 (rpc.statd, rpc.mountd 등)"
    log_info "  U-43: NIS 서비스 (ypserv, ypbind 등)"
    log_info "  U-44: TFTP/Talk 서비스"
    log_info ""
    log_info "확인 명령어:"
    log_info "  systemctl list-units | grep -E 'rpc|yp|tftp|talk'"
    log_info ""
    log_info "참고:"
    log_info "  - rpcbind는 기본적으로 유지됨 (NFS 클라이언트 필요)"
    log_info "  - 비활성화하려면: DISABLE_RPCBIND=true ./kisa-hardening.sh -m U-42"
    log_info ""
}

# 스크립트 실행
main "$@"
