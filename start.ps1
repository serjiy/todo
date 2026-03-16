# start.ps1
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "🚀 ЗАПУСК ПОЛНОГО РАЗВЕРТЫВАНИЯ ToDo-ПРИЛОЖЕНИЯ" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

#---------------------------------------------------------------
# ОПРЕДЕЛЕНИЕ ПУТИ К ПРОЕКТУ
#---------------------------------------------------------------
# Определение директории скрипта и поиск папки проекта
$SCRIPT_PATH = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Поиск папки todo в той же директории, где лежит скрипт
$PROJECT_PATH = $SCRIPT_PATH
if (Test-Path (Join-Path $SCRIPT_PATH "todo")) {
    $PROJECT_PATH = Join-Path $SCRIPT_PATH "todo"
}

$K8S_PATH = Join-Path $PROJECT_PATH "k8s"

Write-Host "`n📁 Скрипт запущен из: $SCRIPT_PATH" -ForegroundColor Cyan
Write-Host "📁 Проект найден в: $PROJECT_PATH" -ForegroundColor Cyan
Write-Host "📁 Манифесты Kubernetes: $K8S_PATH" -ForegroundColor Cyan

#---------------------------------------------------------------
# ШАГ 1: ПРОВЕРКА И ЗАПУСК DOCKER
#---------------------------------------------------------------
Write-Host "`n🔍 ШАГ 1: Проверка Docker..." -ForegroundColor Yellow

