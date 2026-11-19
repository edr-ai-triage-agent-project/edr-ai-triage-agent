
# 런북: 우리가 겪은 장애와 찾는 법

> 02 문서 8장의 **'좋은 런북'** 형식으로 씁니다.
>
> 새벽 당번이 이것만 보고 해결할 수 있게, **실제로 친 명령과 실제 출력**을 남깁니다.

---

## 공통 1차 확인

### Kubernetes 환경

```bash
kubectl -n soc get pods,svc,ingress,pvc,jobs

kubectl -n soc get events --sort-by=.lastTimestamp | tail -20
```

> 교안의 Kubernetes 공통 확인 명령이다. 이번 인프라 0단계에서는 실행하지 않았다.

### Docker Compose 로컬 환경

```powershell
# 컨테이너 상태 확인
docker compose ps -a

# 전체 컨테이너와 호스트 포트 확인
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# PostgreSQL 호스트 포트 매핑 확인
docker port edr-ai-triage-agent-postgres-1

# PostgreSQL SQL 응답 확인
docker compose exec -T postgres psql -U soc -d soc -c "SELECT 1;"
```

---

## 장애 기록

### [0-2] PostgreSQL 5432 포트 충돌 (출제: 📘 · 진단: 🔍 · 복구까지 걸린 시간: 미측정)

| 항목 | 내용 |
|---|---|
| 실습 환경 | Windows 11 / Docker Desktop / Docker Compose |
| 대상 | PostgreSQL 16 |
| 출제 | 📘 문서 담당 |
| 진단 및 복구 | 🔍 기록 담당 |
| 방식 | 팀원이 전달한 시나리오를 개인 로컬 환경에서 재현 |
| 결과 | 컨테이너 실행 및 호스트 포트 매핑 복구 확인 |

---

#### 증상

PostgreSQL 컨테이너를 중지한 뒤, Alpine 임시 컨테이너가 Windows 호스트의 `127.0.0.1:5432` 포트를 점유하도록 설정했다.

이후 기존 PostgreSQL을 다시 시작하자 **Docker 네트워크 구성 단계에서 호스트 포트 바인딩 오류**가 발생했다.

**실제 오류 출력**

```text
Container edr-ai-triage-agent-postgres-1 Starting
Error response from daemon: failed to set up container networking: driver failed programming external connectivity on endpoint edr-ai-triage-agent-postgres-1 (7399f56eeaa7b26af7a0ce77e98331f73446e4e14f14783cd5a546a409af66ae): Bind for 127.0.0.1:5432 failed: port is already allocated
```

**핵심 오류**

```text
Bind for 127.0.0.1:5432 failed: port is already allocated
```

**오류 메시지 해석**

| 메시지 | 의미 |
|---|---|
| `Error response from daemon` | Docker Engine이 오류 반환 |
| `failed to set up container networking` | 컨테이너 네트워크 구성 실패 |
| `driver failed programming external connectivity` | 외부 연결을 위한 네트워크 설정 실패 |
| `Bind for 127.0.0.1:5432 failed` | 호스트 IP·포트 바인딩 실패 |
| `port is already allocated` | 해당 포트가 이미 할당됨 |

**최초 판단**

PostgreSQL 자체의 SQL 실행 오류가 아니라, Docker가 컨테이너를 시작하면서 **호스트 포트 5432를 할당하지 못한 문제**로 판단했다.

---

#### 확인 명령과 출력

##### [1] 장애 발생 전 정상 상태 확인

**실행 명령**

```powershell
docker compose exec -T postgres psql -U soc -d soc -c "SELECT 1;" 2>&1 |
    Tee-Object -FilePath .\evidence\D1-3-0-2-before-sql.txt
```

**실제 출력**

```text
 ?column?
----------
        1
(1 row)
```

**결과 해석**

- PostgreSQL 컨테이너 내부에서 SQL 실행 성공
- `soc` 사용자로 `soc` 데이터베이스 접근 성공
- 장애 주입 전 SQL 응답 정상
- 이 명령만으로 Windows 호스트의 5432 포트 연결까지 검증한 것은 아님

---

##### [2] PostgreSQL 컨테이너 중지

**실행 명령**

```powershell
docker compose stop postgres
```

**실제 출력**

```text
[+] stop 1/1
 ✔ Container edr-ai-triage-agent-postgres-1 Stopped 0.8s
```

**중지 상태 확인**

```powershell
docker compose ps -a
```

**실제 출력 (주요 열 발췌)**

```text
NAME                               SERVICE      STATUS                     PORTS
edr-ai-triage-agent-dashboards-1   dashboards   Up 33 minutes              127.0.0.1:5601->5601/tcp
edr-ai-triage-agent-opensearch-1   opensearch   Up 33 minutes              127.0.0.1:9200->9200/tcp
edr-ai-triage-agent-postgres-1     postgres     Exited (0) 5 seconds ago
```

**결과 해석**

- PostgreSQL은 `Exited (0)`으로 정상 종료
- OpenSearch와 Dashboards는 실행 상태 유지
- PostgreSQL 컨테이너만 중지
- 기존 데이터 Named Volume은 삭제하지 않음

---

##### [3] Alpine 컨테이너로 5432 포트 점유

**실행 명령**

```powershell
docker run -d --name edr-port-blocker -p 127.0.0.1:5432:5432 alpine:3.20 sh -c "sleep 3600"
```

**실제 출력**

```text
Unable to find image 'alpine:3.20' locally
3.20: Pulling from library/alpine
25f1d6b1951a: Pull complete
3a030ca3f633: Download complete
d4050d56ebf2: Download complete
Digest: sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc
Status: Downloaded newer image for alpine:3.20
5508dd2003e70d7d9e538ac74c62a381ce87fab7497bb68bec7b9b2f415109e5
```

**포트 점유 확인 명령**

```powershell
docker ps --filter "name=edr-port-blocker"
```

**실제 출력**

```text
CONTAINER ID   IMAGE         COMMAND                CREATED          STATUS          PORTS                      NAMES
5508dd2003e7   alpine:3.20   "sh -c 'sleep 3600'"   50 seconds ago   Up 49 seconds   127.0.0.1:5432->5432/tcp   edr-port-blocker
```

**결과 해석**

- Alpine 이미지 다운로드 성공
- `edr-port-blocker` 컨테이너 실행 성공
- `127.0.0.1:5432` 포트 매핑 확인
- Alpine 내부에서는 PostgreSQL을 실행하지 않음
- Docker의 호스트 포트 매핑만으로도 충돌 상황을 만들 수 있음

---

##### [4] PostgreSQL 재시작 및 장애 발생 확인

**실행 명령**

```powershell
docker compose up -d postgres 2>&1 |
    Tee-Object -FilePath .\evidence\D1-3-0-2-start-error.txt
```

**실제 출력**

```text
Container edr-ai-triage-agent-postgres-1 Starting
Error response from daemon: failed to set up container networking: driver failed programming external connectivity on endpoint edr-ai-triage-agent-postgres-1 (7399f56eeaa7b26af7a0ce77e98331f73446e4e14f14783cd5a546a409af66ae): Bind for 127.0.0.1:5432 failed: port is already allocated
```

**장애 상태 확인 명령**

```powershell
docker compose ps -a 2>&1 |
    Tee-Object -FilePath .\evidence\D1-3-0-2-failure-containers.txt
```

**실제 출력 (주요 열 발췌)**

