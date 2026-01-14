# 테스트 및 실행 가이드

## 🧪 로컬 테스트 방법

프로젝트를 다운로드하고 로컬 Ubuntu 24.04 환경에서 테스트하는 방법입니다.

### 1. 프로젝트 설정

```bash
# 프로젝트 디렉토리로 이동
cd kisa-hardening

# 실행 권한 부여
chmod +x kisa-hardening.sh
chmod +x scripts/generate-modules-conf.sh
chmod +x lib/*.sh
chmod +x modules/*/*.sh

# modules.conf 생성 (CSV 기반)
./scripts/generate-modules-conf.sh
```

### 2. 드라이런 테스트

실제 시스템을 변경하지 않고 시뮬레이션만 수행합니다.

```bash
# 전체 드라이런
sudo ./kisa-hardening.sh --dry-run

# 특정 모듈 드라이런
sudo ./kisa-hardening.sh -d -m U-01

# 특정 카테고리 드라이런
sudo ./kisa-hardening.sh -d -c 01-account-management
```

### 3. 모듈 목록 확인

```bash
# 사용 가능한 모듈 목록
./kisa-hardening.sh --list

# 출력 예시:
# === 사용 가능한 KISA 보안 모듈 ===
#
# [01-account-management] 계정 관리
#   [활성] U-01-root-remote-restriction - Root 계정 원격 접속 제한
#   [비활성] U-02-password-complexity - 비밀번호 관리정책 설정
#   ...
```

### 4. 단일 모듈 실행

```bash
# U-01 모듈만 실행
sudo ./kisa-hardening.sh -m U-01

# 대화형 모드로 실행 (각 단계마다 확인)
sudo ./kisa-hardening.sh -i -m U-01
```

### 5. 로그 및 결과 확인

```bash
# 실시간 로그 확인
tail -f /var/log/kisa-hardening/kisa-hardening-*.log

# 결과 JSON 확인
cat /var/log/kisa-hardening/results.jsonl

# HTML 보고서 확인
ls -la /var/log/kisa-hardening/reports/

# 백업 확인
ls -la /root/kisa-backup/
```

## 🔍 문제 해결

### 오류: "No such file or directory" (로그 디렉토리)

**원인**: 로그 디렉토리가 생성되지 않음

**해결**:
```bash
sudo mkdir -p /var/log/kisa-hardening
sudo mkdir -p /var/log/kisa-hardening/reports
sudo mkdir -p /root/kisa-backup
```

### 오류: "Permission denied"

**원인**: root 권한 없음

**해결**:
```bash
# sudo로 실행
sudo ./kisa-hardening.sh
```

### 오류: "Command not found: sshd"

**원인**: OpenSSH 서버가 설치되지 않음

**해결**:
```bash
sudo apt-get update
sudo apt-get install openssh-server
```

### SSH 접속 불가

**원인**: PermitRootLogin 설정 후 root 접속 차단됨

**해결**:
```bash
# 1. 현재 세션 유지
# 2. 새 세션에서 일반 사용자로 접속
ssh user@server

# 3. sudo로 root 권한 획득
sudo su -

# 4. 필요시 백업에서 복원
sudo cp /root/kisa-backup/TIMESTAMP/U-01/sshd_config.* /etc/ssh/sshd_config
sudo systemctl restart sshd
```

## ✅ 검증 체크리스트

### U-01 모듈 검증

```bash
# 1. SSH PermitRootLogin 확인
sudo sshd -T | grep permitrootlogin
# 예상 출력: permitrootlogin no

# 2. Telnet 서비스 확인
systemctl status telnetd
# 예상 출력: Unit telnetd.service could not be found.

# 3. 백업 파일 확인
ls -la /root/kisa-backup/*/U-01/
# sshd_config 백업 파일이 존재해야 함

# 4. 로그 확인
tail -20 /var/log/kisa-hardening/kisa-hardening-*.log
# SUCCESS 메시지 확인
```

## 📋 실행 시나리오

### 시나리오 1: 첫 실행 (프로덕션 전 테스트)

```bash
# Step 1: 드라이런으로 영향 확인
sudo ./kisa-hardening.sh -d

# Step 2: 백업 확인
ls /root/kisa-backup/

# Step 3: 단일 모듈 테스트
sudo ./kisa-hardening.sh -m U-01

# Step 4: 결과 확인
cat /var/log/kisa-hardening/results.jsonl

# Step 5: SSH 접속 테스트 (별도 세션)
ssh root@localhost  # 거부되어야 함
ssh user@localhost  # 허용되어야 함
```

### 시나리오 2: 카테고리별 단계 적용

```bash
# 1일차: 계정 관리
sudo ./kisa-hardening.sh -c 01-account-management

# 2일차: 파일 및 디렉토리
sudo ./kisa-hardening.sh -c 02-file-directory

# 3일차: 서비스 관리
sudo ./kisa-hardening.sh -c 03-service-management

# ...
```

### 시나리오 3: 대화형 모드 (운영자 확인)

```bash
# 각 모듈마다 확인 후 실행
sudo ./kisa-hardening.sh -i -c 01-account-management

# 출력 예시:
# ═══════════════════════════════════════
#   모듈 실행: U-01-root-remote-restriction
# ═══════════════════════════════════════
# [INFO] 모듈을 실행하시겠습니까? [y/N]: y
# [INFO] 설정 적용 중...
```

## 🎯 다음 단계

1. **U-01 검증 완료 후**
   - KISA-ITEMS.md 업데이트 (⏳ → ✓)
   - 다음 모듈 (U-02) 구현 시작

2. **U-02 구현 시**
   ```bash
   # 템플릿 복사
   cp modules/01-account-management/U-01-root-remote-restriction.sh \
      modules/01-account-management/U-02-password-complexity.sh
   
   # 편집
   vim modules/01-account-management/U-02-password-complexity.sh
   
   # modules.conf 업데이트
   sed -i 's/^U-02=disabled/U-02=enabled/' config/modules.conf
   
   # 테스트
   sudo ./kisa-hardening.sh -d -m U-02
   sudo ./kisa-hardening.sh -m U-02
   ```

3. **주기적 실행 설정**
   ```bash
   # cron 등록 (예: 매월 1일 실행)
   sudo crontab -e
   # 0 2 1 * * /path/to/kisa-hardening/kisa-hardening.sh >> /var/log/kisa-hardening/cron.log 2>&1
   ```

## 📞 지원

문제가 발생하면:
1. 로그 파일 확인: `/var/log/kisa-hardening/`
2. 백업 위치 확인: `/root/kisa-backup/`
3. Issue 등록: GitHub 프로젝트 페이지

---

**중요**: 프로덕션 적용 전 반드시 테스트 환경에서 충분히 검증하세요!