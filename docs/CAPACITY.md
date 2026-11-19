# 용량 산정 (16GB 서버 기준)

> 2일차 인프라 2단계를 시작하기 전에 계산합니다. 2단계 운전자(🔍 기록 담당)가 주도하고, 📘 문서 담당이 검토합니다.

| 워크로드 | 종류 | CPU req | Mem req / limit | 힙 | 근거 |
|---|---|---|---|---|---|
| OS + k3s + Traefik | - | 예비 500m | 예비 2Gi / - | - | 실측: `free -h`, `kubectl top`. OS 및 k3s 운영을 위한 예비 자원 |
| opensearch | StatefulSet | 1000m | 2Gi / 4Gi | 2Gi | JVM 힙을 메모리 limit의 50%로 설정. 힙 외 메모리 및 검색·인덱싱 작업 고려 |
| postgres | StatefulSet | 250m | 512Mi / 1Gi | - | PostgreSQL 체크포인트 저장 및 DB 운영을 위한 초기 자원 계획 |
| api | Deployment | 250m | 256Mi / 512Mi | - | 기존 API 실측 2m CPU, 65Mi RAM. 요청량 증가에 대비한 여유 확보 |
| worker | Deployment | 250m | 512Mi / 1Gi | - | 백그라운드 알림 처리 및 Python 실행 메모리 고려 |
| generator | Deployment | 250m | 256Mi / 512Mi | - | 이벤트 생성 작업을 위한 초기 자원 계획 |
| kb-ingest (일시적) | Job | 500m | 1Gi / 2Gi | - | PDF 파싱·청킹·임베딩 작업을 위한 일시적 자원 확보 |
| **합계 / 여유** | | **3 CPU / 여유 1 CPU** | **요청 6.5Gi / 컨테이너 limit 합계 9Gi** | - | CPU 4개, RAM 약 15.62Gi 기준. OS 예비 자원 포함. 팀 검토 필요 |

## 1. 서버 자원 실측 결과

서버: `edr-team7`

### CPU 및 메모리

실행 명령:
- `nproc`
- `free -h`

| 항목 | 실제 측정값 |
|---|---|
| 논리 CPU | 4 |
| RAM 전체 | 15Gi (`free -h` 표시값) |
| RAM 사용 중 | 1.3Gi |
| RAM Free | 11Gi |
| RAM Available | 14Gi |
| Buff/Cache | 3.3Gi |
| Swap | 0B |

- 현재 메모리 사용량은 낮고, Available RAM은 약 14Gi이다.
- Swap이 활성화되어 있지 않으므로 메모리 부족에 따른 OOM 위험을 고려해야 한다.
- 현재 가용 메모리가 충분하더라도 전체 워크로드 배포 후 사용량은 별도 검증이 필요하다.

### 디스크

실행 명령: `df -h /`

| 항목 | 실제 측정값 |
|---|---|
| 파일 시스템 | `/dev/vda1` |
| 전체 용량 | 48G |
| 사용량 | 3.8G |
| 사용 가능 | 44G |
| 사용률 | 8% |
| 마운트 경로 | `/` |

- 현재 디스크 사용률은 8%로 여유 공간이 존재한다.
- OpenSearch와 PostgreSQL의 실제 저장 공간 사용량은 아직 측정하지 않았다.
- OpenSearch 인덱스 크기와 데이터 증가량을 고려한 추후 검증이 필요하다.

## 2. Kubernetes 자원 확인

실행 명령:
- `sudo k3s kubectl get nodes -o wide`
- `sudo k3s kubectl describe nodes`
- `sudo k3s kubectl get pods -A -o wide`
- `sudo k3s kubectl top nodes`
- `sudo k3s kubectl top pods -A`

### Node 상태 및 자원

| 항목 | 실제 측정값 |
|---|---|
| Node | `edr-team7` |
| Kubernetes | `v1.37.2+k3s1` |
| Node 상태 | Ready |
| CPU Capacity | 4 |
| CPU Allocatable | 4 |
| Memory Allocatable | 약 15.62Gi |
| 기존 CPU Requests 합계 | 200m (5%) |
| 기존 Memory Requests 합계 | 140Mi |
| 현재 Node CPU 사용량 | 40m (1%) |
| 현재 Node 메모리 사용량 | 908Mi (5%) |
| MemoryPressure | False |
| DiskPressure | False |
| PIDPressure | False |

### 기존 주요 Pod 자원 사용량

| Pod | CPU 사용량 | 메모리 사용량 |
|---|---|---|
| coredns | 2m | 13Mi |
| local-path-provisioner | 1m | 7Mi |
| metrics-server | 3m | 22Mi |
| svclb-traefik | 0m | 0Mi |
| traefik | 1m | 20Mi |
| soc/api | 2m | 65Mi |

