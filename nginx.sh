#!/bin/bash
# nginx.sh – Konfiguracja Nginx jako load balancer oraz wdrożenie front-endu na VM front
# Parametry:
#   $1 – port, na którym Nginx będzie nasłuchiwał (np. 80)
#   $2 – adres IP backend master (np. 10.0.1.4)
#   $3 – adres IP backend slave (np. 10.0.1.5)
#   (Dodatkowo możesz dodać parametr z repozytorium front-end, ale poniżej przyjmujemy, że jest hardkodowany.)

NGINX_PORT=$1
MASTER_IP=$2
SLAVE_IP=$3
FRONT_REPO_URL="https://github.com/spring-petclinic/spring-petclinic-angular.git"

# Aktualizacja systemu oraz instalacja Nginx
sudo apt update && sudo apt upgrade -y
sudo apt install -y nginx

# --- Krok 1: Konfiguracja Nginx jako reverse proxy dla backendów ---
cat > loadbalancer.conf << EOL
upstream petclinic_backend {
    server ${MASTER_IP}:8080;
    server ${SLAVE_IP}:8080;
}

server {
    listen      ${NGINX_PORT} default_server;
    server_name _;

    root /var/www/html;
    index index.html index.htm;

    # Single-Page App – jeśli plik nie istnieje, zwróć index.html
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Przekierowanie zapytań REST API do backendów
    location /petclinic/api/ {
        proxy_pass         http://petclinic_backend;
        proxy_set_header   Host                \$host;
        proxy_set_header   X-Real-IP           \$remote_addr;
        proxy_set_header   X-Forwarded-For     \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto   \$scheme;
    }
}
EOL

sudo mv loadbalancer.conf /etc/nginx/conf.d/loadbalancer.conf
sudo rm /etc/nginx/sites-enabled/default
# --- Krok 2: Wdrożenie front-endu ---
# Instalacja narzędzi Node.js przez nvm (jeśli nie jest zainstalowany)
curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.8/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
nvm install 16

# Klonowanie repozytorium front-endu:
rm -rf ~/spring-petclinic-angular
git clone $FRONT_REPO_URL ~/spring-petclinic-angular
cd ~/spring-petclinic-angular

# Zaktualizuj pliki środowiskowe, aby front-end komunikował się z Nginx (adres VM front, czyli sam siebie)
# Załóżmy, że aplikacja Angular odwołuje się do API przez adres "localhost" na porcie np. 80.
sed -i "s|REST_API_URL: *'.*'|REST_API_URL: window.location.origin + '/petclinic/api/'|g" \
  src/environments/environment.ts \
  src/environments/environment.prod.ts

npm install
npm run build -- --configuration production

# Skopiowanie wynikowych statycznych plików do katalogu, który serwuje Nginx
sudo rm -rf /var/www/html/*
sudo cp -R dist/* /var/www/html/

# --- Krok 3: Restart Nginx, aby wczytał nową konfigurację ---
sudo nginx -t && sudo systemctl restart nginx

echo "Front-end został zbudowany i wdrożony wraz z konfiguracją Nginx."
