#!/bin/bash
# lib/backup.sh
# 백업 함수 라이브러리

# 파일 백업
backup_file() {
    local file_path=$1
    local module_id=${2:-"unknown"}
    
    if [ ! -f "$file_path" ]; then
        log_warning "백업할 파일이 존재하지 않음: $file_path"
        return 1
    fi
    
    local backup_subdir="${BACKUP_DIR}/${module_id}"
    mkdir -p "$backup_subdir"
    
    local filename=$(basename "$file_path")
    local backup_path="${backup_subdir}/${filename}.$(date +%Y%m%d-%H%M%S)"
    
    if cp -p "$file_path" "$backup_path"; then
        log_success "백업 완료: $file_path -> $backup_path"
        echo "$backup_path" >> "${BACKUP_DIR}/backup_manifest.txt"
        return 0
    else
        log_error "백업 실패: $file_path"
        return 1
    fi
}

# 디렉토리 백업
backup_directory() {
    local dir_path=$1
    local module_id=${2:-"unknown"}
    
    if [ ! -d "$dir_path" ]; then
        log_warning "백업할 디렉토리가 존재하지 않음: $dir_path"
        return 1
    fi
    
    local backup_subdir="${BACKUP_DIR}/${module_id}"
    mkdir -p "$backup_subdir"
    
    local dirname=$(basename "$dir_path")
    local backup_path="${backup_subdir}/${dirname}.$(date +%Y%m%d-%H%M%S).tar.gz"
    
    if tar -czf "$backup_path" -C "$(dirname "$dir_path")" "$dirname" 2>/dev/null; then
        log_success "백업 완료: $dir_path -> $backup_path"
        echo "$backup_path" >> "${BACKUP_DIR}/backup_manifest.txt"
        return 0
    else
        log_error "백업 실패: $dir_path"
        return 1
    fi
}

# 백업 복원
restore_backup() {
    local backup_path=$1
    local target_path=$2
    
    if [ ! -f "$backup_path" ]; then
        log_error "백업 파일을 찾을 수 없음: $backup_path"
        return 1
    fi
    
    if [ -z "$target_path" ]; then
        log_error "복원 대상 경로가 지정되지 않음"
        return 1
    fi
    
    if cp -p "$backup_path" "$target_path"; then
        log_success "복원 완료: $backup_path -> $target_path"
        return 0
    else
        log_error "복원 실패"
        return 1
    fi
}

# 오래된 백업 정리
cleanup_old_backups() {
    local retention_days=${BACKUP_RETENTION_DAYS:-30}
    
    log_info "오래된 백업 정리 중 (${retention_days}일 이상)"
    
    find "$BACKUP_BASE_DIR" -type f -mtime +${retention_days} -delete 2>/dev/null
    find "$BACKUP_BASE_DIR" -type d -empty -delete 2>/dev/null
    
    log_success "백업 정리 완료"
}