- 모든 주요 실행 중 Pod가 Running 상태이다.
- 기존 Pod의 CPU Requests 합계는 200m, 메모리 Requests 합계는 140Mi이다.
- 현재 API Pod에는 CPU·메모리 requests 및 limits가 설정되어 있지 않다.
- Pod별 사용량은 측정 시점의 값으로, 최대 부하 시 필요한 자원을 의미하지 않는다.
- Node 사용량에는 Pod 외 Kubernetes 및 시스템 프로세스 사용량도 포함될 수 있다.

## 3. 스토리지 확인

실행 명령:
- `sudo k3s kubectl get storageclass`
- `sudo k3s kubectl get pvc -A`
- `sudo k3s kubectl get pv`

| 항목 | 실제 확인 결과 |
|---|---|
| 기본 StorageClass | `local-path` |
| Provisioner | `rancher.io/local-path` |
| ReclaimPolicy | Delete |
| VolumeBindingMode | WaitForFirstConsumer |
| AllowVolumeExpansion | false |
| 현재 PVC | 없음 |
| 현재 PV | 없음 |

- k3s의 기본 StorageClass는 `local-path`이다.
- OpenSearch StatefulSet 배포 시 PVC를 통해 저장 공간을 요청할 계획이다.
- 현재 PVC와 PV는 존재하지 않는다.
- PVC 바인딩 및 Pod 재생성 이후 데이터 유지 여부는 D2-12에서 검증해야 한다.
- local-path는 노드 로컬 저장소를 사용하므로 별도의 고가용성 스토리지와 동일하게 취급하지 않는다.

## 4. 자원 배분 근거

### CPU

- 서버 전체 CPU: 4
- OS 및 k3s 운영 예비: 500m
- OpenSearch: 1000m
- PostgreSQL: 250m
- API: 250m
- Worker: 250m
- Generator: 250m
- kb-ingest: 500m

계획상 CPU 합계: 3000m (3 CPU)

남는 CPU 예산: 1000m (1 CPU)

### 메모리

- OS 및 k3s 운영 예비: 2Gi
- OpenSearch: 2Gi
- PostgreSQL: 512Mi
- API: 256Mi
- Worker: 512Mi
- Generator: 256Mi
- kb-ingest: 1Gi

계획상 메모리 요청량과 운영 예비 합계: 6.5Gi

애플리케이션 컨테이너의 메모리 limit 합계: 9Gi

운영 예비 2Gi까지 포함한 limit 기준 예산: 11Gi

메모리 Allocatable 약 15.62Gi와 비교하면 계획상 여유가 존재한다.

단, OS·k3s 운영 예비는 실제 Kubernetes requests 설정이 아니며, 기존 시스템 Pod의 requests와 중복 합산하지 않는다.

### OpenSearch JVM 힙

- OpenSearch 메모리 request: 2Gi
- OpenSearch 메모리 limit: 4Gi
- JVM Heap: 2Gi

OpenSearch는 JVM 힙 이외에도 네이티브 메모리와 파일 캐시 등을 사용한다.

따라서 메모리 limit 전체를 JVM 힙으로 할당하지 않고 약 50%를 힙으로 설정하는 초기안을 선택하였다.

해당 설정은 배포 전 계획이며 실제 메모리 사용량을 검증한 결과는 아니다.

## 5. 최종 판단 및 검토 사항

### 현재 확인 완료

- 서버 CPU 4개 확인
- RAM 약 15Gi 및 Available 약 14Gi 확인
- 루트 디스크 48G, 여유 44G 확인
- k3s Node Ready 확인
- Node 및 기존 Pod의 requests/limits 확인
- Metrics Server 기반 실제 자원 사용량 확인
- 기본 StorageClass `local-path` 확인

### 추가 검증 필요

- OpenSearch 배포 후 실제 CPU·RAM 사용량
- OpenSearch JVM Heap 및 컨테이너 메모리 사용량
- PostgreSQL·Worker·Generator 실제 자원 사용량
- kb-ingest 작업 중 최대 메모리 사용량
- 전체 워크로드 동시 실행 시 자원 경쟁
- PVC Bound 및 데이터 영속성
- 실제 인덱스 데이터 크기와 디스크 증가량

### 결론

현재 서버는 CPU 4개, RAM 약 15.62Gi, 디스크 여유 44G를 보유하고 있다.

기존 Kubernetes 워크로드의 예약 자원과 실제 사용량은 낮은 상태이다.

초기 용량 산정상 OpenSearch를 포함한 전체 서비스 배치를 시도할 수 있는 자원 여유가 확인되었다.

다만 자원 배분 수치는 실제 부하 검증 전의 초기 계획값이다.

📘 문서 담당의 검토 완료. 
D2-12 OpenSearch StatefulSet 배포를 진행하고, 실제 사용량에 따라 requests/limits를 조정한다.