```text
NAME                               SERVICE      STATUS
edr-ai-triage-agent-dashboards-1   dashboards   Up 35 minutes
edr-ai-triage-agent-opensearch-1   opensearch   Up 35 minutes
edr-ai-triage-agent-postgres-1     postgres     Exited (128) 2 minutes ago
```

**포트 점유 확인 명령**

```powershell
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>&1 |
    Tee-Object -FilePath .\evidence\D1-3-0-2-port-check.txt
```

**실제 출력**

```text
NAMES                              STATUS              PORTS
edr-port-blocker                   Up About a minute   127.0.0.1:5432->5432/tcp
edr-ai-triage-agent-dashboards-1   Up 35 minutes       127.0.0.1:5601->5601/tcp
edr-ai-triage-agent-opensearch-1   Up 35 minutes       127.0.0.1:9200->9200/tcp
```

**결과 해석**

- PostgreSQL 시작 실패
- PostgreSQL 상태가 `Exited (128)`로 변경
- Alpine 컨테이너는 계속 실행 중
- Alpine이 PostgreSQL의 호스트 포트 5432를 점유
- Docker 오류와 포트 점유 상태가 일치

**종료 상태 비교**

| 시점 | PostgreSQL 상태 | 의미 |
|---|---|---|
| 정상 중지 후 | `Exited (0)` | 정상 종료 |
| 포트 충돌 후 | `Exited (128)` | 시작 과정에서 실패 |

`Exited (128)`만으로 직접 원인을 확정하지 않고, Docker 오류와 포트 점유 결과를 함께 비교했다.

---

#### 원인

##### 직접 원인 — Docker 호스트 포트 5432 중복 점유

Alpine 임시 컨테이너가 PostgreSQL에서 사용해야 할 `127.0.0.1:5432` 포트를 먼저 점유했다.

그 결과 PostgreSQL을 다시 시작하려는 과정에서 Docker가 동일한 호스트 포트를 할당하지 못했다.

**장애 구조**

```text
Windows Host
127.0.0.1:5432
       |
       +---- Alpine (edr-port-blocker)
       |         |
       |         +-- 포트 할당 성공
       |
       +---- PostgreSQL
                 |
                 +-- 동일 포트 할당 요청
                 |
                 +-- Docker 네트워크 설정 실패
                 |
                 +-- 컨테이너 시작 실패
```

**원인 판단 근거**

| 증거 | 실제 결과 | 판단 |
|---|---|---|
| Alpine 컨테이너 | `Up` | 실행 중 |
| Alpine 포트 | `127.0.0.1:5432->5432/tcp` | 호스트 포트 점유 |
| PostgreSQL | `Exited (128)` | 시작 실패 |
| Docker 오류 | `port is already allocated` | 중복 포트 할당 실패 |
| OpenSearch | `Up` | 실행 유지 |
| Dashboards | `Up` | 실행 유지 |

**원인 판단**

최초 장애는 PostgreSQL 내부 설정이나 SQL 실행 문제가 아니라 **Docker Engine의 호스트 포트 충돌**로 발생했다.

---

#### 조치

##### [1] 포트를 점유한 Alpine 컨테이너 제거

**실행 명령**

```powershell
docker rm -f edr-port-blocker
```

**실제 출력**

```text
edr-port-blocker
```

**포트 점유 해제 확인**

```powershell
docker ps --filter "publish=5432"
```

**실제 출력**

```text
CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES
```

**결과 해석**

- Alpine 임시 컨테이너 제거 성공
- 실행 중인 Docker 컨테이너 중 호스트 5432 포트 게시 대상이 더 이상 표시되지 않음

---

##### [2] PostgreSQL 1차 복구

**실행 명령**

```powershell
docker compose up -d postgres
```

**실제 출력**

```text
[+] up 1/1
 ✔ Container edr-ai-triage-agent-postgres-1 Started 0.3s
```

**SQL 정상 응답 확인**

```powershell
docker compose exec -T postgres psql -U soc -d soc -c "SELECT 1;" 2>&1 |
    Tee-Object -FilePath .\evidence\D1-3-0-2-after-sql.txt
```

**실제 출력**

```text
 ?column?
----------
        1
(1 row)
```

**1차 복구 결과**

- PostgreSQL 컨테이너 시작 성공
- PostgreSQL 내부 SQL 실행 성공
- Alpine 컨테이너 제거 완료

그러나 추가 검증에서 **호스트 포트 매핑이 복구되지 않은 문제**를 발견했다.

---

##### [3] 1차 복구 후 포트 매핑 미복원 확인

**컨테이너 상태 확인**

```powershell
docker compose ps -a 2>&1 |
    Tee-Object -FilePath .\evidence\D1-3-0-2-after-containers.txt
```

**실제 출력 (주요 열 발췌)**

```text
NAME                               SERVICE      STATUS          PORTS
edr-ai-triage-agent-dashboards-1   dashboards   Up 37 minutes   127.0.0.1:5601->5601/tcp
edr-ai-triage-agent-opensearch-1   opensearch   Up 37 minutes   127.0.0.1:9200->9200/tcp
edr-ai-triage-agent-postgres-1     postgres     Up 6 seconds    5432/tcp
```

**정상 상태와 비교**

```text
최초 정상 상태
127.0.0.1:5432->5432/tcp

1차 복구 상태
5432/tcp
```

**호스트 포트 매핑 확인**

```powershell
docker port edr-ai-triage-agent-postgres-1
```

**실제 결과**

출력 없음.

**Compose 설정 확인**

```powershell
(docker compose config --format json | ConvertFrom-Json).services.postgres.ports |
    Format-List
```

**실제 출력**

```text
mode      : ingress
host_ip   : 127.0.0.1
target    : 5432
published : 5432
protocol  : tcp
```

**컨테이너에 저장된 포트 바인딩 설정 확인**

```powershell
docker inspect --format '{{json .HostConfig.PortBindings}}' edr-ai-triage-agent-postgres-1
```

**실제 출력**

```json
{"5432/tcp":[{"HostIp":"127.0.0.1","HostPort":"5432"}]}
```

**실제 네트워크 포트 정보 확인**

```powershell
docker inspect --format '{{json .NetworkSettings.Ports}}' edr-ai-triage-agent-postgres-1
```

**실제 출력**

```json
{"5432/tcp":[]}
```

**설정과 실제 상태 비교**

| 확인 항목 | 실제 결과 | 해석 |
|---|---|---|
| Compose 설정 | `127.0.0.1:5432` | 원하는 설정 존재 |
| HostConfig.PortBindings | `127.0.0.1:5432` | 저장된 설정 존재 |
| NetworkSettings.Ports | `{"5432/tcp":[]}` | 실제 호스트 포트 매핑 없음 |
| docker port | 출력 없음 | 포트 매핑 미복원 |
| SELECT 1 | 성공 | 컨테이너 내부 DB 정상 |

**추가 문제 분석**

PostgreSQL 컨테이너를 다시 시작했을 때 SQL 실행은 성공했지만 호스트 포트 매핑이 복원되지 않았다.

설정 파일과 컨테이너에 저장된 포트 바인딩에는 `127.0.0.1:5432`가 존재했다.

그러나 `NetworkSettings.Ports`에는 호스트 포트 목록이 비어 있었다.

앞선 포트 바인딩 실패 이후 기존 컨테이너를 재시작한 과정과 관련됐을 가능성이 있지만, Docker 내부의 정확한 발생 원인까지 확정하지는 않았다.

---

##### [4] PostgreSQL Named Volume 확인

컨테이너 재생성 전 데이터 저장소의 연결 상태를 확인했다.

**실행 명령**

