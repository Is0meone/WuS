#!/bin/bash
# back_slave.sh – Konfiguracja MySQL jako slave oraz uruchomienie aplikacji backend na VM slave.
# Użycie: ./back_slave.sh <BACKEND_PORT> <DB_PORT> <DB_USER> <DB_PASSWORD> <MASTER_IP>
# Dla slave baza działa lokalnie, a replikacja ustawiana jest do mastera o adresie $MASTER_IP.

DIRECTORY="$RANDOM"
echo "Tworzenie katalogu: $DIRECTORY"
mkdir ~/$DIRECTORY
cd ~/$DIRECTORY

# Parametry:
BACKEND_PORT=$1
DB_PORT=$2
DB_USER=$3
DB_PASSWORD=$4
MASTER_IP=$5
DB_ADDRESS="localhost"

sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install openjdk-17-jdk -y
sudo apt-get install mysql-server wget -y

# Skonfiguruj MySQL jako slave:
MY_SQL_CONFIG="/etc/mysql/mysql.conf.d/mysqld.cnf"
sudo sed -i "s/127.0.0.1/0.0.0.0/g" $MY_SQL_CONFIG
if ! grep -q "server-id" $MY_SQL_CONFIG; then
    echo "server-id = 2" | sudo tee -a $MY_SQL_CONFIG
else
    sudo sed -i "s/.*server-id.*/server-id = 2/" $MY_SQL_CONFIG
fi
sudo systemctl restart mysql

# Utwórz bazę danych, jeśli nie istnieje:
mysql -uroot -e "CREATE DATABASE IF NOT EXISTS petclinic;"

# Ustawienie replikacji – konfiguracja slave:
mysql -uroot -e "CHANGE MASTER TO MASTER_HOST='$MASTER_IP', MASTER_USER='replicate', MASTER_PASSWORD='slave_pass', MASTER_PORT=$DB_PORT;"
mysql -uroot -e "START SLAVE;"

# Klonowanie repozytorium aplikacji backendowej:
git clone https://github.com/spring-petclinic/spring-petclinic-rest.git ~/petclinic-rest
cd ~/petclinic-rest

# Modyfikacja konfiguracji aplikacji:
sed -i "s/=hsqldb/=mysql/g" src/main/resources/application.properties 
sed -i "s/9966/$BACKEND_PORT/g" src/main/resources/application.properties

sed -i "s/localhost/$DB_ADDRESS/g" src/main/resources/application-mysql.properties
sed -i "s/3306/$DB_PORT/g" src/main/resources/application-mysql.properties
sed -i "s/pc/$DB_USER/g" src/main/resources/application-mysql.properties
sed -i "s/=petclinic/=$DB_PASSWORD/g" src/main/resources/application-mysql.properties

# Uruchomienie aplikacji backend:
nohup ./mvnw spring-boot:run > backend_slave.out 2>&1 &
