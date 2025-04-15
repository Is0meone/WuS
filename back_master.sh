#!/bin/bash
# back_master.sh – Konfiguracja MySQL jako master oraz uruchomienie aplikacji backend na VM master.
# Użycie: ./back_master.sh <BACKEND_PORT> <DB_PORT> <DB_USER> <DB_PASSWORD>
# Dla mastera baza będzie dostępna lokalnie (adres "localhost").

# Utworzenie unikalnego katalogu roboczego:
DIRECTORY="$RANDOM"
echo "Tworzenie katalogu: $DIRECTORY"
mkdir ~/$DIRECTORY
cd ~/$DIRECTORY

# Parametry:
BACKEND_PORT=$1
DB_PORT=$2
DB_USER=$3
DB_PASSWORD=$4
DB_ADDRESS="localhost"

# Aktualizacja systemu i instalacja JDK:
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install openjdk-17-jdk -y

# Instalacja MySQL i narzędzi:
sudo apt-get install mysql-server wget -y

# Skonfiguruj MySQL jako master:
MY_SQL_CONFIG="/etc/mysql/mysql.conf.d/mysqld.cnf"
sudo sed -i "s/127.0.0.1/0.0.0.0/g" $MY_SQL_CONFIG
if ! grep -q "server-id" $MY_SQL_CONFIG; then
    echo "server-id = 1" | sudo tee -a $MY_SQL_CONFIG
else
    sudo sed -i "s/.*server-id.*/server-id = 1/" $MY_SQL_CONFIG
fi
if ! grep -q "log_bin" $MY_SQL_CONFIG; then
    echo "log_bin = /var/log/mysql/mysql-bin.log" | sudo tee -a $MY_SQL_CONFIG
fi
sudo systemctl restart mysql

# Utworzenie bazy danych i użytkowników:
mysql -uroot -e "CREATE DATABASE IF NOT EXISTS petclinic;"
mysql -uroot -e "CREATE USER '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';"
mysql -uroot -e "GRANT ALL PRIVILEGES ON petclinic.* TO '$DB_USER'@'%';"
mysql -uroot -e "CREATE USER 'replicate'@'%' IDENTIFIED BY 'slave_pass';"
mysql -uroot -e "GRANT REPLICATION SLAVE ON *.* TO 'replicate'@'%';"
mysql -uroot -e "FLUSH PRIVILEGES;"

# Klonowanie repozytorium aplikacji backendowej:
git clone https://github.com/spring-petclinic/spring-petclinic-rest.git ~/petclinic-rest
cd ~/petclinic-rest

# Modyfikacja plików konfiguracyjnych:
sed -i "s/=hsqldb/=mysql/g" src/main/resources/application.properties 
sed -i "s/9966/$BACKEND_PORT/g" src/main/resources/application.properties

sed -i "s/localhost/$DB_ADDRESS/g" src/main/resources/application-mysql.properties
sed -i "s/3306/$DB_PORT/g" src/main/resources/application-mysql.properties
sed -i "s/pc/$DB_USER/g" src/main/resources/application-mysql.properties
sed -i "s/=petclinic/=$DB_PASSWORD/g" src/main/resources/application-mysql.properties

# Uruchomienie aplikacji backend (Spring Boot):
nohup ./mvnw spring-boot:run > backend_master.out 2>&1 &
