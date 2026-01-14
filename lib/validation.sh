#!/bin/bash
# lib/validation.sh
# 검증 함수 라이브러리

# HTML 보고서 생성
generate_html_report() {
    local report_file=$1
    
    log_info "HTML 보고서 생성 중: $report_file"
    
    # 보고서 디렉토리 생성
    mkdir -p "$(dirname "$report_file")"
    
    cat > "$report_file" << 'EOF'
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>KISA 보안 가이드 점검 보고서</title>
    <style>
        body {
            font-family: 'Malgun Gothic', sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            padding: 30px;
            box-shadow: 0 0 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #2c3e50;
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
        }
        h2 {
            color: #34495e;
            margin-top: 30px;
        }
        .summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin: 20px 0;
        }
        .summary-box {
            padding: 20px;
            border-radius: 5px;
            text-align: center;
        }
        .summary-box.success {
            background-color: #d4edda;
            border: 1px solid #c3e6cb;
        }
        .summary-box.warning {
            background-color: #fff3cd;
            border: 1px solid #ffeaa7;
        }
        .summary-box.error {
            background-color: #f8d7da;
            border: 1px solid #f5c6cb;
        }
        .summary-box h3 {
            margin: 0 0 10px 0;
            font-size: 14px;
            color: #666;
        }
        .summary-box .number {
            font-size: 36px;
            font-weight: bold;
            color: #2c3e50;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        th {
            background-color: #3498db;
            color: white;
            font-weight: bold;
        }
        tr:hover {
            background-color: #f5f5f5;
        }
        .status {
            padding: 5px 10px;
            border-radius: 3px;
            font-weight: bold;
        }
        .status.success {
            background-color: #28a745;
            color: white;
        }
        .status.failed {
            background-color: #dc3545;
            color: white;
        }
        .status.skip {
            background-color: #6c757d;
            color: white;
        }
        .footer {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 1px solid #ddd;
            text-align: center;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔒 KISA 보안 가이드 점검 보고서</h1>
        <p><strong>생성 시간:</strong> $(date '+%Y-%m-%d %H:%M:%S')</p>
        <p><strong>호스트명:</strong> $(hostname)</p>
        <p><strong>OS 버전:</strong> $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo "Unknown")</p>
        
        <h2>📊 실행 요약</h2>
        <div class="summary">
            <div class="summary-box success">
                <h3>성공</h3>
                <div class="number">${MODULE_SUCCESS_COUNT:-0}</div>
            </div>
            <div class="summary-box error">
                <h3>실패</h3>
                <div class="number">${MODULE_FAIL_COUNT:-0}</div>
            </div>
            <div class="summary-box warning">
                <h3>건너뜀</h3>
                <div class="number">${MODULE_SKIP_COUNT:-0}</div>
            </div>
        </div>
        
        <h2>📋 모듈 실행 결과</h2>
        <table>
            <thead>
                <tr>
                    <th>항목코드</th>
                    <th>모듈명</th>
                    <th>상태</th>
                    <th>실행시간</th>
                    <th>타임스탬프</th>
                </tr>
            </thead>
            <tbody>
EOF

    # results.jsonl 읽어서 테이블 생성
    if [ -f "${LOG_BASE_DIR}/results.jsonl" ]; then
        while IFS= read -r line; do
            local module=$(echo "$line" | grep -o '"module":"[^"]*"' | cut -d'"' -f4)
            local status=$(echo "$line" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
            local duration=$(echo "$line" | grep -o '"duration":[0-9]*' | cut -d':' -f2)
            local timestamp=$(echo "$line" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4)
            
            local status_class="success"
            [ "$status" = "FAILED" ] && status_class="failed"
            [ "$status" = "SKIP" ] && status_class="skip"
            
            cat >> "$report_file" << TABLEROW
                <tr>
                    <td>$module</td>
                    <td>모듈명</td>
                    <td><span class="status $status_class">$status</span></td>
                    <td>${duration}초</td>
                    <td>$timestamp</td>
                </tr>
TABLEROW
        done < "${LOG_BASE_DIR}/results.jsonl"
    fi

    cat >> "$report_file" << 'EOF'
            </tbody>
        </table>
        
        <div class="footer">
            <p>KISA 보안 가이드 자동화 스크립트 v1.0</p>
            <p>2026 주요정보통신기반시설 기술적 취약점 분석·평가 방법 상세가이드</p>
        </div>
    </div>
</body>
</html>
EOF

    log_success "HTML 보고서 생성 완료: $report_file"
}

# JSON 보고서 생성
generate_json_report() {
    local report_file=$1
    
    log_info "JSON 보고서 생성 중: $report_file"
    
    # 보고서 디렉토리 생성
    mkdir -p "$(dirname "$report_file")"
    
    cat > "$report_file" << EOF
{
  "report_metadata": {
    "generated_at": "$(date -Iseconds)",
    "hostname": "$(hostname)",
    "os_version": "$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo 'Unknown')",
    "script_version": "1.0"
  },
  "summary": {
    "total_modules": $((MODULE_SUCCESS_COUNT + MODULE_FAIL_COUNT + MODULE_SKIP_COUNT)),
    "success_count": ${MODULE_SUCCESS_COUNT:-0},
    "failed_count": ${MODULE_FAIL_COUNT:-0},
    "skip_count": ${MODULE_SKIP_COUNT:-0}
  },
  "modules": [
EOF

    # results.jsonl 읽어서 JSON 배열 생성
    local first=true
    if [ -f "${LOG_BASE_DIR}/results.jsonl" ]; then
        while IFS= read -r line; do
            if [ "$first" = true ]; then
                first=false
            else
                echo "," >> "$report_file"
            fi
            echo "    $line" >> "$report_file"
        done < "${LOG_BASE_DIR}/results.jsonl"
    fi

    cat >> "$report_file" << EOF

  ]
}
EOF

    log_success "JSON 보고서 생성 완료: $report_file"
}