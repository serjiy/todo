#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Определяю директорию проекта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$SCRIPT_DIR/k8s"

# Функция для проверки успешности предыдущей команды
check_success() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo -e "${RED}✗ $1${NC}"
        echo -e "${RED}Скрипт прерван.${NC}"
        exit 1
    fi
}

# Функция ожидания готовности подов
wait_for_pods() {
    local label=$1
    local timeout=$2
    local interval=5
    local elapsed=0
    local ready_count=0
    local total_count=0
    
    echo -e "${YELLOW}⏳ Ожидаю запуск подов с лейблом $label (максимум ${timeout}с)...${NC}"
    
    while [ $elapsed -lt $timeout ]; do
        ready_count=$(kubectl get pods -l $label -o jsonpath='{.items[*].status.containerStatuses[0].ready}' 2>/dev/null | grep -o true | wc -l)
        total_count=$(kubectl get pods -l $label --no-headers 2>/dev/null | wc -l)
        
        if [ "$total_count" -gt 0 ] && [ "$ready_count" -eq "$total_count" ]; then
            echo -e "\n${GREEN}✅ Поды $label запущены (${ready_count}/${total_count})${NC}"
            return 0
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        echo -n "."
    done
    
    echo -e "\n${RED}❌ Таймаут ожидания подов $label (запущено ${ready_count}/${total_count})${NC}"
    return 1
}