```powershell
docker inspect --format '{{range .Mounts}}{{println .Type .Name .Destination}}{{end}}' edr-ai-triage-agent-postgres-1
```

**실제 출력**

```text
volume edr-ai-triage-agent_postgres-data /var/lib/postgresql/data
```

**결과 해석**

| 항목 | 실제 값 |
|---|---|
| 저장소 유형 | `volume` |
| 볼륨 이름 | `edr-ai-triage-agent_postgres-data` |
| 마운트 경로 | `/var/lib/postgresql/data` |

- PostgreSQL이 Docker Named Volume을 사용 중임을 확인
- 컨테이너와 데이터 저장소가 별도로 관리되는 구조
- 재생성 후 동일 볼륨을 다시 연결하는 방식으로 진행
- 실제 데이터 행의 유지 여부는 별도로 검증하지 않음

---

##### [5] PostgreSQL 컨테이너 재생성

기존 PostgreSQL 컨테이너를 재생성하여 Compose 포트 설정을 새로 적용했다.

**실행 명령**

```powershell
docker compose up -d --no-deps --force-recreate postgres
```

**실제 출력**

```text
[+] up 1/1
 ✔ Container edr-ai-triage-agent-postgres-1 Started 1.2s
```

**명령 옵션 설명**

| 옵션 | 의미 |
|---|---|
| `-d` | 백그라운드 실행 |
| `--no-deps` | 의존 서비스는 함께 시작하지 않음 |
| `--force-recreate` | 기존 컨테이너를 교체해 재생성 |
| `postgres` | PostgreSQL 서비스만 대상으로 지정 |

**조치 목적**

- 기존 컨테이너 교체
- Compose 포트 바인딩 설정 다시 적용
- PostgreSQL 서비스만 대상으로 작업
- Named Volume은 삭제하지 않음

---

##### [6] 최종 복구 검증

**호스트 포트 매핑 확인**

```powershell
docker port edr-ai-triage-agent-postgres-1
```

**실제 출력**

```text
5432/tcp -> 127.0.0.1:5432
```

**컨테이너 실행 상태 확인**

```powershell
docker compose ps -a 2>&1 |
    Tee-Object -FilePath .\evidence\D1-3-0-2-final-containers.txt
```

**실제 출력 (주요 열 발췌)**

```text
NAME                               SERVICE      STATUS          PORTS
edr-ai-triage-agent-dashboards-1   dashboards   Up 49 minutes   127.0.0.1:5601->5601/tcp
edr-ai-triage-agent-opensearch-1   opensearch   Up 49 minutes   127.0.0.1:9200->9200/tcp
edr-ai-triage-agent-postgres-1     postgres     Up 13 seconds   127.0.0.1:5432->5432/tcp
```

**SQL 재검증**

```powershell
docker compose exec -T postgres psql -U soc -d soc -c "SELECT 1;" 2>&1 |
    Tee-Object -FilePath .\evidence\D1-3-0-2-final-sql.txt
```

**실제 출력**

```text
 ?column?
----------
        1
(1 row)
```

**Named Volume 재연결 확인**

```powershell
docker inspect --format '{{range .Mounts}}{{println .Type .Name .Destination}}{{end}}' edr-ai-triage-agent-postgres-1
```

**실제 출력**

```text
volume edr-ai-triage-agent_postgres-data /var/lib/postgresql/data
```

---

##### [7] 장애 발생 전후 결과 비교

| 비교 항목 | 최초 정상 | 장애 발생 | 1차 복구 | 최종 복구 |
|---|---|---|---|---|
| PostgreSQL 상태 | Up | Exited (128) | Up | Up |
| 호스트 5432 포트 | PostgreSQL 사용 | Alpine 사용 | 매핑 없음 | PostgreSQL 사용 |
| docker port | 정상 매핑 | 시작 실패 | 출력 없음 | 정상 매핑 |
| SELECT 1 | 성공 | 미실행 | 성공 | 성공 |
| OpenSearch | Up | Up | Up | Up |
| Dashboards | Up | Up | Up | Up |
| Named Volume | 구성 존재 | 삭제하지 않음 | 연결 확인 | 동일 볼륨 확인 |

**비교 분석**

1. 정상 중지 시 PostgreSQL은 `Exited (0)`이었다.
2. Alpine이 포트를 점유한 상태에서 재시작하자 `Exited (128)` 및 포트 바인딩 오류가 발생했다.
3. Alpine을 제거한 뒤 PostgreSQL은 실행됐지만 호스트 포트 매핑이 복원되지 않았다.
4. `HostConfig.PortBindings`와 `NetworkSettings.Ports`를 비교해 저장된 설정과 실제 네트워크 상태가 다른 점을 확인했다.
5. PostgreSQL 컨테이너를 재생성한 후 호스트 포트 매핑과 SQL 응답이 정상화됐다.

**최종 판단**

PostgreSQL 5432 포트 충돌을 재현했고, 직접 원인을 제거한 뒤 추가로 발견한 포트 매핑 문제까지 복구했다.

최종적으로 다음 항목을 확인했다.

- PostgreSQL 컨테이너 `Up`
- 호스트 포트 `127.0.0.1:5432` 매핑 복원
- `SELECT 1` 성공
- 기존 Named Volume 재연결
- OpenSearch와 Dashboards 실행 상태 유지

단, Windows 호스트에서 PostgreSQL로 직접 TCP 접속하는 검증과 기존 데이터 행의 보존 여부는 별도로 수행하지 않았다.

---

#### 진단 후 나눔 (깨 보기 규칙 5~6번)

##### 진단자: 가장 오래 걸린 지점과 이유

- 실제 복구 시간: 미측정
- 가장 오래 걸린 지점에 대한 개인 회고: 작성 예정

**이번 실습에서 추가로 발견한 문제**

- 최초 포트 충돌 해결 후에도 호스트 포트 매핑이 복원되지 않았음
- PostgreSQL 내부 SQL은 성공했지만 외부 포트 연결 정보는 비어 있었음
- 설정과 실제 적용 상태를 비교하는 추가 진단이 필요했음

**학습한 점**

- 컨테이너가 `Up`이어도 모든 기능이 정상이라는 보장은 없음
- SQL 성공과 호스트 포트 연결은 별도 검증 대상
- 장애 원인 제거 후에도 실제 상태를 재검증해야 함
- 필요한 경우 컨테이너 재시작과 재생성의 차이를 고려해야 함

---

##### 출제자: 나라면 어디부터 봤을지

- `port is already allocated` 오류가 발생했으므로 Docker 컨테이너 상태와 포트 점유 여부부터 확인했을 것.
- `docker compose ps -a`로 컨테이너 상태를 확인하고, `docker ps`로 5432 포트를 점유한 컨테이너를 찾았을 것.
- 실제로 Alpine 컨테이너가 포트를 점유하고 있었으므로 예상한 진단 방향과 일치함.
- 포트 충돌 해결 후에도 포트 매핑이 복구되지 않을 수 있으므로, `docker port`로 실제 매핑까지 확인해야 한다는 점을 알게 됨.

---

##### 다음에 같은 증상을 보면 처음 칠 명령

**[1] 컨테이너 상태 확인**

```powershell
docker compose ps -a
```

**[2] 포트 점유 현황 확인**

