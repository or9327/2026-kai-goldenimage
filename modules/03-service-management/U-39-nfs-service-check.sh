#!/bin/bash
# modules/03-service-management/U-39-nfs-service-check.sh
# DESC: NFS 서비스 점검 (불필요 시 비활성화 권장)

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-39"
MODULE_NAME="NFS 서비스 점검"
MODULE_CATEGORY="서비스 관리"
MODULE_SEVERITY="중"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# NFS 관련 서비스
NFS_SERVICES=(
    "nfs-server"
    "nfs-kernel-server"
    "rpcbind"
    "nfs-mountd"
    "nfs-idmapd"
)

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    local nfs_active=false
    local active_services=""
    
    # NFS 서비스 확인
    log_info "Step 1: NFS 관련 서비스 확인"
    
    for service in "${NFS_SERVICES[@]}"; do
        if systemctl list-units --all --type=service 2>/dev/null | grep -q "$service"; then
            local status="비활성화"
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                status="활성화"
                nfs_active=true
                active_services="${active_services} ${service}"
            fi
            
            local enabled="disabled"
            if systemctl is-enabled --quiet "$service" 2>/dev/null; then
                enabled="enabled"
            fi
            
            log_info "  $service: $status ($enabled)"
        fi
    done
    
    # NFS 패키지 설치 확인
    if dpkg -l | grep -qE "^ii.*nfs-kernel-server|^ii.*nfs-common"; then
        log_info "NFS 패키지가 설치되어 있습니다"
    fi
    
    # /etc/exports 확인
    if [ -f /etc/exports ]; then
        local export_count=$(grep -v "^#" /etc/exports | grep -v "^$" | wc -l)
        if [ "$export_count" -gt 0 ]; then
            log_info "/etc/exports에 $export_count개의 공유 설정이 있습니다"
        fi
    fi
    
    ACTIVE_SERVICES="$active_services"
    NFS_ACTIVE="$nfs_active"
    
    if [ "$nfs_active" = false ]; then
        log_success "✓ NFS 서비스가 비활성화됨"
        return 0
    else
        log_warning "NFS 서비스가 활성화됨"
        return 1
    fi
}

# 2. 백업 수행
perform_backup() {
    log_info "백업 단계 생략 (검증 전용 모듈)"
}

# 3. 설정 적용
apply_hardening() {
    log_info "NFS 서비스 분석 중..."
    
    if [ "$NFS_ACTIVE" = false ]; then
        log_info "NFS 서비스가 비활성화되어 있습니다"
        return 0
    fi
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] NFS 서비스 비활성화 시뮬레이션"
        if [ -n "$ACTIVE_SERVICES" ]; then
            for service in $ACTIVE_SERVICES; do
                log_info "[DRY RUN] $service 비활성화 예정"
            done
        fi
        return 0
    fi
    
    # 자동 비활성화 옵션
    if [ "${AUTO_DISABLE_NFS:-false}" = true ]; then
        log_info "NFS 서비스 비활성화 중..."
        
        for service in $ACTIVE_SERVICES; do
            # 서비스 중지
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                systemctl stop "$service" 2>/dev/null
                log_success "✓ $service 중지"
            fi
            
            # 서비스 비활성화
            if systemctl is-enabled --quiet "$service" 2>/dev/null; then
                systemctl disable "$service" 2>/dev/null
                log_success "✓ $service 비활성화"
            fi
        done
    else
        log_warning ""
        log_warning "========================================="
        log_warning "NFS 서비스가 활성화되어 있습니다"
        log_warning "========================================="
        log_warning ""
        log_warning "NFS 서비스를 사용하지 않는 경우 비활성화를 권장합니다."
        log_warning ""
        log_warning "활성화된 서비스:"
        for service in $ACTIVE_SERVICES; do
            log_warning "  - $service"
        done
        log_warning ""
        log_warning "비활성화 방법:"
        log_warning "  1. 수동 비활성화:"
        for service in $ACTIVE_SERVICES; do
            log_warning "     sudo systemctl stop $service"
            log_warning "     sudo systemctl disable $service"
        done
        log_warning ""
        log_warning "  2. 자동 비활성화 (주의!):"
        log_warning "     sudo AUTO_DISABLE_NFS=true ./kisa-hardening.sh -m U-39"
        log_warning ""
        log_warning "참고:"
        log_warning "  - NFS가 필요한 경우 U-40에서 접근 제한을 설정하세요"
        log_warning "  - 파일 서버, 컨테이너 환경 등에서는 NFS가 필요할 수 있습니다"
        log_warning ""
    fi
    
    log_success "NFS 서비스 분석 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 생략 (검증 전용 모듈)"
    return 0
}

# 메인 실행 흐름
main() {
    # 현재 상태 확인
    if check_current_status; then
        log_info "NFS 서비스가 비활성화되어 있습니다"
        exit 0
    fi
    
    # 백업 생략 (검증 전용)
    
    # 분석 수행
    if ! apply_hardening; then
        log_error "분석 실패"
        exit 1
    fi
    
    log_success "[$MODULE_ID] $MODULE_NAME - 완료"
    
    # 추가 안내
    log_info ""
    log_info "=== NFS 서비스 점검 완료 ==="
    log_info "이 모듈은 NFS 서비스를 검증만 합니다."
    log_info ""
    log_info "NFS 사용 여부 판단 기준:"
    log_info "  - 파일 서버: NFS 필요"
    log_info "  - 컨테이너/K8s: NFS 필요할 수 있음"
    log_info "  - 일반 서버: NFS 불필요"
    log_info "  - 웹 서버: NFS 불필요"
    log_info ""
    log_info "확인 명령어:"
    log_info "  # NFS 서비스 상태"
    log_info "  systemctl status nfs-server nfs-kernel-server"
    log_info ""
    log_info "  # NFS 공유 목록"
    log_info "  cat /etc/exports"
    log_info "  showmount -e localhost"
    log_info ""
}

# 스크립트 실행
main "$@"
