#!/bin/bash
# nginx_node.sh – Skrypt, który buduje aplikację front-end w Node.js,
# uruchamia serwer Angular (angular-http-server) i konfiguruje Nginx
# aby przekazywał ruch do tego serwera.
#
# Użycie:
#   ./nginx_node.sh <NGINX_PORT> <MASTER_IP> <SLAVE_IP> <FRONT_PORT>
#
# Parametry:
#   NGINX_PORT   – port, na którym ma nasłuchiwać Nginx (np. 80)
#   MASTER_IP    – adres IP backend master (przekazywany dalej do Nginx, jeżeli wymagany w upstream)
#   SLAVE_IP     – adres IP backend slave (może być użyty w upstream dla backendów – opcjonalnie)
#   FRONT_PORT   – port, na którym ma działać Node.js serwer front-endu (np. 4200)
#
# Repozytorium front-endu (Angular) – jeśli nie przekażesz innego, używany jest domyślny:
#   FRONT_REPO_URL="https://github.com/spring-petclinic/spring-petclinic-angular.git"

NGINX_PORT=$1
MASTER_IP=$2
SLAVE_IP=$3
FRONT_PORT=$4
# Opcjonalny parametr z repozytorium; jeśli nie podano, używamy domyślnego.
FRONT_REPO_URL=${5:-"https://github.com/spring-petclinic/spring-petclinic-angular.git"}

echo "Aktualizacja systemu..."
sudo apt update && sudo apt upgrade -y

echo "Instalacja Nginx..."
sudo apt install -y nginx

echo "Instalacja Node.js przy użyciu nvm..."
curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.8/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm install 16

echo "Klonowanie repozytorium front-end: $FRONT_REPO_URL"
rm -rf ~/spring-petclinic-angular
git clone $FRONT_REPO_URL ~/spring-petclinic-angular
cd ~/spring-petclinic-angular

echo "Aktualizacja plików środowiskowych front-endu..."
# Upewnij się, że aplikacja Angular komunikuje się z API przez adres front VM (czyli 'localhost')
sed -i "s/localhost/localhost/g" src/environments/environment.prod.ts src/environments/environment.ts
# Zamieniamy domyślny port (np. 9966) na port, na którym backend (lub API) będzie dostępny – możesz to zostawić lub zmienić według potrzeb.
sed -i "s/9966/8080/g" src/environments/environment.prod.ts src/environments/environment.ts

echo "Instalacja zależności front-endu oraz budowanie aplikacji..."
npm install
npm run build -- --configuration production

echo "Uruchamianie Node.js serwera do serwowania front-endu..."
# Uruchamiamy angular-http-server, który serwuje statyczne pliki z katalogu 'dist'
nohup npx angular-http-server --path ./dist -p $FRONT_PORT > node_server.out 2> node_server.err &

# --- Konfiguracja Nginx ---
echo "Generowanie konfiguracji Nginx do proxy Node.js serwera front-endu..."
cat > front_proxy.conf << EOF
server {
    listen $NGINX_PORT;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:$FRONT_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Opcjonalnie – możesz dodać konfigurację dla API backendów, korzystając z upstream,
    # ale zakładamy, że front-end komunikuje się wyłącznie z Nginx, a API dostępne są pośrednio.
}
EOF

echo "Przenoszenie konfiguracji do katalogu Nginx..."
sudo mv front_proxy.conf /etc/nginx/conf.d/front_proxy.conf

echo "Testowanie konfiguracji Nginx..."
sudo nginx -t && sudo systemctl restart nginx

echo "Front-end jako aplikacja Node.js został uruchomiony na porcie $FRONT_PORT, a Nginx proxy przekazuje ruch na ten serwer."
