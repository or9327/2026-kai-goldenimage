#!/bin/bash
# modules/01-account-management/U-13-password-encryption-algorithm.sh
# DESC: 패스워드 암호화 알고리즘 설정

# 현재 스크립트 디렉토리
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 공통 라이브러리 로드
source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/lib/logging.sh"
source "${ROOT_DIR}/lib/backup.sh"

# 모듈 정보
MODULE_ID="U-13"
MODULE_NAME="패스워드 암호화 알고리즘 설정"
MODULE_CATEGORY="계정 관리"
MODULE_SEVERITY="중"

# 모듈 시작
log_info "[$MODULE_ID] $MODULE_NAME"

# 드라이런 모드 확인
if [ "${DRY_RUN_MODE:-false}" = true ]; then
    log_info "[DRY RUN] 시뮬레이션 모드"
fi

# 권장 암호화 알고리즘 (우선순위 순)
PREFERRED_ALGORITHMS="yescrypt sha512 sha256"

# 1. 현재 상태 확인
check_current_status() {
    log_info "현재 상태 확인 중..."
    
    local needs_update=false
    
    # Step 1: /etc/shadow 파일 확인 (현재 사용 중인 알고리즘)
    log_info "Step 1: 현재 암호화 알고리즘 확인"
    
    if [ -f /etc/shadow ]; then
        # $6$ = SHA-512, $y$ = yescrypt, $5$ = SHA-256
        local algo_count_yescrypt=$(grep -c '^\w*:\$y\$' /etc/shadow 2>/dev/null || echo 0)
        local algo_count_sha512=$(grep -c '^\w*:\$6\$' /etc/shadow 2>/dev/null || echo 0)
        local algo_count_sha256=$(grep -c '^\w*:\$5\$' /etc/shadow 2>/dev/null || echo 0)
        local algo_count_md5=$(grep -c '^\w*:\$1\$' /etc/shadow 2>/dev/null || echo 0)
        
        log_info "현재 사용 중인 암호화 알고리즘:"
        log_info "  yescrypt (\$y\$): $algo_count_yescrypt 계정"
        log_info "  SHA-512 (\$6\$): $algo_count_sha512 계정"
        log_info "  SHA-256 (\$5\$): $algo_count_sha256 계정"
        log_info "  MD5 (\$1\$): $algo_count_md5 계정"
        
        if [ "$algo_count_md5" -gt 0 ]; then
            log_warning "⚠ MD5 알고리즘 사용 계정 발견 (취약)"
        fi
    fi
    
    # Step 2: /etc/login.defs 확인
    if [ -f /etc/login.defs ]; then
        local current_method=$(grep "^ENCRYPT_METHOD" /etc/login.defs | awk '{print $2}')
        log_info "/etc/login.defs의 ENCRYPT_METHOD: ${current_method:-없음}"
        
        if [ -z "$current_method" ] || [ "$current_method" = "DES" ] || [ "$current_method" = "MD5" ]; then
            needs_update=true
        fi
    else
        log_warning "/etc/login.defs 파일이 없음"
        needs_update=true
    fi
    
    # Step 3: /etc/pam.d/common-password 확인
    if [ -f /etc/pam.d/common-password ]; then
        if grep -q "pam_unix.so.*sha512\|pam_unix.so.*yescrypt" /etc/pam.d/common-password; then
            log_success "✓ PAM에서 안전한 알고리즘 사용 중"
        else
            log_warning "PAM 설정 확인 필요"
            needs_update=true
        fi
    fi
    
    if [ "$needs_update" = false ]; then
        log_success "✓ 안전한 암호화 알고리즘이 설정됨"
        return 0
    else
        log_warning "설정 변경 필요"
        return 1
    fi
}

# 2. 백업 수행
perform_backup() {
    log_info "설정 파일 백업 중..."
    
    if [ -f /etc/login.defs ]; then
        backup_file "/etc/login.defs" "$MODULE_ID"
    fi
    
    if [ -f /etc/pam.d/common-password ]; then
        backup_file "/etc/pam.d/common-password" "$MODULE_ID"
    fi
}