```powershell
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

**[3] PostgreSQL 호스트 포트 확인**

```powershell
docker port edr-ai-triage-agent-postgres-1
```

**명령별 목적**

| 명령 | 확인 목적 |
|---|---|
| `docker compose ps -a` | PostgreSQL 실행·종료 상태 |
| `docker ps` | 다른 컨테이너의 포트 점유 |
| `docker port` | PostgreSQL의 실제 호스트 포트 매핑 |

위 순서는 이번 실습을 기반으로 작성한 제안이며, 팀원과 최종 합의한 내용은 아니다.

---

#### 재발 방지

##### [1] 호스트 포트 충돌 사전 확인

- Docker Compose에서 사용하는 호스트 포트를 확인한다.
- 동일한 포트를 다른 컨테이너가 사용 중인지 점검한다.
- `port is already allocated` 메시지가 발생하면 포트 중복 사용 여부를 우선 확인한다.

##### [2] Docker 오류와 PostgreSQL 내부 오류 구분

- Docker 네트워크 설정 단계에서 실패했는지 확인한다.
- PostgreSQL 내부에서 발생한 오류인지 구분한다.
- 컨테이너 종료 코드 하나만으로 원인을 단정하지 않는다.

##### [3] 복구 후 호스트 포트 매핑 검증

- `docker compose ps -a`로 실행 상태를 확인한다.
- `docker port`로 호스트 포트 매핑을 확인한다.
- 설정과 실제 상태가 다르면 `docker inspect`로 비교한다.

##### [4] PostgreSQL 정상 응답 검증

- `SELECT 1`로 컨테이너 내부 SQL 응답을 확인한다.
- 호스트에서 접속해야 한다면 TCP 연결도 별도 확인한다.

##### [5] 데이터 보존을 고려한 복구

- 컨테이너 재생성 전 Named Volume을 확인한다.
- 재생성 후 동일 볼륨이 연결됐는지 확인한다.
- `docker compose down -v` 사용에 주의한다.
- 필요한 경우 실제 데이터 조회로 보존 여부를 검증한다.

---

#### 고장 예상표와 비교

02 문서 9-2에서 예상했던 고장인가? 증상과 '처음 확인할 곳'은 맞았나?

**출제자가 예상한 장애**

```text
PostgreSQL이 사용하는 호스트 포트 5432를
다른 컨테이너가 먼저 점유하도록 만든다.

PostgreSQL 시작 시 포트 충돌 오류가 발생한다.
```

**출제자가 예상한 오류**

```text
Bind for 127.0.0.1:5432 failed: port is already allocated
```

**실제 확인 결과**

- Alpine 컨테이너의 5432 포트 점유 확인
- PostgreSQL 재시작 실패 확인
- 출제자가 예상한 오류와 실제 오류 일치
- 1차 복구 후 호스트 포트 매핑이 복원되지 않는 추가 증상 발견

**예상과 실제 결과 비교**

| 비교 항목 | 실제 실습 결과 | 기존 고장 예상표와 비교 |
|---|---|---|
| 장애 유형 | PostgreSQL 5432 포트 충돌 | 기존 예상표 확인 필요 |
| 예상 오류 | `port is already allocated` | 출제자 예상과 일치 |
| 직접 원인 | Alpine의 5432 포트 점유 | 기존 예상표 확인 필요 |
| 처음 확인할 곳 | Docker 오류 및 포트 점유 | 기존 예상표 확인 필요 |
| 추가 발견 문제 | 1차 복구 후 포트 매핑 미복원 | 기존 예상표 확인 필요 |
| 최종 복구 | PostgreSQL 컨테이너 재생성 | 기존 예상표 확인 필요 |

**비교 결과**

출제자가 의도한 PostgreSQL 포트 충돌 장애는 실제로 재현됐다.

예상했던 오류 메시지와 실제 발생한 오류가 일치했다.

추가로, 포트 충돌 원인을 제거한 뒤에도 호스트 포트 매핑이 복구되지 않아 재검증과 컨테이너 재생성이 필요했다.

기존 02 문서 9-2의 개인 고장 예상표 원문과 비교한 결과는 아직 확인되지 않았다.

---

### [1-1] Kubernetes 이미지 태그 오타

- **환경:** Gabia Ubuntu / k3s
- **출제:** ChatGPT (🔍 팀원 역할 대행)
- **진단·복구:** 📘 문서 담당
- **복구 시간:** 미측정
- **결과:** 복구 완료

#### 1. 증상

API 배포 후 기존 Pod는 정상 실행됐지만 새 Pod는 실행되지 않았다.

```text
api-56d66656c4-d2gpz   1/1   Running
api-7d9c65bc74-5hbt2   0/1   ImagePullBackOff
```

#### 2. 확인 명령과 출력

먼저 Pod 상태를 확인했다.

```bash
kubectl --kubeconfig ~/.kube/edr-team7.yaml -n soc get pods
```

오류 원인을 확인하기 위해 `kubectl describe pod`를 실행했지만, 처음에는 kubeconfig를 지정하지 않아 `localhost:8080 connection refused` 오류가 발생했다.

kubeconfig를 지정해 다시 실행했다.

```bash
kubectl --kubeconfig ~/.kube/edr-team7.yaml -n soc describe pod api-7d9c65bc74-5hbt2
```

**Events 주요 출력**

```text
Failed to pull image "...:d2-tset"
NotFound: ...:d2-tset: not found
Error: ImagePullBackOff
```

#### 3. 원인

이미지 태그가 `d2-test`가 아닌 `d2-tset`으로 잘못 설정되어 있었다.

존재하지 않는 이미지를 가져오려고 해서 새 Pod 실행에 실패한 것이다.

#### 4. 조치

이미지 태그를 정상값으로 수정했다.

```bash
kubectl --kubeconfig ~/.kube/edr-team7.yaml -n soc set image deployment/api \
  api=ghcr.io/edr-ai-triage-agent-project/edr-ai-triage-agent:d2-test
```

**복구 확인**

```text
deployment "api" successfully rolled out
Deployment READY: 1/1
HTTP/1.1 200 OK
{"status":"ok","backend":"memory"}
```

정상 Pod만 남았고 API 응답도 확인했다.

#### 5. 진단 후 나눔

**📘 진단자 — 가장 오래 걸린 부분**

오류 원인을 확인해야 한다는 건 알았지만 어떤 명령어를 사용해야 하는지 몰라서 헷갈렸다. AI 도움 없이 검색해서 `kubectl describe pod`를 찾았다. 처음에는 kubeconfig를 빠뜨려 오류가 발생했고, 다시 실행해서 Events를 확인했다.

**🔍 출제자 — 나라면 어디부터 봤을지**

`kubectl get pods`로 비정상 Pod를 찾고, `ImagePullBackOff`가 보이면 `kubectl describe pod`의 Events부터 확인했을 것이다.

**다음에 처음 실행할 명령어**

```bash
kubectl --kubeconfig ~/.kube/edr-team7.yaml -n soc get pods
```

비정상 Pod가 있으면 `describe pod`로 상세 원인을 확인한다.

#### 6. 재발 방지

- 배포 전에 이미지 이름과 태그를 확인한다.
- `ImagePullBackOff` 발생 시 Pod Events를 먼저 확인한다.
- 원격 클러스터 명령에는 kubeconfig를 명시한다.
- 복구 후 Pod 상태와 API 응답까지 확인한다.


---

### [2-1] OpenSearch vm.max_map_count 커널 설정 오류

- **환경:** Gabia Ubuntu 24.04.4 / k3s / OpenSearch 2.19.1
- **진단·복구:** 🔍 기록 담당
- **장애 출제 역할:** 📘 문서 담당
- **실습 일자:** 2026-11-19
- **복구 시간:** 미측정
- **결과:** 커널 설정 경고 재현 및 복구 완료 / 예상 CrashLoopBackOff 미발생

#### 1. 정상 상태

장애 주입 전 OpenSearch StatefulSet 및 Pod가 정상 실행 중이었다.

```text
statefulset.apps/opensearch   1/1
pod/opensearch-0              1/1 Running
```

커널 설정 확인:

```bash
sysctl vm.max_map_count
```

실제 출력:

```text
vm.max_map_count = 1048576
```

OpenSearch에서 요구하는 최소값 262144보다 높은 상태였다.

이전 영속성 검증에서 OpenSearch Pod 삭제·재생성 후에도 테스트 문서 1건이 유지되는 것을 확인하였다.

#### 2. 장애 주입

**실습 목적**

서버의 `vm.max_map_count` 값을 낮춘 뒤 OpenSearch Pod를 재생성하여 시작 조건 검사 오류를 관찰한다.

기존 설정을 `ORIGINAL` 변수에 저장하고, 스크립트 종료 시 원래 값으로 복구하도록 설정하였다.

```bash
ORIGINAL=$(sysctl -n vm.max_map_count)

