# start.ps1
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "🚀 ЗАПУСК ПОЛНОГО РАЗВЕРТЫВАНИЯ ToDo-ПРИЛОЖЕНИЯ" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

#---------------------------------------------------------------
# ОПРЕДЕЛЕНИЕ ПУТИ К ПРОЕКТУ
#---------------------------------------------------------------
$SCRIPT_PATH = Split-Path -Parent $MyInvocation.MyCommand.Definition
$PROJECT_PATH = $SCRIPT_PATH
if (Test-Path (Join-Path $SCRIPT_PATH "todo")) {
    $PROJECT_PATH = Join-Path $SCRIPT_PATH "todo"
}
$K8S_PATH = Join-Path $PROJECT_PATH "k8s"

Write-Host "`n📁 Скрипт запущен из: $SCRIPT_PATH" -ForegroundColor Cyan
Write-Host "📁 Проект найден в: $PROJECT_PATH" -ForegroundColor Cyan
Write-Host "📁 Манифесты Kubernetes: $K8S_PATH" -ForegroundColor Cyan

#---------------------------------------------------------------
# ФУНКЦИЯ ПРОВЕРКИ DOCKER
#---------------------------------------------------------------
function Test-DockerRunning {
    try {
        $info = docker info 2>$null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

#---------------------------------------------------------------
# ФУНКЦИЯ ЗАПУСКА DOCKER DESKTOP
#---------------------------------------------------------------
function Start-DockerDesktop {
    Write-Host "  ⚡ Поиск Docker Desktop..." -ForegroundColor Yellow
    
    $dockerPaths = @(
        "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe",
        "$env:LOCALAPPDATA\Programs\Docker\Docker\Docker Desktop.exe"
    )
    
    foreach ($path in $dockerPaths) {
        if (Test-Path $path) {
            Write-Host "  Найден Docker: $path" -ForegroundColor Gray
            Start-Process $path
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
            Write-Host "`n  ❌ Docker не запустился за $timeout сек" -ForegroundColor Red
            return $false
        }
    }
    
    Write-Host "  ❌ Не удалось найти Docker Desktop." -ForegroundColor Red
    return $false
}

#---------------------------------------------------------------
# ФУНКЦИЯ БЫСТРОЙ ПРОВЕРКИ ПОДОВ
#---------------------------------------------------------------
function Wait-ForPod {
    param(
        [string]$label,
        [string]$name
    )
    
    Write-Host "  → Проверка $name..." -ForegroundColor Gray
    $timeout = 30
    $elapsed = 0
    
    while ($elapsed -lt $timeout) {
        $status = kubectl get pods -l $label -o jsonpath='{.items[0].status.phase}' 2>$null
        if ($status -eq "Running") {
            Write-Host "    ✅ $name запущен" -ForegroundColor Green
            return $true
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
        Write-Host "." -NoNewline -ForegroundColor Gray
    }
    Write-Host "`n    ⚠️ $name не запустился за $timeout сек" -ForegroundColor Yellow
    return $false
}

#---------------------------------------------------------------
# ШАГ 1: ПРОВЕРКА И ЗАПУСК DOCKER
#---------------------------------------------------------------
Write-Host "`n🔍 ШАГ 1: Проверка Docker..." -ForegroundColor Yellow

if (Test-DockerRunning) {
    Write-Host "✅ Docker уже запущен" -ForegroundColor Green
} else {
    Write-Host "⚠️ Docker не запущен. Выполняется запуск..." -ForegroundColor Yellow
    $result = Start-DockerDesktop
    if (-not $result) {
        Write-Host "❌ Не удалось запустить Docker. Запустите вручную." -ForegroundColor Red
        Read-Host "Нажмите Enter для выхода"
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
        Read-Host "Нажмите Enter для выхода"
        exit 1
    }
}
Write-Host "✅ Minikube работает" -ForegroundColor Green

#---------------------------------------------------------------
# ШАГ 3: ВКЛЮЧЕНИЕ INGRESS
#---------------------------------------------------------------
Write-Host "`n🔧 ШАГ 3: Включение Ingress..." -ForegroundColor Yellow
minikube addons enable ingress | Out-Null
Write-Host "✅ Ingress включен" -ForegroundColor Green

#---------------------------------------------------------------
# ШАГ 4: ПРИМЕНЕНИЕ МАНИФЕСТОВ
#---------------------------------------------------------------
Write-Host "`n📦 ШАГ 4: Применение манифестов..." -ForegroundColor Yellow

if (-not (Test-Path $K8S_PATH)) {
    Write-Host "❌ Папка с манифестами не найдена: $K8S_PATH" -ForegroundColor Red
    Read-Host "Нажмите Enter для выхода"
    exit 1
}

Set-Location $K8S_PATH

Write-Host "  → Применение PV и PVC..." -ForegroundColor Gray
kubectl apply -f mongo-pv.yaml 2>$null

Write-Host "  → Применение MongoDB..." -ForegroundColor Gray
kubectl apply -f mongo-deployment.yaml 2>$null
kubectl apply -f mongo-service.yaml 2>$null

Write-Host "  → Применение приложения..." -ForegroundColor Gray
kubectl apply -f deployment.yaml 2>$null
kubectl apply -f todo-service.yaml 2>$null

Write-Host "  → Применение Ingress и HPA..." -ForegroundColor Gray
kubectl apply -f ingress.yaml 2>$null
kubectl apply -f hpa.yaml 2>$null

Write-Host "  → Применение мониторинга..." -ForegroundColor Gray
kubectl apply -f monitoring/ 2>$null

Write-Host "✅ Манифесты применены" -ForegroundColor Green

#---------------------------------------------------------------
# ШАГ 5: ПРОВЕРКА ЗАПУСКА ПОДОВ
#---------------------------------------------------------------
Write-Host "`n⏳ ШАГ 5: Проверка запуска подов..." -ForegroundColor Yellow

Wait-ForPod -label "app=mongo" -name "MongoDB"
Wait-ForPod -label "app=todo" -name "Flask app"
Wait-ForPod -label "app=prometheus" -name "Prometheus"
Wait-ForPod -label "app=grafana" -name "Grafana"
Wait-ForPod -label "app=loki" -name "Loki"

#---------------------------------------------------------------
# ШАГ 6: ЗАПУСК ТУННЕЛЯ
#---------------------------------------------------------------
Write-Host "`n🌐 ШАГ 6: Запуск туннеля..." -ForegroundColor Yellow

# Проверка существующего туннеля
$tunnelRunning = Get-Process -Name "minikube" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*tunnel*" }

if (-not $tunnelRunning) {
    # Запуск в новом окне
    Start-Process cmd -ArgumentList "/c start cmd /k minikube tunnel" -WindowStyle Hidden
    Write-Host "  ✅ Туннель запущен в новом окне" -ForegroundColor Green
    Start-Sleep -Seconds 2
} else {
    Write-Host "  ⚠️ Туннель уже работает" -ForegroundColor Yellow
}

#---------------------------------------------------------------
# ШАГ 7: НАСТРОЙКА /etc/hosts
#---------------------------------------------------------------
Write-Host "`n🔧 ШАГ 7: Настройка hosts..." -ForegroundColor Yellow
$MINIKUBE_IP = minikube ip
$HOSTS_PATH = "$env:windir\System32\drivers\etc\hosts"

# Добавление записи (если её нет)
$hostsContent = Get-Content $HOSTS_PATH -Raw
if ($hostsContent -notmatch "todo.local") {
    Add-Content -Path $HOSTS_PATH -Value "`n$MINIKUBE_IP todo.local" -Force
    Write-Host "  ✅ Запись добавлена: $MINIKUBE_IP todo.local" -ForegroundColor Green
} else {
    Write-Host "  ⚠️ Запись уже существует" -ForegroundColor Yellow
}

#---------------------------------------------------------------
# ФИНАЛЬНЫЙ ВЫВОД
#---------------------------------------------------------------
Write-Host "`n=========================================================" -ForegroundColor Green
Write-Host "✅ ПРОЕКТ УСПЕШНО ЗАПУЩЕН!" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "📊 Доступ к сервисам:" -ForegroundColor Cyan
Write-Host "  • Приложение: http://todo.local/list" -ForegroundColor White
Write-Host "  • Grafana:    http://localhost:3000 (admin/admin)" -ForegroundColor White
Write-Host "  • Prometheus: http://localhost:9090" -ForegroundColor White
Write-Host ""
Write-Host "📌 Команды для открытия:" -ForegroundColor Cyan
Write-Host "  • minikube service grafana" -ForegroundColor Gray
Write-Host "  • minikube service prometheus" -ForegroundColor Gray
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "ℹ️  Окно с туннелем открыто отдельно" -ForegroundColor Yellow
Write-Host "   Для остановки проекта:" -ForegroundColor White
Write-Host "   1. Закройте окно туннеля" -ForegroundColor Gray
Write-Host "   2. Нажмите Enter в этом окне" -ForegroundColor Gray
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

# Блокировка закрытия окна
Read-Host "`nНажмите Enter для завершения работы скрипта"