# 3. 설정 적용
apply_hardening() {
    log_info "보안 설정 적용 중..."
    
    # 드라이런 모드
    if [ "${DRY_RUN_MODE:-false}" = true ]; then
        log_info "[DRY RUN] 암호화 알고리즘 설정 시뮬레이션"
        return 0
    fi
    
    # 사용 가능한 최선의 알고리즘 선택
    local selected_algo=""
    
    for algo in $PREFERRED_ALGORITHMS; do
        # yescrypt 지원 확인 (Ubuntu 22.04+)
        if [ "$algo" = "yescrypt" ]; then
            if getent passwd root | grep -q '\$y\$' 2>/dev/null || \
               grep -q "rounds" /etc/pam.d/common-password 2>/dev/null; then
                selected_algo="yescrypt"
                break
            fi
        elif [ "$algo" = "sha512" ]; then
            selected_algo="SHA512"
            break
        elif [ "$algo" = "sha256" ]; then
            selected_algo="SHA256"
            break
        fi
    done
    
    # 기본값은 SHA512
    if [ -z "$selected_algo" ]; then
        selected_algo="SHA512"
    fi
    
    log_info "선택된 암호화 알고리즘: $selected_algo"
    
    # Step 2: /etc/login.defs 설정
    log_info "Step 2: /etc/login.defs 설정 중..."
    
    if [ -f /etc/login.defs ]; then
        # 기존 ENCRYPT_METHOD 제거
        sed -i '/^ENCRYPT_METHOD/d' /etc/login.defs
        
        # 새 설정 추가
        echo "" >> /etc/login.defs
        echo "# KISA Security Guide: U-13 - Password Encryption Algorithm" >> /etc/login.defs
        echo "ENCRYPT_METHOD ${selected_algo}" >> /etc/login.defs
        
        log_success "✓ /etc/login.defs 설정 완료"
    else
        log_error "/etc/login.defs 파일이 없습니다"
        return 1
    fi
    
    # Step 3: /etc/pam.d/common-password 설정
    log_info "Step 3: /etc/pam.d/common-password 설정 중..."
    
    if [ -f /etc/pam.d/common-password ]; then
        # pam_unix.so 라인에 알고리즘 추가
        local pam_algo=$(echo "$selected_algo" | tr '[:upper:]' '[:lower:]')
        
        # 기존 알고리즘 옵션 제거 (md5, sha256, sha512, yescrypt 등)
        sed -i 's/\(pam_unix.so.*\)\(md5\|sha256\|sha512\|yescrypt\)/\1/g' /etc/pam.d/common-password
        
        # 새 알고리즘 추가
        if grep -q "^password.*pam_unix.so" /etc/pam.d/common-password; then
            # yescrypt는 특별 처리 (rounds 옵션 필요)
            if [ "$pam_algo" = "yescrypt" ]; then
                sed -i 's/\(^password.*pam_unix.so.*\)/\1 yescrypt rounds=11/' /etc/pam.d/common-password
            else
                sed -i "s/\(^password.*pam_unix.so.*\)/\1 $pam_algo/" /etc/pam.d/common-password
            fi
            log_success "✓ /etc/pam.d/common-password 설정 완료"
        else
            log_warning "pam_unix.so 설정을 찾을 수 없습니다"
        fi
    else
        log_warning "/etc/pam.d/common-password 파일이 없습니다"
    fi
    
    log_success "설정 적용 완료"
}

# 4. 설정 검증
validate_settings() {
    log_info "설정 검증 중..."
    
    local validation_failed=false
    
    # /etc/login.defs 검증
    if [ -f /etc/login.defs ]; then
        local encrypt_method=$(grep "^ENCRYPT_METHOD" /etc/login.defs | awk '{print $2}')
        
        if [ "$encrypt_method" = "SHA512" ] || \
           [ "$encrypt_method" = "SHA256" ] || \
           [ "$encrypt_method" = "yescrypt" ]; then
            log_success "✓ ENCRYPT_METHOD: $encrypt_method"
        else
            log_error "✗ ENCRYPT_METHOD: ${encrypt_method:-없음} (예상: SHA512/SHA256/yescrypt)"
            validation_failed=true
        fi
    fi
    
    # /etc/pam.d/common-password 검증
    if [ -f /etc/pam.d/common-password ]; then
        if grep -q "pam_unix.so.*sha512\|pam_unix.so.*sha256\|pam_unix.so.*yescrypt" /etc/pam.d/common-password; then
            log_success "✓ PAM에서 안전한 암호화 알고리즘 사용"
        else
            log_warning "⚠ PAM 설정 확인 필요"
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
    log_info "=== 암호화 알고리즘 설정 완료 ==="
    log_info "향후 생성되는 모든 계정에 안전한 암호화 알고리즘이 적용됩니다."
    log_info ""
    log_info "알고리즘 식별자:"
    log_info "  \$y\$ = yescrypt (최신, Ubuntu 22.04+)"
    log_info "  \$6\$ = SHA-512 (권장)"
    log_info "  \$5\$ = SHA-256 (허용)"
    log_info "  \$1\$ = MD5 (취약, 사용 금지)"
    log_info ""
    log_info "확인 명령어:"
    log_info "  # 현재 설정 확인"
    log_info "  grep ENCRYPT_METHOD /etc/login.defs"
    log_info ""
    log_info "  # 계정별 암호화 알고리즘 확인"
    log_info "  sudo cut -d: -f1,2 /etc/shadow | head -5"
    log_info ""
    log_info "참고:"
    log_info "  - 기존 계정 비밀번호는 자동 변경되지 않음"
    log_info "  - 비밀번호 변경 시 새 알고리즘 적용"
    log_info "  - 기존 계정 강제 재설정: passwd <username>"
    log_info ""
}

# 스크립트 실행
main "$@"