trap 'sysctl -w "vm.max_map_count=$ORIGINAL"' EXIT

sysctl -w vm.max_map_count=65530

k3s kubectl -n soc delete pod opensearch-0
```

실제 출력:

```text
vm.max_map_count = 65530
pod "opensearch-0" deleted from soc namespace
```

커널 설정 변경과 Pod 삭제가 정상적으로 수행되었다.

#### 3. 증상 및 증거 수집

**예상 증상**

- OpenSearch 시작 실패
- Pod `CrashLoopBackOff`
- Bootstrap Check 오류 로그

**실제 Pod 상태**

실행 명령:

```bash
k3s kubectl -n soc rollout status \
  statefulset/opensearch --timeout=90s

k3s kubectl -n soc get pod opensearch-0 -o wide
```

실제 출력:

```text
Waiting for 1 pods to be ready...
partitioned roll out complete: 1 new pods have been updated...

NAME           READY   STATUS    RESTARTS   AGE   IP
opensearch-0   1/1     Running   0          31s   10.42.0.15
```

예상했던 `CrashLoopBackOff`는 발생하지 않았다.

**Kubernetes 이벤트**

실행 명령:

```bash
k3s kubectl -n soc describe pod opensearch-0
```

주요 출력:

```text
Normal  Scheduled  Successfully assigned soc/opensearch-0 to edr-team7
Normal  Pulled     Container image "opensearchproject/opensearch:2.19.1" already present on machine
Normal  Created    Container created
Normal  Started    Container started
```

Pod 스케줄링, 컨테이너 생성 및 시작이 정상적으로 진행되었다.

**OpenSearch 로그**

실행 명령:

```bash
k3s kubectl -n soc logs opensearch-0 --tail=100
```

실제 오류 관련 로그:

```text
[WARN ][o.o.b.BootstrapChecks] [opensearch-0] max virtual memory areas vm.max_map_count [65530] is too low, increase to at least [262144]
```

이어지는 로그:

```text
[INFO ][o.o.n.Node] [opensearch-0] started
```

커널 설정이 요구 기준보다 낮다는 경고는 발생했지만 OpenSearch 프로세스는 정상적으로 시작되었다.

**이전 컨테이너 로그 확인**

```bash
k3s kubectl -n soc logs opensearch-0 \
  --previous --tail=100
```

실제 출력:

```text
Error from server (BadRequest): previous terminated container "opensearch" in pod "opensearch-0" not found
```

새 Pod에서 종료된 이전 컨테이너의 로그는 확인되지 않았다.

#### 4. 원인 판단

**직접 확인한 원인**

Linux 커널 설정값을 `1048576`에서 `65530`으로 낮추면서 OpenSearch가 요구하는 최소 메모리 매핑 영역 수인 `262144`보다 작아졌다.

OpenSearch Bootstrap Check가 이를 감지하고 경고 로그를 출력하였다.

**예상과 달리 프로세스가 종료되지 않은 이유**

현재 OpenSearch 설정:

```yaml
- name: discovery.type
  value: "single-node"
```

OpenSearch의 단일 노드 실행 설정에서는 일부 Bootstrap Check가 강제되지 않아 경고만 기록하고 정상적으로 시작할 수 있다.

현재 관찰 결과는 해당 동작과 일치한다.

다만 단일 노드 설정이 이번 경고 처리의 직접적인 원인이라는 사실을 추가 설정 변경 실험으로 검증한 것은 아니다.

따라서 실제 결과는 다음과 같이 구분한다.

- 커널 설정 오류: 실제 재현
- Bootstrap Check 경고: 실제 확인
- OpenSearch 시작 실패: 미발생
- CrashLoopBackOff: 미발생

#### 5. 조치 및 복구

장애 수집 스크립트 종료 시 기존 설정으로 복원되었다.

실제 출력:

```text
vm.max_map_count = 1048576
```

원래 설정을 복구한 뒤 OpenSearch Pod를 다시 생성하였다.

```bash
sudo -n k3s kubectl -n soc delete pod opensearch-0

sudo -n k3s kubectl -n soc rollout status \
  statefulset/opensearch --timeout=240s
```

실제 출력:

```text
pod "opensearch-0" deleted from soc namespace

Waiting for 1 pods to be ready...
partitioned roll out complete: 1 new pods have been updated...
```

#### 6. 복구 후 재검증

실행 명령:

```bash
sysctl vm.max_map_count

sudo -n k3s kubectl -n soc get sts,pods,pvc
```

실제 결과:

```text
vm.max_map_count = 1048576

statefulset.apps/opensearch   1/1

pod/api-56d66656c4-d2gpz   1/1 Running
pod/opensearch-0            1/1 Running

persistentvolumeclaim/data-opensearch-0   Bound
```

PVC는 기존 PV를 유지하였다.

```text
pvc-0ed49159-735b-47d4-8264-cde77881aed1
```

**테스트 데이터 영속성 확인**

```bash
sudo -n k3s kubectl -n soc exec opensearch-0 -- \
  curl -sS "http://127.0.0.1:9200/edr-d2-persistence-test/_count?pretty"
