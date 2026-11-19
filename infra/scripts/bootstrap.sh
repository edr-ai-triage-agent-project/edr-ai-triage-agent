#!/usr/bin/env bash
set -euo pipefail

# D2-10: 가비아 Ubuntu 서버 초기 설정
# 운전: 문서 담당
# 사용법:
#   bash bootstrap.sh             # 점검만 수행
#   ADMIN_IP=공인IP sudo -E bash bootstrap.sh --apply

APPLY=false

if [[ "${1:-}" == "--apply" ]]; then
    APPLY=true
fi

echo "=== 서버 정보 ==="
hostname
nproc
free -h

echo "=== Swap 확인 ==="
if [[ -n "$(swapon --noheadings --show)" ]]; then
    echo "경고: Swap이 활성화되어 있습니다."
else
    echo "Swap 비활성화 확인"
fi

echo "=== vm.max_map_count 확인 ==="
MAP_COUNT=$(sysctl -n vm.max_map_count)

if (( MAP_COUNT >= 262144 )); then
    echo "vm.max_map_count=$MAP_COUNT (요구 조건 충족)"
else
    echo "경고: vm.max_map_count 영구 설정 필요"
fi

echo "=== 방화벽 확인 ==="
sudo ufw status verbose

if [[ "$APPLY" == false ]]; then
    echo "점검 모드: 설정을 변경하지 않았습니다."
    exit 0
fi

# 관리자 IP를 입력받지 못하면 적용 중단
if [[ -z "${ADMIN_IP:-}" ]]; then
    echo "오류: ADMIN_IP가 설정되지 않았습니다."
    exit 1
fi

# 관리자 공인 IPv4 형식 검사
if ! [[ "$ADMIN_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "오류: ADMIN_IP 형식이 올바르지 않습니다."
    exit 1
fi

echo "=== Swap 비활성화 ==="

if [[ -n "$(swapon --noheadings --show)" ]]; then
    sudo swapoff -a
    echo "활성화된 Swap을 비활성화했습니다."
else
    echo "Swap이 이미 비활성화되어 있습니다."
fi

echo "=== vm.max_map_count 영구 설정 ==="

MAP_COUNT=$(sysctl -n vm.max_map_count)

if (( MAP_COUNT < 262144 )); then
    echo "vm.max_map_count = 262144" |
        sudo tee /etc/sysctl.d/99-edr-map-count.conf > /dev/null

    sudo sysctl --system
    echo "vm.max_map_count 영구 설정 완료"
else
    echo "현재 값 $MAP_COUNT 유지"
fi

echo "=== UFW 규칙 설정 ==="

# SSH 및 웹 접속
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Kubernetes API: 관리자 공인 IPv4만 허용
sudo ufw allow from "$ADMIN_IP" to any port 6443 proto tcp

# k3s 내부 네트워크
sudo ufw allow from 10.42.0.0/16 to any
sudo ufw allow from 10.43.0.0/16 to any

# Pod 포워딩
sudo ufw route allow in on cni0 out on eth0
sudo ufw route allow in on eth0 out on cni0

echo "=== UFW 규칙 확인 ==="
sudo ufw status numbered

echo "규칙 등록 완료. UFW 활성화는 별도 검토 후 수행합니다."