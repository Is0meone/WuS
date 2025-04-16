#!/bin/bash
# frontend_nginx.sh – Konfiguracja lokalnego Nginx (dla API) oraz uruchomienie front-endu jako aplikacji Node.js.
# Parametry:
#   $1 – FRONT_PORT (port, na którym wystawiany jest front-end, np. 4200)
#   $2 – API_PORT (port, na którym Nginx nasłuchuje lokalnie, np. 3000)
#   $3 – MASTER_IP (adres backend master, użyty w upstream, opcjonalnie)
#   $4 – SLAVE_IP  (adres backend slave, użyty w upstream, opcjonalnie)

FRONT_PORT=$1
API_PORT=$2
MASTER_IP=$3
SLAVE_IP=$4

echo "Konfigurowanie lokalnego Nginx, aby nasłuchiwał na 127.0.0.1:$API_PORT..."

sudo apt update && sudo apt upgrade -y
sudo apt install -y nginx

cat > api_proxy.conf << EOF
upstream petclinic_backend {
    server ${MASTER_IP}:8080;
    server ${SLAVE_IP}:8080;
}

server {
    # Nginx nasłuchuje tylko na adresie loopback
    listen 127.0.0.1:${API_PORT};
    
    location / {
        proxy_pass http://petclinic_backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

sudo mv api_proxy.conf /etc/nginx/conf.d/
sudo nginx -t && sudo systemctl restart nginx

echo "Lokalny Nginx skonfigurowany na porcie $API_PORT."

echo "Instalacja Node.js (nvm)..."
curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.8/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm install 16

echo "Klonowanie repozytorium front-end..."
rm -rf ~/spring-petclinic-angular
git clone https://github.com/spring-petclinic/spring-petclinic-angular.git ~/spring-petclinic-angular
cd ~/spring-petclinic-angular

echo "Aktualizacja plików środowiskowych, ustawienie API na http://localhost:${API_PORT}..."
# Zakładamy, że w plikach environment.ts i environment.prod.ts znajduje się adres API (np. http://localhost:9966)
sed -i "s|http://localhost:[0-9]\{1,\}|http://localhost:${API_PORT}|g" src/environments/environment.ts
sed -i "s|http://localhost:[0-9]\{1,\}|http://localhost:${API_PORT}|g" src/environments/environment.prod.ts

echo "Instalacja zależności front-endu..."
npm install
npm run build -- --configuration production

echo "Uruchamianie Node.js serwera do serwowania front-endu na porcie $FRONT_PORT..."
nohup npx angular-http-server --path ./dist -p $FRONT_PORT > node_front.out 2> node_front.err &

echo "Front-end uruchomiony na porcie $FRONT_PORT. Ruch API jest przekazywany przez lokalny Nginx na porcie $API_PORT."
