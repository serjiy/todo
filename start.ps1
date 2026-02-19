# start.ps1
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "🚀 ЗАПУСК ПОЛНОГО РАЗВЕРТЫВАНИЯ ToDo-ПРИЛОЖЕНИЯ" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

#---------------------------------------------------------------
# ШАГ 1: ПРОВЕРКА И ЗАПУСК DOCKER
#---------------------------------------------------------------
Write-Host "`n🔍 ШАГ 1: Проверяем Docker..." -ForegroundColor Yellow

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
    Write-Host "  ⚡ Запускаем Docker Desktop..." -ForegroundColor Yellow
    
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
    
    Write-Host "  ⏳ Ожидаем запуск Docker (до 60 сек)..." -ForegroundColor Gray
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
    Write-Host "⚠️ Docker не запущен. Пробуем запустить..." -ForegroundColor Yellow
    $result = Start-DockerDesktop
    if (-not $result) {
        exit 1
    }
}

#---------------------------------------------------------------
# ШАГ 2: ПРОВЕРКА И ЗАПУСК MINIKUBE
#---------------------------------------------------------------
Write-Host "`n🔍 ШАГ 2: Проверяем Minikube..." -ForegroundColor Yellow

$minikubeStatus = minikube status --format='{{.Host}}' 2>$null
if ($minikubeStatus -ne "Running") {
    Write-Host "🔄 Запускаем Minikube..." -ForegroundColor Yellow
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
# ШАГ 3: ПРИМЕНЕНИЕ МАНИФЕСТОВ (С ПРАВИЛЬНЫМИ ПУТЯМИ)
#---------------------------------------------------------------
Write-Host "`n📦 ШАГ 3: Применяем Kubernetes манифесты..." -ForegroundColor Yellow

# Явно указываем путь к папке k8s
$K8S_PATH = "C:\Users\serjio\Desktop\devops\tms-git\tms-git\todo\k8s"

Write-Host "  → Применяем PV и PVC..." -ForegroundColor Gray
kubectl apply -f "$K8S_PATH\mongo-pv.yaml"

Write-Host "  → Применяем MongoDB..." -ForegroundColor Gray
kubectl apply -f "$K8S_PATH\mongo-deployment.yaml"
kubectl apply -f "$K8S_PATH\mongo-service.yaml"

Write-Host "  → Применяем приложение..." -ForegroundColor Gray
kubectl apply -f "$K8S_PATH\deployment.yaml"
kubectl apply -f "$K8S_PATH\todo-service.yaml"

Write-Host "  → Применяем Ingress..." -ForegroundColor Gray
kubectl apply -f "$K8S_PATH\ingress.yaml"

Write-Host "  → Применяем HPA..." -ForegroundColor Gray
kubectl apply -f "$K8S_PATH\hpa.yaml"

Write-Host "  → Применяем мониторинг..." -ForegroundColor Gray
kubectl apply -f "$K8S_PATH\monitoring\"

#---------------------------------------------------------------
# ШАГ 4: ОЖИДАНИЕ ЗАПУСКА ПОДОВ
#---------------------------------------------------------------
Write-Host "`n⏳ ШАГ 4: Ожидаем запуск всех подов..." -ForegroundColor Yellow

Write-Host "  → Ожидаем MongoDB..." -ForegroundColor Gray
kubectl wait --for=condition=ready pod -l app=mongo --timeout=60s 2>$null

Write-Host "  → Ожидаем приложение..." -ForegroundColor Gray
kubectl wait --for=condition=ready pod -l app=todo --timeout=60s 2>$null

Write-Host "  → Ожидаем Prometheus..." -ForegroundColor Gray
kubectl wait --for=condition=ready pod -l app=prometheus --timeout=60s 2>$null

Write-Host "  → Ожидаем Grafana..." -ForegroundColor Gray
kubectl wait --for=condition=ready pod -l app=grafana --timeout=60s 2>$null

#---------------------------------------------------------------
# ШАГ 5: ЗАПУСК MINIKUBE TUNNEL
#---------------------------------------------------------------
Write-Host "`n🌐 ШАГ 5: Запускаем Minikube tunnel в новом окне..." -ForegroundColor Yellow

$tunnelRunning = Get-Process -Name "minikube" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*tunnel*" }
if (-not $tunnelRunning) {
    Start-Process powershell -ArgumentList "minikube tunnel; Read-Host 'Нажми Enter для закрытия'"
    Write-Host "  ✅ Туннель запущен" -ForegroundColor Green
} else {
    Write-Host "  ⚠️ Туннель уже работает" -ForegroundColor Yellow
}

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
Write-Host "  • Prometheus: http://localhost:9090 (после tunnel)" -ForegroundColor White
Write-Host "  • Grafana:    http://localhost:3000 (admin/admin)" -ForegroundColor White

Write-Host "`n⚠️  Проверь запись в hosts:" -ForegroundColor Yellow
Write-Host "   C:\Windows\System32\drivers\etc\hosts -> 127.0.0.1 todo.local" -ForegroundColor White