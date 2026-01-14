#!/bin/bash
# modules/01-account-management/U-10-duplicate-uid-prohibition.sh
# DESC: 동일한 UID 금지

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-10"
MODULE_NAME="동일한 UID 금지"
MODULE_CATEGORY="계정 관리"
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
    
    if [ ! -f /etc/passwd ]; then
        log_error "/etc/passwd 파일을 찾을 수 없음"
        return 1
    fi
    
    # 중복 UID 확인
    log_info "Step 1: 중복 UID 검색 중..."
    
    # UID별로 카운트하여 2개 이상인 UID 찾기
    local duplicate_uids=$(awk -F: '{print $3}' /etc/passwd | sort | uniq -d)
    
    if [ -n "$duplicate_uids" ]; then
        log_warning "중복된 UID 발견:"
        
        echo "$duplicate_uids" | while read uid; do
            log_warning "  UID $uid:"
            awk -F: -v uid="$uid" '$3 == uid {print "    - " $1 " (UID:" $3 ")"}' /etc/passwd
        done
        
        # 전역 변수로 저장
        FOUND_DUPLICATE_UIDS="$duplicate_uids"
        
        log_warning "설정 변경 필요"
        return 1
    else
        log_success "✓ 중복된 UID 없음"
        return 0
    fi
}

# 2. 백업 수행
perform_backup() {
    log_info "설정 파일 백업 중..."
    
    backup_file "/etc/passwd" "$MODULE_ID"
    
    if [ -f /etc/shadow ]; then
        backup_file "/etc/shadow" "$MODULE_ID"
    fi
}

# 3. 설정 적용
apply_hardening() {
    log_info "보안 설정 적용 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] 중복 UID 변경 시뮬레이션"
        if [ -n "$FOUND_DUPLICATE_UIDS" ]; then
            echo "$FOUND_DUPLICATE_UIDS" | while read uid; do
                local accounts=$(awk -F: -v uid="$uid" '$3 == uid {print $1}' /etc/passwd)
                log_info "[DRY RUN] UID $uid를 가진 계정들: $accounts"
            done
        fi
        return 0
    fi
    
    if [ -z "$FOUND_DUPLICATE_UIDS" ]; then
        log_info "변경할 계정이 없습니다"
        return 0
    fi
    
    # Step 2: 중복 UID 변경
    log_info "Step 2: 중복 UID 변경 중..."
    
    # 사용 가능한 UID 시작점
    local next_uid=2000
    
    echo "$FOUND_DUPLICATE_UIDS" | while read uid; do
        # 해당 UID를 가진 계정들
        local accounts=$(awk -F: -v uid="$uid" '$3 == uid {print $1}' /etc/passwd)
        local account_count=$(echo "$accounts" | wc -l)
        
        log_info "UID $uid를 가진 계정: $account_count개"
        
        # 첫 번째 계정은 유지, 나머지만 변경
        local first_account=$(echo "$accounts" | head -1)
        local other_accounts=$(echo "$accounts" | tail -n +2)
        
        log_info "  유지: $first_account (UID: $uid)"
        
        echo "$other_accounts" | while read account; do
            # 중복되지 않는 UID 찾기
            while getent passwd "$next_uid" >/dev/null 2>&1; do
                next_uid=$((next_uid + 1))
            done
            
            log_info "  변경: $account (UID: $uid -> $next_uid)"
            
            # usermod로 UID 변경
            if usermod -u "$next_uid" "$account" 2>/dev/null; then
                log_success "    ✓ $account의 UID를 $next_uid로 변경"
                
                # 해당 UID로 소유된 파일 소유자 변경
                log_info "    파일 소유자 업데이트 중..."
                find / -user "$uid" -exec chown "$next_uid" {} \; 2>/dev/null &
                
                next_uid=$((next_uid + 1))
            else
                log_error "    ✗ $account: UID 변경 실패"
                return 1
            fi
        done
    done
    
    # 백그라운드 작업 완료 대기
    wait
    
    log_success "설정 적용 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 중..."
    
    local validation_failed=false
    
    # 중복 UID 재확인
    log_info "검증: 중복 UID 확인"
    
    local duplicate_uids=$(awk -F: '{print $3}' /etc/passwd | sort | uniq -d)
    
    if [ -z "$duplicate_uids" ]; then
        log_success "✓ 중복된 UID 없음"
    else
        log_error "✗ 여전히 중복된 UID가 존재:"
        echo "$duplicate_uids" | while read uid; do
            log_error "  UID $uid:"
            awk -F: -v uid="$uid" '$3 == uid {print "    - " $1}' /etc/passwd
        done
        validation_failed=true
    fi
    
    # 통계 출력
    local total_accounts=$(wc -l < /etc/passwd)
    local unique_uids=$(awk -F: '{print $3}' /etc/passwd | sort -u | wc -l)
    
    log_info "통계:"
    log_info "  전체 계정 수: $total_accounts"
    log_info "  고유 UID 수: $unique_uids"
    
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
    log_info "=== 중복 UID 제거 완료 ==="
    log_info "각 UID는 고유한 하나의 계정에만 할당됩니다."
    log_info ""
    log_info "확인 명령어:"
    log_info "  # 중복 UID 확인"
    log_info "  awk -F: '{print \$3}' /etc/passwd | sort | uniq -d"
    log_info ""
    log_info "  # UID별 계정 수"
    log_info "  awk -F: '{print \$3}' /etc/passwd | sort | uniq -c"
    log_info ""
}

# 스크립트 실행
main "$@"