```

실제 출력:

```json
{
  "count": 1,
  "_shards": {
    "total": 1,
    "successful": 1,
    "skipped": 0,
    "failed": 0
  }
}
```

복구 후 OpenSearch Pod가 Ready 상태로 돌아왔으며 기존 테스트 문서 1건이 유지되었다.

#### 7. 고장 예상표와 실제 결과 비교

| 비교 항목 | 고장 예상표 | 실제 결과 |
|---|---|---|
| 커널 설정 | 65530으로 변경 | 변경 성공 |
| Pod 재생성 | 삭제 후 재시작 | 재생성 성공 |
| 예상 Pod 증상 | CrashLoopBackOff | Running |
| 예상 로그 | max_map_count 관련 오류 | WARN 발생 |
| 프로세스 시작 | 시작 실패 예상 | 정상 시작 |
| 복구 후 상태 | Ready | Ready |
| 데이터 유지 | 확인 필요 | 1건 유지 |

**비교 결과**

커널 설정 오류 자체는 실제로 재현되었다.

그러나 예상한 `CrashLoopBackOff` 대신 경고 로그만 발생하고 OpenSearch가 정상 시작되었다.

단일 노드 설정에서 Bootstrap Check가 강제되지 않은 것이 유력한 원인으로 판단된다.

#### 8. 진단 후 나눔

**🔍 진단자 — 오래 걸린 부분과 이유**

- 가장 판단이 필요했던 부분은 `vm.max_map_count`를 `65530`으로 낮췄는데도 예상한 `CrashLoopBackOff`가 발생하지 않은 점이었다.
- 처음에는 커널 설정 변경이 정상적으로 적용되지 않았을 가능성을 고려했으나, OpenSearch 로그에서 `vm.max_map_count [65530] is too low` 경고를 확인하였다.
- 따라서 설정 변경은 적용되었지만 OpenSearch가 종료되지 않았다는 사실을 구분할 수 있었다.
- 현재 `discovery.type: single-node` 설정에서 Bootstrap Check가 경고로 처리된 것이 유력한 원인으로 판단하였다.
- 장애 진단에서는 예상한 Pod 상태뿐 아니라 실제 애플리케이션 로그까지 확인하는 것이 중요하다는 점을 배웠다.

**📘 출제자 — 나라면 처음 확인할 곳**

- 먼저 `kubectl get pods`로 OpenSearch Pod가 실제로 `CrashLoopBackOff` 상태인지 확인한다.
- 이후 `kubectl logs`에서 Bootstrap Check 관련 오류를 확인한다.
- `vm.max_map_count` 경고가 존재한다면 Ubuntu 서버에서 현재 커널 설정값을 확인하여 요구 기준과 비교한다.
- Pod가 정상 실행되더라도 로그에 경고가 남아 있을 수 있으므로 Pod 상태만으로 장애 여부를 단정하지 않는다.

**다음에 동일 증상이 발생하면 처음 사용할 명령**

sysctl vm.max_map_count

#### 9. 재발 방지

- OpenSearch 배포 전 호스트의 `vm.max_map_count` 확인
- 커널 설정 변경 전 기존 값 기록
- Pod 상태와 애플리케이션 로그를 함께 확인
- 경고 발생과 실제 서비스 중단을 구분
- 복구 후 StatefulSet Ready 및 PVC 상태 확인
- 데이터 영속성은 실제 문서 조회로 재검증

**최종 상태:** 커널 설정 복구, OpenSearch Ready, PVC 유지, 테스트 문서 1건 유지 확인


---


### [4-3] Worker Deployment 중지 및 복구 (🔍 기록 담당)

#### 1. 정상 상태

- 환경: Gabia Ubuntu `edr-team7`, k3s, 네임스페이스 `soc`
- Worker Deployment: `1/1`
- 정상 Pod: `worker-7f9fbb888c-hxx2w`
- Pod IP: `10.42.0.20`
- Node: `edr-team7`
- Restart: `0`

확인 명령:

```bash
sudo -n k3s kubectl get deployment worker -n soc
sudo -n k3s kubectl get pods -n soc -l app=worker -o wide
```

#### 2. 장애 주입

Worker Deployment의 원하는 복제본 수를 0으로 변경하였다.

```bash
sudo -n k3s kubectl scale deployment/worker \
  -n soc --replicas=0
```

실제 출력:

```text
deployment.apps/worker scaled
```

#### 3. 장애 증상 및 증거

Deployment 조회 결과:

```text
NAME     READY   UP-TO-DATE   AVAILABLE
worker   0/0     0            0
```

Worker Pod 조회 결과:

```text
No resources found in soc namespace.
```

Worker Pod가 제거되어 알림 처리 프로세스를 실행할 수 없는 상태가 되었다.

이번 실험에서는 알림 적체 및 재처리까지 검증하지 않았다.

#### 4. 원인 판단

`kubectl scale --replicas=0`으로 Deployment의 Desired State를 0개로 변경하였다.

Kubernetes는 설정된 원하는 상태에 따라 Worker Pod를 제거하였다.

이는 Kubernetes가 예기치 않은 장애를 감지한 것이 아니라, 운영자가 의도적으로 복제본 수를 변경한 실험이다.

#### 5. 조치 및 복구

```bash
sudo -n k3s kubectl scale deployment/worker \
  -n soc --replicas=1

sudo -n k3s kubectl rollout status \
  deployment/worker -n soc --timeout=120s
```

실제 출력:

```text
deployment.apps/worker scaled
deployment "worker" successfully rolled out
```

#### 6. 복구 후 재검증

| 항목 | 장애 전 | 복구 후 |
|---|---|---|
| Pod | worker-7f9fbb888c-hxx2w | worker-7f9fbb888c-jmxzh |
| IP | 10.42.0.20 | 10.42.0.22 |
| Node | edr-team7 | edr-team7 |
| READY | 1/1 | 1/1 |
| STATUS | Running | Running |
| RESTARTS | 0 | 0 |

복구 후 로그:

```text
2026-11-19 11:08:23,713 checkpoint PostgreSQL Checkpointer 초기화 완료
2026-11-19 11:08:23,723 worker 워커 시작: worker-7f9fbb888c-jmxzh
```

Health 확인:

```text
200 heartbeat 2s ago
```

새 Worker Pod가 생성되었고 PostgreSQL Checkpointer 초기화, OpenSearch HTTP 200 검색, Health HTTP 200을 확인하였다.

#### 7. 실제 결과와 검증 한계

- Worker 중지 및 신규 Pod 생성: 검증 완료
- Kubernetes Deployment 복제본 수 복원: 검증 완료
- PostgreSQL Checkpointer 초기화 및 Health 복구: 검증 완료
- 중지 중 알림 적체 및 복구 후 재처리: 미검증
- 처리 도중 Pod 강제 종료 및 LangGraph 체크포인트 복원(4-5): 미실습

#### 8. 진단 후 나눔

**🔍 기록 담당 — 확인한 점**

- Deployment가 관리하는 것은 특정 Pod 자체가 아니라 원하는 복제본 수라는 점을 확인하였다.
- 복구 전후 Pod 이름과 IP가 변경되었으므로 새 Pod 생성 사실을 확인할 수 있었다.
- `1/1 Running`뿐 아니라 PostgreSQL 초기화 로그와 Health 응답까지 확인하여 복구 여부를 판단하였다.

#### 9. 재발 방지

- Worker Deployment의 `replicas` 값 확인
- Pod 상태와 실제 애플리케이션 로그를 함께 확인
- Pod 교체 후 `/healthz` 및 외부 의존성 연결 확인
- 설정을 임시 변경했다면 원래 복제본 수로 복구되었는지 재검증

**최종 결과:** Worker Deployment `replicas=1` 복구, 신규 Pod Running, PostgreSQL Checkpointer 초기화 및 Health HTTP 200 확인.


---


### [D2-14 통합 검증] KB 인덱스 미생성으로 인한 Worker AI 분석 실패

- **환경:** Gabia Ubuntu `edr-team7` / k3s / 네임스페이스 `soc`
- **담당:** 🔍 기록 담당
- **대상:** Worker Deployment, LangGraph, OpenSearch KB 검색
- **발견 경위:** D2-14 Worker 통합 기능 검증 중 발견
- **최종 결과:** Mock KB 환경에서 승인 대기 및 리포트 저장 성공, 원래 환경변수 복구 완료
- **남은 작업:** 인프라 6단계에서 실제 KB 인덱스 생성 및 문서 적재

#### 1. 정상 동작 기대

Generator가 만든 보안 이벤트를 OpenSearch에 저장하고, 탐지 규칙으로 생성한 알림을 Worker가 분석하는 흐름을 검증한다.

예상 처리 흐름:

```text
Generator
    ↓ 이벤트 생성
OpenSearch (edr-events-*)
    ↓ 탐지 규칙
OpenSearch (edr-alerts)
    ↓ Worker가 알림 획득
LangGraph AI 분석
    ↓
KB 플레이북 검색
    ↓