# Функция проверки статуса Docker
function Test-DockerRunning {
    try {
        $info = docker info 2>$null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

# Функция запуска Docker Desktop
function Start-DockerDesktop {
    Write-Host "  ⚡ Запуск Docker Desktop..." -ForegroundColor Yellow
    
    $dockerPaths = @(
        "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe",
        "$env:LOCALAPPDATA\Programs\Docker\Docker\Docker Desktop.exe"
    )
    
    $started = $false
    foreach ($path in $dockerPaths) {
        if (Test-Path $path) {
            Write-Host "  Найден Docker: $path" -ForegroundColor Gray
            Start-Process $path
            $started = $true
            break
        }
    }
    
    if (-not $started) {
        Write-Host "  ❌ Не удалось найти Docker Desktop." -ForegroundColor Red
        return $false
    }
    
    Write-Host "  ⏳ Ожидание запуска Docker (до 60 сек)..." -ForegroundColor Gray
    $timeout = 60
    $elapsed = 0
    while ($elapsed -lt $timeout) {
        if (Test-DockerRunning) {
            Write-Host "  ✅ Docker успешно запущен!" -ForegroundColor Green
            return $true
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
        Write-Host "." -NoNewline -ForegroundColor Gray
    }
    
    Write-Host "`n  ❌ Docker не запустился" -ForegroundColor Red
    return $false
}

if (Test-DockerRunning) {
    Write-Host "✅ Docker уже запущен" -ForegroundColor Green
} else {
    Write-Host "⚠️ Docker не запущен. Выполняется запуск..." -ForegroundColor Yellow
    $result = Start-DockerDesktop
    if (-not $result) {
        exit 1
    }
}

#---------------------------------------------------------------
# ШАГ 2: ПРОВЕРКА И ЗАПУСК MINIKUBE
#---------------------------------------------------------------
Write-Host "`n🔍 ШАГ 2: Проверка Minikube..." -ForegroundColor Yellow

$minikubeStatus = minikube status --format='{{.Host}}' 2>$null
if ($minikubeStatus -ne "Running") {
    Write-Host "🔄 Запуск Minikube..." -ForegroundColor Yellow
    minikube start --driver=docker
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Ошибка запуска Minikube" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Minikube запущен" -ForegroundColor Green
} else {
    Write-Host "✅ Minikube уже работает" -ForegroundColor Green
}

#---------------------------------------------------------------
# ШАГ 3: ПРИМЕНЕНИЕ МАНИФЕСТОВ
#---------------------------------------------------------------
Write-Host "`n📦 ШАГ 3: Применение Kubernetes манифестов..." -ForegroundColor Yellow

# Проверка существования папки с манифестами
if (-not (Test-Path $K8S_PATH)) {
    Write-Host "❌ Папка с манифестами не найдена: $K8S_PATH" -ForegroundColor Red
    Write-Host "Проверьте, что скрипт запускается из правильной директории" -ForegroundColor Yellow
    exit 1
}

Write-Host "  → Применение PV и PVC..." -ForegroundColor Gray
kubectl apply -f "$K8S_PATH\mongo-pv.yaml"

Write-Host "  → Применение MongoDB..." -ForegroundColor Gray
kubectl apply -f "$K8S_PATH\mongo-deployment.yaml"
kubectl apply -f "$K8S_PATH\mongo-service.yaml"

Write-Host "  → Применение приложения..." -ForegroundColor Gray
kubectl apply -f "$K8S_PATH\deployment.yaml"
kubectl apply -f "$K8S_PATH\todo-service.yaml"

Write-Host "  → Применение Ingress..." -ForegroundColor Gray
kubectl apply -f "$K8S_PATH\ingress.yaml"

Write-Host "  → Применение HPA..." -ForegroundColor Gray
kubectl apply -f "$K8S_PATH\hpa.yaml"

Write-Host "  → Применение мониторинга..." -ForegroundColor Gray
kubectl apply -f "$K8S_PATH\monitoring\"

#---------------------------------------------------------------
# ШАГ 4: ОЖИДАНИЕ ЗАПУСКА ПОДОВ
#---------------------------------------------------------------
Write-Host "`n⏳ ШАГ 4: Ожидание запуска всех подов..." -ForegroundColor Yellow

Write-Host "  → Ожидание MongoDB..." -ForegroundColor Gray
kubectl wait --for=condition=ready pod -l app=mongo --timeout=60s 2>$null

Write-Host "  → Ожидание приложения..." -ForegroundColor Gray
kubectl wait --for=condition=ready pod -l app=todo --timeout=60s 2>$null

Write-Host "  → Ожидание Prometheus..." -ForegroundColor Gray
kubectl wait --for=condition=ready pod -l app=prometheus --timeout=60s 2>$null

Write-Host "  → Ожидание Grafana..." -ForegroundColor Gray
kubectl wait --for=condition=ready pod -l app=grafana --timeout=60s 2>$null

#---------------------------------------------------------------
# ШАГ 5: ЗАПУСК MINIKUBE TUNNEL В НОВОМ ОКНЕ
#---------------------------------------------------------------
Write-Host "`n🌐 ШАГ 5: Запуск Minikube tunnel в новом окне..." -ForegroundColor Yellow

# Проверка, не запущен ли уже туннель
$tunnelRunning = Get-Process -Name "minikube" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*tunnel*" }

if (-not $tunnelRunning) {
    # Запуск туннеля в новом окне через cmd (не PowerShell)
    $tunnelWindow = Start-Process cmd -ArgumentList "/c start cmd /k minikube tunnel" -WindowStyle Hidden -PassThru
    
    if ($tunnelWindow) {
        Write-Host "  ✅ Туннель запущен в новом окне" -ForegroundColor Green
        Write-Host "  ℹ️ Окно с туннелем открыто отдельно, основное окно продолжает работу" -ForegroundColor Yellow
    } else {
        Write-Host "  ❌ Не удалось запустить туннель" -ForegroundColor Red
    }
} else {
    Write-Host "  ⚠️ Туннель уже работает" -ForegroundColor Yellow
}

# Небольшая пауза, чтобы туннель успел инициализироваться
Start-Sleep -Seconds 3

#---------------------------------------------------------------
# ШАГ 6: ПРОВЕРКА И ИТОГИ
#---------------------------------------------------------------
Write-Host "`n=========================================================" -ForegroundColor Green
Write-Host "✅ РАЗВЕРТЫВАНИЕ УСПЕШНО ЗАВЕРШЕНО!" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green

$pods = kubectl get pods --no-headers 2>$null | Measure-Object | Select-Object -ExpandProperty Count
$runningPods = kubectl get pods --no-headers 2>$null | Select-String "Running" | Measure-Object | Select-Object -ExpandProperty Count

Write-Host "`n📊 Статистика:" -ForegroundColor Cyan
Write-Host "  • Подов всего: $pods" -ForegroundColor White
Write-Host "  • Запущено: $runningPods" -ForegroundColor White

Write-Host "`n📊 Доступ к сервисам:" -ForegroundColor Cyan
Write-Host "  • Приложение: http://todo.local/list" -ForegroundColor White
Write-Host "    Команда: minikube service todo (если не работает Ingress)" -ForegroundColor Gray
Write-Host ""
Write-Host "  • Grafana:    http://localhost:3000 (admin/admin)" -ForegroundColor White
Write-Host "    Команда: minikube service grafana" -ForegroundColor Gray
Write-Host ""
Write-Host "  • Prometheus: http://localhost:9090" -ForegroundColor White
Write-Host "    Команда: minikube service prometheus" -ForegroundColor Gray

Write-Host "`n⚠️  Проверка записи в hosts:" -ForegroundColor Yellow
Write-Host "   C:\Windows\System32\drivers\etc\hosts -> 127.0.0.1 todo.local" -ForegroundColor White

#---------------------------------------------------------------
# ИНФОРМАЦИЯ О ЗАВЕРШЕНИИ
#---------------------------------------------------------------
Write-Host "`n📌 Скрипт завершил работу." -ForegroundColor Cyan
Write-Host "   Окно с туннелем остаётся открытым отдельно (заголовок: Command Prompt)." -ForegroundColor Cyan
Write-Host "   Для остановки туннеля закройте его окно или нажмите Ctrl+C в нём." -ForegroundColor Cyan