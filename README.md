## ToDo List — приложение на Flask + MongoDB

Простое приложение для управления задачами.  
Данные хранятся в MongoDB.  

## ✅ Что сделано

### 🐳 Docker-часть
- Полностью работает через `docker compose up -d`
- Доступен по адресу `http://localhost:5000/list`
- Метрики на `http://localhost:5000/metrics`

### ☸️ Kubernetes-часть (Minikube)
- Разворачивается в Minikube командой `kubectl apply -f k8s/`
- Две реплики Flask-приложения (отказоустойчивость)
- Постоянное хранилище для MongoDB — данные не теряются после перезапуска
- HPA (HorizontalPodAutoscaler) — при нагрузке >50% CPU автоматически добавляет поды (до 5)
- Доступ через Ingress по адресу `http://todo.local/list`

### 📊 Мониторинг
- Prometheus — собирает метрики эндпоинта `/metrics`
- Grafana — готовые дашборды:
  - Запросы в минуту (с разбивкой по HTTP-статусам)
  - Запросы в секунду
  - Использование памяти
  - Время ответа
  - Ошибки
- Все метрики приложения доступны по адресу `/metrics`

### 📜 Логирование (Loki + Promtail)

- Loki — централизованное хранилище логов, легковесная альтернатива Elasticsearch
- Promtail — сборщик логов, работает на каждой ноде и отправляет логи в Loki
- Интеграция с Grafana — логи доступны прямо в интерфейсе Grafana (Explore → Loki)
- Собираются логи — от самого приложения, MongoDB, Prometheus и системных компонентов
- Долговечность — Loki настроен с PersistentVolume, логи не теряются при перезапуске

### 📁 Структура проекта

```
todo/									# Корень проекта
├── app.py                              # Само Flask-приложение. Здесь логика добавления/удаления задач, роуты (/list, /metrics) и счетчики для Prometheus
├── requirements.txt                    # Список зависимостей: Flask, pymongo (для связи с MongoDB), prometheus_client (для метрик)
├── Dockerfile                          # Инструкция, как из кода сделать Docker-образ
├── docker-compose.yml   				# Для локального запуска без Kubernetes: поднимает Flask + MongoDB одной командой 
│             
├── .gitignore                          # Список файлов и папок, которые Git не должен отслеживать (__pycache__, .env, .idea, etc.)
├── .dockerignore                       # Список файлов, которые не должны попадать в Docker-образ (аналог .gitignore для Docker)
├── .github/                            # Всё, что связано с GitHub
│   └── workflows/                      # GitHub Actions — автоматизация при пушах
│       └── ci-cd.yml                   # Пайплайн: при пуше в main собирает образ, пушит в Docker Hub, обновляет тег в манифестах
│
├── k8s/                                # Все манифесты для Kubernetes (декларативное описание того, что должно работать)
│   ├── deployment.yaml                 # Как запускать Flask-приложение: 2 реплики, пробы (liveness/readiness), запросы ресурсов, аннотации для Prometheus
│   ├── todo-service.yaml               # Сервис — постоянный адрес внутри кластера для доступа к подам Flask
│   │
│   ├── mongo-deployment.yaml           # Как запускать MongoDB: 1 реплика, образ, порты
│   ├── mongo-service.yaml              # Сервис для MongoDB — чтобы Flask знал, где искать базу
│   ├── mongo-pv.yaml                   # Постоянное хранилище для MongoDB: PersistentVolume + PVC, чтобы данные не пропадали при перезапуске
│   │
│   ├── ingress.yaml                    # Вход в кластер: правило, что http://todo.local направляется в сервис Flask
│   ├── hpa.yaml                        # HorizontalPodAutoscaler — правило автомасштабирования: если CPU > 50%, добавить поды (до 5)
│   │
│   └── monitoring/                        # Всё для наблюдения за приложением
│       ├── prometheus-config.yaml         # Конфиг Prometheus: откуда забирать метрики (наши поды с аннотациями)
│       ├── prometheus-deployment.yaml     # Сам Prometheus — хранилище метрик
│       ├── prometheus-rbac.yaml           # Права для Prometheus: чтобы мог читать информацию о подах из Kubernetes API
│       ├── prometheus-service.yaml        # Доступ к веб-интерфейсу Prometheus
│       ├── grafana-deployment.yaml        # Grafana — визуализация метрик (рисует графики)
│       ├── grafana-service.yaml           # Доступ к веб-интерфейсу Grafana
│       │
│       └── loki/                           # Стек для сбора логов
│           ├── loki-config.yaml            # Конфиг Loki: как хранить логи, какие папки использовать
│           ├── loki-deployment.yaml        # Loki — само хранилище логов (как Prometheus, только для текста)
│           ├── loki-service.yaml           # Доступ к Loki внутри кластера (чтобы Promtail мог отправлять логи)
│           ├── promtail-config.yaml        # Конфиг Promtail: какие файлы читать, куда отправлять (в Loki)
│           ├── promtail-daemonset.yaml     # Promtail — сборщик логов, запускается на каждой ноде и читает логи всех контейнеров
│           └── promtail-rbac.yaml          # Права для Promtail: чтобы имел доступ к логам на нодах
│
├── templates/                            # HTML-шаблоны (что видит пользователь в браузере)
├── static/                               # CSS, JS, картинки для фронтенда
│
└── start.ps1                             # Скрипт для полного развертывания на Windows одной командой (в разработке)
└── start.sh                              # Скрипт для полного развертывания на Linux (протестировано в Ubuntu 24.04 LTS)
```