분석 리포트 저장 (triage-reports)
    ↓
completed 또는 pending_approval
```

이번 실습에서는 실제 보안 알림이 Worker까지 전달되는지, LangGraph 분석이 실행되는지, 분석 결과가 저장되는지 확인하는 것을 목표로 했다.

#### 2. 증상 — 실제 KB 검색 중 HTTP 404 발생

가비아 Ubuntu에서 실행 중인 Worker 컨테이너를 통해 `credential_dump` 시나리오를 주입하였다.

**실행 명령**

```bash
sudo -n k3s kubectl exec -n soc deployment/worker -- \
  python -m soc.simulator.run --inject credential_dump
```

**실제 출력**

```text
'credential_dump'을 WS-007에 주입: 기록 3건, 새 알림 1건 (악성: True)
```

Generator의 이벤트 생성과 보안 알림 생성까지는 정상 수행되었다.

그러나 Worker가 알림을 분석하는 과정에서 오류가 발생했다.

**Worker 오류 로그**

```text
2026-11-19 11:12:51,222 opensearch POST http://opensearch:9200/kb-playbooks/_search [status:404 request:0.003s]

worker 처리 실패: al-4a5ea8938693

opensearchpy.exceptions.NotFoundError:
NotFoundError(404, 'index_not_found_exception', 'no such index [kb-playbooks]', kb-playbooks, index_or_alias)
```

**오류 발생 위치**

```text
soc/worker.py
    ↓
graph.invoke()
    ↓
soc/agent/nodes.py
    ↓ recommend 노드
search_playbook()
    ↓
soc/kb/search.py
    ↓ keyword_search()
OpenSearch kb-playbooks 검색
    ↓
HTTP 404 / index_not_found_exception
```

Worker 프로세스 자체가 종료된 것이 아니라, LangGraph 분석 중 실제 KB 검색 단계에서 예외가 발생하였다.

#### 3. 증거 수집 — 알림 상태와 Worker Metrics

**알림 상태 확인 명령**

```bash
sudo -n k3s kubectl exec -n soc opensearch-0 -- \
  curl -fsS 'http://localhost:9200/edr-alerts/_search?size=10&_source_includes=status,attempts,worker,lease_until&filter_path=hits.hits._id,hits.hits._source'
```

**실제 조회 결과 요약**

| 알림 ID | status | attempts | Worker |
|---|---|---:|---|
| `al-f5497182756c` | failed | 1 | worker-7f9fbb888c-jmxzh |
| `al-4a5ea8938693` | failed | 1 | worker-7f9fbb888c-jmxzh |

두 알림이 `failed` 상태였으며, 각각 한 차례 Worker에 획득된 기록이 있었다.

단, `kb-playbooks` HTTP 404 오류 로그로 직접 원인을 확인한 알림은 `al-4a5ea8938693`이다. 다른 실패 알림의 구체적인 원인은 이번에 별도로 확인하지 않았다.

**Worker Metrics 조회 명령**

```bash
sudo -n k3s kubectl exec -n soc deployment/worker -- \
  python -c "import urllib.request as u; print(u.urlopen('http://127.0.0.1:9100/metrics').read().decode())"
```

**실제 출력**

```text
soc_worker_processed 0
soc_worker_failed 2
soc_worker_pending_approval 0
soc_worker_busy 0
```

**결과 해석**

| 항목 | 값 | 의미 |
|---|---:|---|
| processed | 0 | 일반 처리 완료 건수 0 |
| failed | 2 | 현재 Worker 프로세스의 실패 건수 2 |
| pending_approval | 0 | 승인 대기 건수 0 |
| busy | 0 | 조회 시점에 실행 중인 분석 없음 |

알림 획득은 성공했으나 분석이 정상적인 종료 상태에 도달하지 못했다.

#### 4. 원인 판단

**직접 확인한 원인**

Worker의 공통 환경변수는 다음과 같이 설정되어 있었다.

```yaml
KB_TOOLS: "real"
```

`KB_TOOLS=real`인 경우 실제 OpenSearch의 KB 인덱스를 검색한다.

그러나 현재 가비아 OpenSearch에는 `kb-playbooks` 인덱스가 없어 검색 요청이 HTTP 404를 반환하였다.

**증거와 원인 비교**

| 증거 | 실제 결과 | 해석 |
|---|---|---|
| 이벤트 주입 | 이벤트 3건 생성 | Generator 경로 정상 |
| 알림 생성 | 새 알림 1건 생성 | 탐지 규칙 동작 확인 |
| Worker 획득 | attempts=1 | Worker가 알림 획득 |
| OpenSearch 연결 | 검색 요청에 응답 | OpenSearch 접근 가능 |
| KB 검색 | HTTP 404 | 검색 대상 인덱스 없음 |
| LangGraph | recommend 노드에서 예외 | KB 검색 단계 실패 |

따라서 OpenSearch 서버 자체가 중단된 문제는 아니며, **실제 KB 검색에 필요한 인덱스가 준비되지 않은 상태에서 Worker가 real 검색을 수행한 문제**로 판단하였다.

KB 인덱스 생성과 PDF 플레이북 적재는 인프라 6단계에서 진행할 예정이다.

#### 5. 임시 조치 — Worker만 Mock KB 적용

**조치 목적**

아직 준비되지 않은 실제 KB 검색 기능을 제외하고, Worker의 알림 획득·LangGraph 분석·결과 저장 흐름을 검증한다.

팀원이 관리하는 공통 `soc-config`는 변경하지 않기로 했다.

대신 Worker Deployment에만 환경변수를 직접 추가하여 기존 `KB_TOOLS=real` 설정을 임시로 덮어썼다.

**실행 명령**

```bash
sudo -n k3s kubectl set env deployment/worker \
  -n soc KB_TOOLS=mock

sudo -n k3s kubectl rollout status \
  deployment/worker -n soc --timeout=120s
```

**실제 출력**

```text
deployment.apps/worker env updated
Waiting for deployment "worker" rollout to finish: 1 old replicas are pending termination...
deployment "worker" successfully rolled out
```

**적용된 환경변수 확인**

```bash
sudo -n k3s kubectl exec -n soc deployment/worker -- \
  printenv KB_TOOLS
```

**실제 출력**

```text
mock
```

**명령어 의미**

| 명령/옵션 | 의미 |
|---|---|
| `kubectl set env` | Deployment의 컨테이너 환경변수 변경 |
| `deployment/worker` | 변경할 대상 Deployment |
| `-n soc` | 대상 네임스페이스 |
| `KB_TOOLS=mock` | Worker에서 Mock KB 검색 사용 |
| `rollout status` | 변경된 Pod 배포 완료 확인 |
| `printenv KB_TOOLS` | 컨테이너에 실제 적용된 환경변수 확인 |

ConfigMap에서 가져오는 `envFrom` 값보다 컨테이너에 직접 지정한 `env` 값이 우선하므로, 공통 설정을 변경하지 않고 Worker만 테스트할 수 있었다.

환경변수 변경으로 Worker Pod가 교체되며, 프로세스 메모리의 Metrics 카운터도 초기화될 수 있다.

#### 6. 재검증 — 실제 알림 분석 및 리포트 저장

Mock KB 적용 후 동일한 유형의 시나리오를 새로 한 번 주입하였다.

**실행 명령**

```bash
sudo -n k3s kubectl exec -n soc deployment/worker -- \
  python -m soc.simulator.run --inject credential_dump