# Функция проверки готовности туннеля
wait_for_tunnel() {
    local timeout=60
    local interval=3
    local elapsed=0
    local INGRESS_IP=""
    
    echo -e "${YELLOW}⏳ Проверяю работу туннеля (до ${timeout}с)...${NC}"
    
    for i in {1..10}; do
        INGRESS_IP=$(kubectl get ingress todo-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        if [ -n "$INGRESS_IP" ] && [ "$INGRESS_IP" != "null" ]; then
            break
        fi
        sleep 2
    done
    
    if [ -z "$INGRESS_IP" ] || [ "$INGRESS_IP" = "null" ]; then
        echo -e "\n${YELLOW}⚠️ IP Ingress не получен, использую IP Minikube: $(minikube ip)${NC}"
        INGRESS_IP=$(minikube ip)
    fi
    
    echo -e "${YELLOW}📌 Проверяю доступ приложения по IP: $INGRESS_IP${NC}"
    
    while [ $elapsed -lt $timeout ]; do
        if ! pgrep -f "minikube tunnel" > /dev/null; then
            echo -e "\n${RED}❌ Туннель не запущен${NC}"
            return 1
        fi
        
        if curl -s -o /dev/null -w "%{http_code}" "http://$INGRESS_IP" --connect-timeout 2 --max-time 3 | grep -q "200\|404\|503"; then
            echo -e "\n${GREEN}✅ Туннель работает, приложение доступно${NC}"
            return 0
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        echo -n "."
    done
    
    echo -e "\n${RED}❌ Таймаут ожидания туннеля${NC}"
    return 1
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}🚀 ЗАПУСК ПРОЕКТА TODO${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}📁 Проект находится в: $SCRIPT_DIR${NC}"
echo -e "${YELLOW}📁 Манифесты Kubernetes: $K8S_DIR${NC}"

# Шаг 1: Проверяю Docker
echo -e "\n${YELLOW}[1/13] Проверяю работу Docker...${NC}"
docker ps > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Docker не запущен или нет прав.${NC}"
    echo -e "Выполни: sudo usermod -aG docker $USER и перезагрузись"
    exit 1
fi
echo -e "${GREEN}✓ Docker работает${NC}"

# Шаг 2: Запускаю Minikube
echo -e "\n${YELLOW}[2/13] Запускаю Minikube...${NC}"
if minikube status | grep -q "Running"; then
    echo -e "${GREEN}✓ Minikube уже запущен${NC}"
else
    minikube start --driver=docker
    check_success "Minikube запущен"
fi

# Шаг 3: Включаю Ingress
echo -e "\n${YELLOW}[3/13] Включаю Ingress-контроллер...${NC}"
minikube addons enable ingress
check_success "Ingress включен"

# Шаг 4: Проверяю наличие манифестов
echo -e "\n${YELLOW}[4/13] Проверяю манифесты Kubernetes...${NC}"
if [ ! -d "$K8S_DIR" ]; then
    echo -e "${RED}❌ Папка с манифестами не найдена: $K8S_DIR${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Манифесты найдены${NC}"

# Шаг 5: Разворачиваю основные компоненты
echo -e "\n${YELLOW}[5/13] Разворачиваю приложение в кластере...${NC}"
cd "$K8S_DIR"

kubectl apply -f mongo-pv.yaml
kubectl apply -f mongo-deployment.yaml
kubectl apply -f mongo-service.yaml
kubectl apply -f deployment.yaml
kubectl apply -f todo-service.yaml
kubectl apply -f ingress.yaml
kubectl apply -f hpa.yaml
kubectl apply -f monitoring/
check_success "Основные компоненты развернуты"

# Шаг 6: Разворачиваю Loki
echo -e "\n${YELLOW}[6/13] Разворачиваю Loki...${NC}"
cd "$K8S_DIR/monitoring/loki"
kubectl apply -f loki-config.yaml
kubectl apply -f loki-deployment.yaml
kubectl apply -f loki-service.yaml
check_success "Loki развернут"
cd "$SCRIPT_DIR"

# Шаг 7: Ожидаю запуск MongoDB
echo -e "\n${YELLOW}[7/13] Ожидаю запуск MongoDB...${NC}"
wait_for_pods "app=mongo" 180

# Шаг 8: Ожидаю запуск приложения
echo -e "\n${YELLOW}[8/13] Ожидаю запуск Flask-приложения...${NC}"
wait_for_pods "app=todo" 180

# Шаг 9: Ожидаю запуск Prometheus и Grafana
echo -e "\n${YELLOW}[9/13] Ожидаю запуск Prometheus и Grafana...${NC}"
wait_for_pods "app=prometheus" 120
wait_for_pods "app=grafana" 120

# Шаг 10: Ожидаю запуск Loki
echo -e "\n${YELLOW}[10/13] Ожидаю запуск Loki...${NC}"
wait_for_pods "app=loki" 120

# Шаг 11: Перезапускаю Promtail для подключения к Loki
echo -e "\n${YELLOW}[11/13] Перезапускаю Promtail...${NC}"
kubectl rollout restart daemonset promtail
sleep 5
echo -e "${GREEN}✓ Promtail перезапущен${NC}"

# Шаг 12: Настраиваю туннель для доступа к приложению
echo -e "\n${YELLOW}[12/13] Настраиваю сетевой туннель...${NC}"
pkill -f "minikube tunnel" 2>/dev/null
sleep 2

nohup minikube tunnel > /tmp/minikube-tunnel.log 2>&1 &
TUNNEL_PID=$!
echo -e "${GREEN}✓ Туннель запущен (PID: $TUNNEL_PID)${NC}"
echo -e "${YELLOW}📝 Логи туннеля: tail -f /tmp/minikube-tunnel.log${NC}"

wait_for_tunnel
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️ Туннель ещё настраивается, приложение может быть доступно по IP: $(minikube ip)${NC}"
fi

# Шаг 13: Настраиваю файл hosts и проверяю доступ
echo -e "\n${YELLOW}[13/13] Настраиваю файл hosts и проверяю доступ...${NC}"
MINIKUBE_IP=$(minikube ip)
sudo sed -i '/todo.local/d' /etc/hosts
echo "$MINIKUBE_IP todo.local" | sudo tee -a /etc/hosts > /dev/null

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://todo.local/list --max-time 5)
if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✅ Приложение работает: http://todo.local/list${NC}"
else
    echo -e "${YELLOW}⚠️ Приложение не отвечает, проверь логи туннеля${NC}"
fi

echo -e "\n${BLUE}========================================${NC}"
echo -e "${GREEN}✅ ПРОЕКТ УСПЕШНО ЗАПУЩЕН!${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e ""
echo -e "${YELLOW}📌 Где смотреть:${NC}"
echo -e "   • Приложение: ${GREEN}http://todo.local/list${NC}"
echo -e "   • Grafana:    ${GREEN}minikube service grafana${NC}"
echo -e "   • Prometheus: ${GREEN}minikube service prometheus${NC}"
echo -e ""
echo -e "${YELLOW}📌 Управление проектом:${NC}"
echo -e "   • Логи туннеля: ${GREEN}tail -f /tmp/minikube-tunnel.log${NC}"
echo -e "   • Остановить туннель: ${GREEN}pkill -f 'minikube tunnel'${NC}"
echo -e "   • Остановить кластер: ${GREEN}minikube stop${NC}"