## 🚀 Запуск в Windows (локально)

```powershell
1. Запусти Docker Desktop
Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"

2. Запусти ВСЕ существующие контейнеры (которые не запущены)
docker start $(docker ps -a -q -f status=exited -f status=created)

3. Запусти Minikube
minikube start --driver=docker

4. Проверь Minikube
minikube status

5. Примени все манифесты (перейди в папку k8s)
cd C:\*\todo\k8s

kubectl apply -f mongo-pv.yaml
kubectl apply -f mongo-deployment.yaml
kubectl apply -f mongo-service.yaml
kubectl apply -f deployment.yaml
kubectl apply -f todo-service.yaml
kubectl apply -f ingress.yaml
kubectl apply -f hpa.yaml
kubectl apply -f monitoring/

где * путь до папки todo\k8s

6. Запусти туннель (ВАЖНО: окно должно оставаться открытым)
minikube tunnel

7. В новом окне PowerShell проверь поды
kubectl get pods -w

8. Проверь Ingress
kubectl get ingress

9. Открой Grafana
minikube service grafana

10. Открой Prometheus (для проверки)
minikube service prometheus

11. Проверь логи (Loki)
Проверь, что под Loki запустился:
kubectl get pods -l app=loki

В Grafana: Explore → выбери Loki → введи {app="todo"} → Run query
Если Loki нет в списке источников: Configuration → Data Sources → Add → Loki → URL: http://loki:3100

12. Проверь приложение в браузере
http://todo.local/list
```
## ⚠️ Важно для Windows

1. Добавить запись в `C:\Windows\System32\drivers\etc\hosts`:
   ```
   127.0.0.1 todo.local
   ```
2. Docker Desktop должен быть **запущен** перед `minikube start`
3. Туннель (`minikube tunnel`) должен работать **всё время**, пока пользуешься приложением

## 📊 Работа с HPA (автомасштабирование)

```powershell
Посмотреть все HPA в кластере
kubectl get hpa

Посмотреть конкретный HPA
kubectl get hpa todo-app-hpa

Следить за HPA в реальном времени
kubectl get hpa -w
```

### 🐧 Запуск в Linux (автоматический)

Для Linux (проверено на Ubuntu 22.04/24.04) весь процесс развёртывания автоматизирован с помощью скрипта **`start.sh`**. Находится в корневой папке проекта.

```bash
1. Сделай скрипт исполняемым
chmod +x ~/todo/start.sh

2. Запусти развёртывание
~/todo/start.sh
```

**Что сделает скрипт:**
* Проверит работу Docker и права пользователя
* Запустит Minikube (если ещё не запущен)
* Включит Ingress-контроллер
* Последовательно применит все манифесты из `k8s/`:
  * Постоянное хранилище для MongoDB
  * MongoDB, приложение, сервисы, Ingress, HPA
  * Prometheus и Grafana
  * Loki и Promtail
* Ожидает полного запуска всех компонентов
* Запускает `minikube tunnel` в фоновом режиме
* Автоматически настраивает `/etc/hosts` (IP кластера)
* Проверяет доступность приложения

**После успешного выполнения:**
* Приложение будет доступно по адресу `http://todo.local/list`
* Мониторинг открывается командами `minikube service grafana` и `minikube service prometheus`
* Логи туннеля можно смотреть: `tail -f /tmp/minikube-tunnel.log`

### ⚙️ CI/CD (GitHub Actions)

**Полностью автоматизированный пайплайн — при каждом пуше в ветку main:**
- Автоматически собирается Docker-образ приложения
- Пушится в Docker Hub (serjiy/todo) https://hub.docker.com/repository/docker/serjiy/todo/general с двумя тегами:
1. latest — актуальная версия
2. Уникальный тег вида 20260219-101831-fe63054 (дата+время+хэш коммита) — для откатов и истории
- Автоматически обновляется файл k8s/deployment.yaml в репозитории — в него подставляется новый тег образа
- Работает через GitHub Actions

### 🤖 Telegram-уведомления

**Доступны статусы каждого деплоя**

* В CI/CD пайплайн добавлена интеграция с Telegram
* При каждом пуше в ветку `main` приходит сообщение:
  * ✅ — если всё прошло успешно
  * ❌ — если что-то упало
* В уведомлении видно:
  * Репозиторий и ветку
  * Автора коммита
  * Сообщение коммита
  * Прямую ссылку на запуск в Actions
* Настроено через GitHub Actions и переменные окружения:
  * `TELEGRAM_TOKEN` — токен бота
  * `TELEGRAM_CHAT_ID` — ID чата для уведомлений


