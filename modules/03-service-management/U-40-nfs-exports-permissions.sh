#!/bin/bash
# modules/03-service-management/U-40-nfs-exports-permissions.sh
# DESC: /etc/exports 파일 권한 설정

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-40"
MODULE_NAME="NFS 접근 제한 (/etc/exports 권한)"
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
    
    # /etc/exports 파일 확인
    if [ ! -f /etc/exports ]; then
        log_success "✓ /etc/exports 파일 없음 (NFS 서버 미사용)"
        return 0
    fi
    
    local current_perms=$(stat -c "%a" /etc/exports 2>/dev/null)
    local current_owner=$(stat -c "%U" /etc/exports 2>/dev/null)
    local current_group=$(stat -c "%G" /etc/exports 2>/dev/null)
    
    log_info "/etc/exports: $current_owner:$current_group $current_perms"
    
    # 공유 설정 확인
    local export_count=$(grep -v "^#" /etc/exports | grep -v "^$" | wc -l)
    if [ "$export_count" -gt 0 ]; then
        log_info "공유 설정: $export_count개"
        
        # 보안 위험 옵션 확인
        if grep -qE "^\s*[^#].*\(.*no_root_squash" /etc/exports; then
            log_warning "⚠ no_root_squash 옵션 발견 (보안 위험)"
        fi
        
        if grep -qE "^\s*[^#].*\(.*rw.*\*" /etc/exports; then
            log_warning "⚠ 모든 호스트에 쓰기 권한 부여 (보안 위험)"
        fi
    else
        log_info "공유 설정: 없음 (GCP Filestore 사용 가능)"
    fi
    
    # 권한 확인
    if [ "$current_perms" = "644" ] && [ "$current_owner" = "root" ]; then
        log_success "✓ /etc/exports 권한 올바름"
        return 0
    else
        log_warning "/etc/exports 권한 변경 필요"
        return 1
    fi
}

# 2. 백업 수행
perform_backup() {
    log_info "설정 파일 백업 중..."
    
    if [ -f /etc/exports ]; then
        backup_file "/etc/exports" "$MODULE_ID"
    fi
}

# 3. 설정 적용
apply_hardening() {
    log_info "보안 설정 적용 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] /etc/exports 권한 설정 시뮬레이션"
        return 0
    fi
    
    # /etc/exports 파일이 없으면 생성하지 않음
    if [ ! -f /etc/exports ]; then
        log_info "/etc/exports 파일 없음 (생성하지 않음)"
        log_info "GCP Filestore를 사용하는 경우 이 파일은 필요하지 않습니다"
        return 0
    fi
    
    # Step 1: 파일 권한 설정
    log_info "Step 1: /etc/exports 권한 설정"
    
    # 소유자 변경
    chown root:root /etc/exports 2>/dev/null || chown root /etc/exports 2>/dev/null
    
    # 권한 변경
    if chmod 644 /etc/exports 2>/dev/null; then
        log_success "✓ /etc/exports: root:root 644"
    else
        log_error "✗ /etc/exports: 권한 변경 실패"
        return 1
    fi
    
    # Step 2: 설정 내용 검증 (경고만)
    log_info "Step 2: /etc/exports 내용 검증"
    
    local export_count=$(grep -v "^#" /etc/exports | grep -v "^$" | wc -l)
    
    if [ "$export_count" -eq 0 ]; then
        log_success "✓ 공유 설정 없음 (안전)"
    else
        log_info "공유 설정 발견: $export_count개"
        
        # 보안 검증
        local warnings=0
        
        # no_root_squash 확인
        if grep -qE "^\s*[^#].*\(.*no_root_squash" /etc/exports; then
            log_warning "⚠ no_root_squash 사용 중 (root 권한 유지)"
            warnings=$((warnings + 1))
        fi
        
        # 모든 호스트 접근 확인
        if grep -qE "^\s*/.*\s+\*\s*\(" /etc/exports; then
            log_warning "⚠ 모든 호스트에 접근 허용"
            warnings=$((warnings + 1))
        fi
        
        # rw 권한 확인
        if grep -qE "^\s*[^#].*\(.*rw" /etc/exports; then
            log_info "쓰기(rw) 권한이 부여된 공유 있음"
        fi
        
        if [ "$warnings" -gt 0 ]; then
            log_warning ""
            log_warning "보안 권장사항:"
            log_warning "  1. 특정 호스트만 허용: /shared 192.168.1.0/24(ro)"
            log_warning "  2. root_squash 사용 (기본값)"
            log_warning "  3. 읽기 전용 우선: (ro)"
            log_warning ""
        fi
    fi
    
    log_success "설정 적용 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 중..."
    
    # 파일이 없으면 성공
    if [ ! -f /etc/exports ]; then
        log_success "✓ /etc/exports 파일 없음"
        return 0
    fi
    
    local current_perms=$(stat -c "%a" /etc/exports)
    local current_owner=$(stat -c "%U" /etc/exports)
    
    if [ "$current_perms" = "644" ] && [ "$current_owner" = "root" ]; then
        log_success "✓ /etc/exports: root $current_perms"
        return 0
    else
        log_error "✗ /etc/exports: $current_owner $current_perms (예상: root 644)"
        return 1
    fi
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
    log_info "=== NFS 접근 제한 설정 완료 ==="
    log_info ""
    
    if [ -f /etc/exports ] && [ -s /etc/exports ]; then
        log_info "현재 환경: NFS 서버로 사용 중"
        log_info ""
        log_info "NFS 보안 권장사항:"
        log_info "  1. 특정 호스트만 허용"
        log_info "     /shared 192.168.1.100(ro,root_squash)"
        log_info ""
        log_info "  2. 네트워크 대역 지정"
        log_info "     /data 10.0.0.0/8(rw,sync,no_subtree_check)"
        log_info ""
        log_info "  3. 읽기 전용 우선 (ro)"
        log_info "  4. root_squash 사용 (기본값, 권장)"
        log_info ""
        log_info "설정 적용:"
        log_info "  sudo vi /etc/exports"
        log_info "  sudo exportfs -ra"
    else
        log_info "현재 환경: GCP Filestore 사용 (NFS 서버 미사용)"
        log_info ""
        log_info "GCP Filestore 사용 시:"
        log_info "  - VM은 NFS 클라이언트로만 동작"
        log_info "  - /etc/exports 파일 불필요"
        log_info "  - Filestore 콘솔에서 접근 제어 설정"
    fi
    
    log_info ""
    log_info "확인 명령어:"
    log_info "  # /etc/exports 권한"
    log_info "  ls -l /etc/exports"
    log_info ""
    log_info "  # 현재 공유 목록"
    log_info "  cat /etc/exports"
    log_info "  showmount -e localhost"
    log_info ""
}

# 스크립트 실행
main "$@"