```

**실제 출력**

```text
'credential_dump'을 WS-007에 주입: 기록 3건, 새 알림 1건 (악성: True)
```

**새로 생성된 알림 ID**

```text
al-0d957dbf1977
```

Worker가 해당 알림을 획득해 분석을 수행하였다.

**Worker Metrics 재확인 결과**

```text
soc_worker_processed 0
soc_worker_failed 0
soc_worker_pending_approval 1
soc_worker_busy 0
```

**결과 해석**

- `processed=0`: 일반 완료 건수는 0건
- `failed=0`: 이번 Worker 프로세스에서 실패 건수 0건
- `pending_approval=1`: 승인 대기 상태에 도달한 알림 1건
- `busy=0`: 분석 작업 종료

`processed=0`이라고 해서 분석 실패를 의미하지 않는다.

이번 알림은 사람의 승인이 필요한 `pending_approval` 분기로 이동했기 때문이다.

**OpenSearch 알림 상태 확인**

```bash
sudo -n k3s kubectl exec -n soc opensearch-0 -- \
  curl -fsS 'http://localhost:9200/edr-alerts/_doc/al-0d957dbf1977?filter_path=_id,_source.status,_source.attempts,_source.worker'
```

**실제 출력**

```json
{
  "_id": "al-0d957dbf1977",
  "_source": {
    "status": "pending_approval",
    "attempts": 1,
    "worker": "worker-fd45fdc78-22shw"
  }
}
```

Metrics의 `pending_approval=1`과 OpenSearch에 저장된 알림 상태가 일치하였다.

**분석 리포트 저장 확인**

```bash
sudo -n k3s kubectl exec -n soc opensearch-0 -- \
  curl -sS \
  'http://localhost:9200/triage-reports/_doc/al-0d957dbf1977?filter_path=found,_id,_source.alert_id'
```

**실제 출력**

```json
{
  "_id": "al-0d957dbf1977",
  "found": true,
  "_source": {
    "alert_id": "al-0d957dbf1977"
  }
}
```

**재검증 결론**

- 실제 보안 이벤트 및 알림 생성 성공
- Worker 알림 획득 성공
- Mock KB 기반 LangGraph 분석 흐름 검증
- `pending_approval` 상태 저장 성공
- `triage-reports` 문서 저장 성공

단, 이 결과는 실제 KB 기반 RAG 검색 성공을 의미하지 않는다. 또한 저장된 리포트의 내용 품질 및 승인 이후 최종 처리까지 평가한 것은 아니다.

#### 7. 임시 환경변수 원상복구

**복구 목적**

D2-14 통합 검증이 끝났으므로 Worker에서만 적용한 임시 Mock 설정을 제거한다.

팀의 기존 공통 환경변수 `KB_TOOLS=real`이 다시 적용되도록 복구한다.

**실행 명령**

```bash
sudo -n k3s kubectl set env deployment/worker \
  -n soc KB_TOOLS-

sudo -n k3s kubectl rollout status \
  deployment/worker -n soc --timeout=120s
```

**실제 출력**

```text
deployment.apps/worker env updated
Waiting for deployment "worker" rollout to finish: 1 old replicas are pending termination...
deployment "worker" successfully rolled out
```

여기서 `KB_TOOLS-`는 환경변수 값을 빈 문자열로 설정하는 것이 아니라, Deployment에 직접 추가한 환경변수를 제거하는 문법이다.

**환경변수 복구 확인**

```bash
sudo -n k3s kubectl exec -n soc deployment/worker -- \
  printenv KB_TOOLS
```

**실제 출력**

```text
real
```

**Health 재검증**

```bash
sudo -n k3s kubectl exec -n soc deployment/worker -- \
  python -c "import urllib.request as u; r=u.urlopen('http://127.0.0.1:9100/healthz'); print(r.status, r.read().decode())"
```

**실제 출력**

```text
200 heartbeat 2s ago
```

원래 환경변수로 복구되었으며 새 Worker Pod의 Health 응답도 정상임을 확인하였다.

#### 8. 장애 원인과 검증 결과 비교

| 비교 항목 | 최초 상태 (Real KB) | 임시 조치 (Mock KB) | 원상복구 |
|---|---|---|---|
| KB_TOOLS | real | mock | real |
| KB 검색 | kb-playbooks 404 | Mock 검색 | 실제 KB 사용 설정 |
| Worker 분석 | 실패 발생 | 승인 대기 도달 | 재검증하지 않음 |
| Metrics failed | 2 | 0 | Pod 교체로 새 카운터 |
| pending_approval | 0 | 1 | 새 Pod에서 별도 집계 |
| 리포트 저장 | 해당 테스트에서 성공 미확인 | found=true | 기존 문서 유지 여부 별도 미조회 |
| Health | 정상 | Worker 재배포 성공 | HTTP 200 |

**비교 결과**

동일한 유형의 보안 알림에서 Mock KB를 적용한 경우에는 승인 대기 상태와 리포트 저장까지 도달하였다.

이는 최초 실패가 실제 KB 인덱스 미준비 문제와 관련되어 있다는 판단을 뒷받침한다.

다만 최초 알림을 재처리한 것이 아니라 새로운 알림으로 검증했으므로, 기존 실패 알림의 복구 성공까지 입증한 것은 아니다.

#### 9. 진단 후 나눔

**🔍 기록 담당 — 확인한 점**

- Worker Pod가 `Running`이고 OpenSearch 연결이 성공하더라도 실제 AI 분석이 완료된다는 보장은 없었다.
- LangGraph의 `recommend` 노드에서 실제 KB 인덱스가 필요하다는 의존성을 확인하였다.
- Worker 전체 설정을 바꾸지 않고 `kubectl set env`로 특정 Deployment의 환경변수만 임시 변경할 수 있었다.
- `processed=0`과 `pending_approval=1`을 구분해 결과를 해석해야 했다.
- Metrics뿐 아니라 실제 OpenSearch 알림 상태와 리포트 문서를 함께 확인해야 분석 결과를 검증할 수 있었다.
- 임시 설정 변경 후에는 원래 환경변수와 Health 상태를 반드시 확인해야 한다는 점을 배웠다.

#### 10. 재발 방지 및 후속 작업

- `KB_TOOLS=real`을 사용하기 전에 `kb-playbooks` 인덱스 존재 여부를 확인한다.
- 실제 KB 인덱스 및 PDF 플레이북 적재를 인프라 6단계에서 진행한다.
- KB 미준비 상태와 Worker 자체의 실행 장애를 구분한다.
- Worker 처리 결과는 로그, Metrics, 알림 상태, 리포트 저장 결과를 함께 확인한다.
- 임시 환경변수 변경 시 공통 ConfigMap 수정 여부를 구분하고 원상복구까지 검증한다.
- 실제 KB 기반 RAG 검색과 리포트 품질은 후속 단계에서 별도로 검증한다.
- 기존 `failed` 알림의 재처리와 승인 이후 최종 처리도 별도 검증 대상으로 남긴다.

**최종 상태**

- Worker Deployment 정상 실행
- 임시 `KB_TOOLS=mock` 설정 제거
- `KB_TOOLS=real` 원상복구 확인
- `/healthz` HTTP 200 확인
- Mock KB 기반 분석 및 리포트 저장 성공
- 실제 KB 인덱스 미생성 문제는 인프라 6단계 후속 작업으로 유지

**최종 판단:** D2-14에서 Worker의 알림 획득·Mock KB 기반 분석·승인 대기·리포트 저장 흐름을 검증하였다. 실제 KB 검색 실패 원인을 확인하고 임시 설정으로 정상 동작 경로를 검증한 뒤 원래 설정으로 복구하였다.
