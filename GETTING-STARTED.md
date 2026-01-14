# KISA 보안 가이드 자동화 프로젝트 - 시작 가이드

## 📦 프로젝트 개요

이 프로젝트는 **2026 주요정보통신기반시설 기술적 취약점 분석·평가 방법 상세가이드**의 67개 보안 점검 항목을 Ubuntu 24.04 환경에서 자동으로 적용하는 Shell Script 기반 도구입니다.

## 🎯 현재 구현 상태

- ✅ 전체 프로젝트 구조 완성
- ✅ CSV 기반 항목 관리 시스템
- ✅ 자동 config 생성 도구
- ✅ 모듈 템플릿 및 실행 프레임워크
- ✅ 백업/복구 시스템
- ✅ 로깅 및 보고서 생성
- ⏳ U-01 모듈만 구현 완료 (1/67)
- ⏳ 나머지 66개 모듈 구현 대기

## 📂 주요 파일

1. **README.md** - 전체 프로젝트 문서
2. **KISA-ITEMS.md** - 67개 항목 목록 (Markdown)
3. **kisa-items.csv** - 67개 항목 목록 (CSV)
4. **config/modules.conf** - 모듈 활성화/비활성화 설정 (자동 생성)
5. **scripts/generate-modules-conf.sh** - modules.conf 자동 생성 스크립트

## 🚀 빠른 시작

### 1. 프로젝트 설정

```bash
# 프로젝트 디렉토리로 이동
cd kisa-hardening

# 실행 권한 부여
chmod +x *.sh
chmod +x scripts/*.sh
chmod +x lib/*.sh

# modules.conf 생성
./scripts/generate-modules-conf.sh
```

### 2. 모듈 추가 방법

#### Step 1: CSV에 정보 확인
`kisa-items.csv`에서 구현할 항목 확인

#### Step 2: 모듈 스크립트 작성
```bash
# 템플릿 복사
cp modules/01-account-management/U-01-root-remote-restriction.sh \
   modules/01-account-management/U-02-password-complexity.sh

# 스크립트 편집
vim modules/01-account-management/U-02-password-complexity.sh
```

#### Step 3: 모듈 정보 수정
```bash
MODULE_ID="U-02"
MODULE_NAME="비밀번호 관리정책 설정"
MODULE_CATEGORY="계정 관리"
MODULE_SEVERITY="상"
```

#### Step 4: 로직 구현
- `check_current_status()` - 현재 상태 확인
- `perform_backup()` - 백업 수행
- `apply_hardening()` - 보안 설정 적용
- `validate_settings()` - 설정 검증

#### Step 5: modules.conf 업데이트
```bash
# modules.conf 재생성
./scripts/generate-modules-conf.sh

# 또는 수동 편집
vim config/modules.conf
# U-02=enabled  # 활성화
```

#### Step 6: 테스트
```bash
# 드라이런으로 테스트
sudo ./kisa-hardening.sh -d -m U-02

# 실제 실행
sudo ./kisa-hardening.sh -m U-02
```

## 📋 다음 구현할 항목 (우선순위)

### 높은 우선순위 (상 중요도)
1. U-02: 비밀번호 관리정책 설정
2. U-03: 계정 잠금 임계값 설정
3. U-04: 비밀번호 파일 보호
4. U-05: root 이외의 UID가 '0' 금지
5. U-06: 사용자 계정 su 기능 제한

### 파일 및 디렉토리 (상 중요도)
- U-14 ~ U-28: 파일 권한 및 소유자 설정

### 서비스 관리 (상 중요도)
- U-34 ~ U-47: 불필요한 서비스 비활성화

## 🔧 개발 가이드

### 모듈 작성 규칙

1. **DESC 주석 필수**
   ```bash
   # DESC: 모듈 설명
   ```

2. **4단계 구조 준수**
   - check_current_status()
   - perform_backup()
   - apply_hardening()
   - validate_settings()

3. **드라이런 모드 지원**
   ```bash
   if [ "${DRY_RUN_MODE:-false}" = true ]; then
       log_info "[DRY RUN] 시뮬레이션"
       return 0
   fi
   ```

4. **상세한 로깅**
   ```bash
   log_info "작업 시작..."
   log_success "작업 완료"
   log_warning "주의사항"
   log_error "오류 발생"
   ```

### 테스트 체크리스트

- [ ] 드라이런 모드 동작 확인
- [ ] 백업 파일 생성 확인
- [ ] 설정 적용 확인
- [ ] 검증 통과 확인
- [ ] 에러 핸들링 확인
- [ ] 롤백 가능 확인

## 📊 진행률 추적

진행률은 `kisa-items.csv` 파일로 관리:
- CSV의 각 행이 하나의 점검 항목
- `config/modules.conf`에서 enabled/disabled 상태 확인
- 완료된 모듈은 해당 스크립트 파일이 `modules/` 디렉토리에 존재

**진행률 확인**:
```bash
# 자동으로 CSV 파일과 modules 디렉토리를 분석
./scripts/check-progress.sh

# 출력 예시:
# ╔════════════════════════════════════════════════════════╗
# ║           KISA 보안 가이드 구현 진행률                  ║
# ╚════════════════════════════════════════════════════════╝
# 
# 📊 카테고리별 진행률
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 카테고리                    완료    전체    진행률
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. 계정 관리                   1      13      7.7%
# ...
```

## 🤝 협업 워크플로우

1. **브랜치 생성**
   ```bash
   git checkout -b feature/U-XX-module-name
   ```

2. **모듈 구현**
   - CSV 확인
   - 스크립트 작성
   - 테스트 수행

3. **커밋**
   ```bash
   git add modules/XX-category/U-XX-*.sh
   git commit -m "feat: Add U-XX module - 항목명"
   ```

4. **진행률 확인**
   ```bash
   ./scripts/check-progress.sh
   ```

5. **PR 생성**
   - 테스트 결과 첨부
   - 체크리스트 완료 확인

## 📞 문의 및 지원

- Issue 트래커를 통한 문의
- Pull Request를 통한 기여

---

**시작하기**: 다음 명령어로 현재 상태 확인
```bash
./kisa-hardening.sh --list
```