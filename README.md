# ToDo List — приложение на Flask + MongoDB

Простое приложение для управления задачами.   
Данные хранятся в MongoDB.  
Приложение отдаёт метрики в формате Prometheus по адресу `/metrics`.

На текущий момент проект умеет:

- Полностью работать через Docker Compose (локальный запуск одной командой)
- Разворачиваться в Minikube (Kubernetes) с двумя репликами приложения
- Доступен по адресу http://todo.local (через Ingress)
- Иметь встроенные метрики (количество задач, HTTP-запросы, память, CPU, GC и т.д.)
- Запускаться стабильно после перезапуска Docker и Minikube

## Как запустить локально (Docker Compose)

Самый простой способ:

```bash
docker compose up -d
```

После запуска открывайте:

- http://localhost:5000/list  
- http://localhost:5000/metrics (метрики)

Это запускает два контейнера:  
- `flask-app` — само приложение  
- `mongo` — база данных

Остановить:

```bash
docker compose down
```

## Как запустить в Kubernetes (Minikube)

1. Запустите Minikube:

   ```bash
   minikube start --driver=docker
   ```

2. Запустите tunnel:

   ```bash
   minikube tunnel
   ```

   Оставьте окно открытым.

3. Разверните приложение:

   ```bash
   kubectl apply -f k8s/
   ```

4. Подождите 30–60 секунд.

5. Откройте в браузере:

   http://todo.local/list  
   http://todo.local/metrics

## Структура проекта

```
todo/
├── app.py                  # основная логика: Flask, маршруты, задачи, метрики
├── requirements.txt        # зависимости Python
├── Dockerfile              # сборка Docker-образа приложения
├── docker-compose.yml      # запуск Flask + MongoDB локально
├── k8s/                    # файлы для Kubernetes
│   ├── deployment.yaml     # запуск приложения (2 реплики)
│   ├── mongo-deployment.yaml # запуск MongoDB
│   ├── services.yaml       # доступ к приложению и базе
│   ├── ingress.yaml        # домен todo.local
│   └── service-monitor.yaml # настройка сбора метрик (в процессе)
└── templates/              # HTML-шаблоны страниц
└── static/                 # CSS, JS, картинки
```

## Требования к окружению

- Docker Desktop (запущенный)
- Minikube (для Kubernetes-варианта)
- kubectl (идёт вместе с Minikube)
- Браузер
- Запись в файле hosts:  
  ```
  127.0.0.1 todo.local
  ```

В планах

- Автоматическое масштабирование подов (HPA)
- Постоянное хранилище для MongoDB (PersistentVolume)
- Автоматическая сборка и деплой через GitHub Actions (CI/CD)
- Удобная визуализация метрик (графики задач, запросов, ресурсов)
- Сбор логов приложения

Проект уже стабильно запускается локально и в Minikube.  
Можно добавлять задачи, смотреть метрики, перезапускать — всё работает.