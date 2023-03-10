#!/bin/bash
#shellcheck source=/dev/null

set -e

########################################################
# 
#         Pterodactyl-AutoAddons Installation
#
#         Created and maintained by Ferks-FK
#
#            Protected by GPL 3.0 License
#
########################################################

#### Fixed Variables ####

SCRIPT_VERSION="PhpMyAdmin-Installer"
PHPMYADMIN_VERSION="5.1.3"
SUPPORT_LINK="https://discord.gg/buDBbSGJmQ"


#### Set functions to false by default ####

CONFIGURE_UFW=false
CONFIGURE_UFW_CMD=false
CONFIGURE_FIREWALL=false
CONFIGURE_SSL=false

#### Github URL's ####

GITHUB="https://raw.githubusercontent.com/Ferks-FK/Pterodactyl-AutoAddons/$SCRIPT_VERSION"

#### Functions for visual styles ####

GREEN="\e[0;92m"
YELLOW="\033[1;33m"
red='\033[0;31m'
reset="\e[0m"

print_brake() {
  for ((n = 0; n < $1; n++)); do
    echo -n "#"
  done
  echo ""
}

print_warning() {
  echo ""
  echo -e "* ${YELLOW}WARNING${reset}: $1"
  echo ""
}

print_error() {
  echo ""
  echo -e "* ${red}ERROR${reset}: $1"
  echo ""
}

print_success() {
  echo ""
  echo -e "* ${GREEN}SUCCESS${reset}: $1"
  echo ""
}

print() {
  echo ""
  echo -e "${GREEN}* $1 ${reset}"
  echo ""
}

hyperlink() {
  echo -e "\e]8;;${1}\a${1}\e]8;;\a"
}

# regex for email
regex="^(([A-Za-z0-9]+((\.|\-|\_|\+)?[A-Za-z0-9]?)*[A-Za-z0-9]+)|[A-Za-z0-9]+)@(([A-Za-z0-9]+)+((\.|\-|\_)?([A-Za-z0-9]+)+)*)+\.([A-Za-z]{2,})+$"

valid_email() {
  [[ $1 =~ ${regex} ]]
}

email_input() {
  local __resultvar=$1
  local result=''

  while ! valid_email "$result"; do
    echo -n "* ${2}"
    read -r result

    valid_email "$result" || print_error "${3}"
  done

  eval "$__resultvar="'$result'""
}

password_input() {
  local __resultvar=$1
  local result=''
  local default="$4"

  while [ -z "$result" ]; do
    echo -n "* ${2}"
    while IFS= read -r -s -n1 char; do
      [[ -z $char ]] && {
        printf '\n'
        break
      }
      if [[ $char == $'\x7f' ]]; then
        if [ -n "$result" ]; then
          [[ -n $result ]] && result=${result%?}
          printf '\b \b'
        fi
      else
        result+=$char
        printf '*'
      fi
    done
    [ -z "$result" ] && [ -n "$default" ] && result="$default"
    [ -z "$result" ] && print_error "${3}"
  done

  eval "$__resultvar="'$result'""
}


#### OS check ####

check_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$(echo "$ID" | awk '{print tolower($0)}')
    OS_VER=$VERSION_ID
  elif type lsb_release >/dev/null 2>&1; then
    OS=$(lsb_release -si | awk '{print tolower($0)}')
    OS_VER=$(lsb_release -sr)
  elif [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    OS=$(echo "$DISTRIB_ID" | awk '{print tolower($0)}')
    OS_VER=$DISTRIB_RELEASE
  elif [ -f /etc/debian_version ]; then
    OS="debian"
    OS_VER=$(cat /etc/debian_version)
  elif [ -f /etc/SuSe-release ]; then
    OS="SuSE"
    OS_VER="?"
  elif [ -f /etc/redhat-release ]; then
    OS="Red Hat/CentOS"
    OS_VER="?"
  else
    OS=$(uname -s)
    OS_VER=$(uname -r)
  fi

  OS=$(echo "$OS" | awk '{print tolower($0)}')
  OS_VER_MAJOR=$(echo "$OS_VER" | cut -d. -f1)
}

#### Check if OS is supported ####

check_support_os() {
case "$OS" in
  ubuntu)
    PHP_SOCKET="/run/php/php8.0-fpm.sock"
    [ "$OS_VER_MAJOR" == "18" ] && SUPPORTED=true
    [ "$OS_VER_MAJOR" == "20" ] && SUPPORTED=true
    ;;
  debian)
    PHP_SOCKET="/run/php/php8.0-fpm.sock"
    [ "$OS_VER_MAJOR" == "9" ] && SUPPORTED=true
    [ "$OS_VER_MAJOR" == "10" ] && SUPPORTED=true
    [ "$OS_VER_MAJOR" == "11" ] && SUPPORTED=true
    ;;
  centos)
    PHP_SOCKET="/var/run/php-fpm/phpmyadmin.sock"
    [ "$OS_VER_MAJOR" == "7" ] && SUPPORTED=true
    [ "$OS_VER_MAJOR" == "8" ] && SUPPORTED=true
    [ "$OS_VER_MAJOR" == "9" ] && SUPPORTED=true
    ;;
  *)
    SUPPORTED=false
    ;;
esac

if [ "$SUPPORTED" == true ]; then
    print "Checking that your OS is compatible with the script..."
    sleep 3
    print "$OS $OS_VER is supported."
  else
    echo "* $OS $OS_VER is not supported"
    print_error "Unsupported OS"
    exit 1
fi
}

# Other OS Functions #

enable_all_services_debian() {
systemctl enable "$WEB_SERVER" --now
systemctl enable mariadb --now
}

enable_all_services_centos() {
if [[ "$WEB_SERVER" == "nginx" ]]; then
    systemctl enable nginx --now
  elif [[ "$WEB_SERVER" == "apache2" ]]; then
    systemctl enable httpd --now
fi
systemctl enable mariadb --now
}

restart_all_services_debian() {
systemctl restart "$WEB_SERVER"
systemctl restart mariadb
systemctl restart php-fpm
}

restart_all_services_centos() {
if [[ "$WEB_SERVER" == "nginx" ]]; then
    systemctl restart nginx
    systemctl restart mariadb
    systemctl restart php-fpm
  elif [[ "$WEB_SERVER" == "apache2" ]]; then
    systemctl restart httpd
    systemctl restart mariadb
    systemctl restart php-fpm
fi
}

centos_php() {
curl -so /etc/php-fpm.d/www.phpmyadmin.conf $GITHUB/features/PhpMyAdmin/configs/www.phpmyadmin.conf

[ "$WEB_SERVER" == "nginx" ] && sed -i -e "s@<web_server>@nginx@g" /etc/php-fpm.d/www.phpmyadmin.conf
[ "$WEB_SERVER" == "apache2" ] && sed -i -e "s@<web_server>@apache@g" /etc/php-fpm.d/www.phpmyadmin.conf

systemctl enable php-fpm --now
}

# Ask which web server the user wants to use #

web_server_menu() {
WEB_SERVER="nginx"
echo
echo -ne "* Choose your Web-Server\n1) Nginx (${YELLOW}Default${reset})\n2) Apache2 "
read -r WEB_SERVER
case "$WEB_SERVER" in
  "")
    WEB_SERVER="nginx"
    ;;
  1)
    WEB_SERVER="nginx"
    ;;
  2)
    WEB_SERVER="apache2"
    ;;
  *)
    print_error "This option does not exist!"
    web_server_menu
    ;;
  esac
}

ask_ssl() {
email=""
echo -n "* Do you want to generate SSL certificate for your domain? (y/N): "
read -r ASK_SSL
if [[ "$ASK_SSL" =~ [Yy] ]]; then
  CONFIGURE_SSL=true
  # Ask the email only if the SSL is true #
  email_input email "Enter an email address that will be used for the creation of the SSL certificate: " "The email address must not be invalid or empty"
  # Ask if you want to configure UFW only if SSL is true #
  ask_ufw
fi
}

ask_ufw() {
print_warning "If you want phpmyadmin to be accessed externally, allow the script to configure the firewall.
Otherwise you may have problems accessing it outside your local network."
echo -n "* Would you like to open the ports on the firewall for external access? (y/N): "
read -r ASK_UFW
if [[ "$ASK_UFW" =~ [Yy] ]]; then
  case "$OS" in
    debian | ubuntu)
    CONFIGURE_UFW=true
    CONFIGURE_FIREWALL=true
    ;;
    centos)
    CONFIGURE_UFW_CMD=true
    CONFIGURE_FIREWALL=true
    ;;
  esac
fi
}

check_fqdn() {
print "Checking FQDN..."
sleep 2
IP="$(curl -s https://ipecho.net/plain ; echo)"
CHECK_DNS="$(dig +short @8.8.8.8 "$FQDN" | tail -n1)"
if [[ "$IP" != "$CHECK_DNS" ]]; then
    print_error "Your FQDN (${YELLOW}$FQDN${reset}) is not pointing to the public IP (${YELLOW}$IP${reset}), please make sure your domain is set correctly."
    echo -n "* Would you like to check again? (y/N): "
    read -r CHECK_DNS_AGAIN
    [[ "$CHECK_DNS_AGAIN" =~ [Yy] ]] && check_fqdn
    [[ "$CHECK_DNS_AGAIN" == [a-xA-X]* ]] && print_error "Installation aborted!" && exit 1
  else
    print_success "DNS successfully verified!"
fi
}

configure_ufw() {
apt-get install -y ufw

print " Opening port 22 (SSH), 80 (HTTP) and 443 (HTTPS)"

ufw allow ssh >/dev/null
ufw allow http >/dev/null
ufw allow https >/dev/null

ufw --force enable
ufw --force reload
ufw status numbered | sed '/v6/d'
}

configure_ufw_cmd() {
[ "$OS_VER_MAJOR" == "7" ] && yum -y -q install firewalld >/dev/null
[ "$OS_VER_MAJOR" == "8" ] && dnf -y -q install firewalld >/dev/null

systemctl --now enable firewalld >/dev/null

print "Opening port 22 (SSH), 80 (HTTP) and 443 (HTTPS)"

firewall-cmd --add-service=http --permanent -q
firewall-cmd --add-service=https --permanent -q
firewall-cmd --add-service=ssh --permanent -q
firewall-cmd --reload -q
}

inicial_deps() {
print "Downloading packages required for FQDN validation..."

case "$OS" in
  debian | ubuntu)
    apt-get update -y && apt-get install -y dnsutils
  ;;
  centos)
    if [[ "$OS_VER_MAJOR" == "7" ]]; then
        yum update -y && yum install -y bind-utils
      elif [[ "$OS_VER_MAJOR" == "8" ]]; then
        dnf update -y && dnf install -y bind-utils
    fi
  ;;
esac
}

deps_ubuntu() {
print "Installing dependencies for Ubuntu $OS_VER..."

apt-get install -y software-properties-common curl apt-transport-https ca-certificates gnupg

[ "$OS_VER_MAJOR" == "18" ] && add-apt-repository universe

LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php

curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash

apt-get update -y && apt-get upgrade -y

apt-get install -y php8.0 php8.0-{mbstring,fpm,cli,zip,gd,xml,curl,mysql} "$WEB_SERVER" mariadb-server tar zip unzip

[ "$WEB_SERVER" == "apache2" ] && apt-get install -y libapache2-mod-php8.0

enable_all_services_debian
}

deps_debian() {
print "Installing dependencies for Debian $OS_VER..."

apt-get install -y dirmngr

apt-get install -y ca-certificates apt-transport-https lsb-release
wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list

[ "$OS_VER_MAJOR" == "9" ] && curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash

apt-get update -y && apt-get upgrade -y

apt-get install -y php8.0 php8.0-{mbstring,fpm,cli,zip,gd,xml,curl,mysql} "$WEB_SERVER" mariadb-server tar zip unzip

[ "$WEB_SERVER" == "apache2" ] && apt-get install -y libapache2-mod-php8.0

enable_all_services_debian
}

deps_centos() {
if [ "$OS_VER_MAJOR" == "7" ]; then
    print "Installing dependencies for CentOS $OS_VER..."

    yum install -y policycoreutils policycoreutils-python selinux-policy selinux-policy-targeted libselinux-utils setroubleshoot-server setools setools-console mcstrans

    yum install -y epel-release http://rpms.remirepo.net/enterprise/remi-release-7.rpm
    yum install -y yum-utils
    yum-config-manager -y --disable remi-php54
    yum-config-manager -y --enable remi-php80
    yum update -y

    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash

    yum install -y php php-mbstring php-fpm php-cli php-zip php-gd php-xml php-curl php-mysql mariadb-server tar zip unzip

    [ "$WEB_SERVER" == "nginx" ] && yum install -y epel-release && yum install -y nginx
    [ "$WEB_SERVER" == "apache2" ] && yum install -y httpd

    enable_all_services_centos
  elif [ "$OS_VER_MAJOR" == "8" ]; then
    print "Installing dependencies for CentOS $OS_VER..."

    dnf install -y policycoreutils selinux-policy selinux-policy-targeted setroubleshoot-server setools setools-console mcstrans

    dnf install -y epel-release http://rpms.remirepo.net/enterprise/remi-release-8.rpm
    dnf module enable -y php:remi-8.0
    dnf upgrade -y

    dnf install -y php php-mbstring php-fpm php-cli php-zip php-gd php-xml php-curl php-mysql tar zip unzip

    dnf install -y mariadb-server

    [ "$WEB_SERVER" == "nginx" ] && dnf install -y nginx
    [ "$WEB_SERVER" == "apache2" ] && dnf install -y httpd

    enable_all_services_centos
  elif [ "$OS_VER_MAJOR" == "9" ]; then
    print "Installing dependencies for CentOS $OS_VER..."

    dnf install -y policycoreutils selinux-policy selinux-policy-targeted setroubleshoot-server setools setools-console mcstrans

    dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
    dnf install -y dnf-utils http://rpms.remirepo.net/enterprise/remi-release-9.rpm
    dnf update -y --refresh
    dnf module enable -y php:remi-8.0

    dnf upgrade -y

    dnf install --skip-broken -y php php-mbstring php-fpm php-cli php-zip php-gd php-xml php-curl php-mysql tar zip unzip

    dnf install -y mariadb-server

    [ "$WEB_SERVER" == "nginx" ] && dnf install -y nginx
    [ "$WEB_SERVER" == "apache2" ] && dnf install -y httpd

    enable_all_services_centos
fi
}

download_files() {
print "Downloading files from phpmyadmin..."

mkdir -p "/var/www/phpmyadmin"
cd "/var/www/phpmyadmin"
mkdir -p tmp
curl -sSLo phpMyAdmin-"${PHPMYADMIN_VERSION}"-all-languages.tar.gz https://files.phpmyadmin.net/phpMyAdmin/"${PHPMYADMIN_VERSION}"/phpMyAdmin-"${PHPMYADMIN_VERSION}"-all-languages.tar.gz
tar -xzvf phpMyAdmin-"${PHPMYADMIN_VERSION}"-all-languages.tar.gz
cd phpMyAdmin-"${PHPMYADMIN_VERSION}"-all-languages
mv -- * "/var/www/phpmyadmin"
cd "/var/www/phpmyadmin"
rm -r phpMyAdmin-"${PHPMYADMIN_VERSION}"-all-languages phpMyAdmin-"${PHPMYADMIN_VERSION}"-all-languages.tar.gz config.sample.inc.php
curl -sSLo config.inc.php https://raw.githubusercontent.com/Ferks-FK/Pterodactyl-AutoAddons/${SCRIPT_VERSION}/features/PhpMyAdmin/configs/config.inc.php
}

configure_phpmyadmin() {
print "Configuring phpmyadmin..."

PHPMYADMIN_PASSWORD="$(openssl rand -base64 32)"
KEY="$(openssl rand -base64 32)"

mysql -u root -e "CREATE USER 'pma'@'127.0.0.1' IDENTIFIED BY '${PHPMYADMIN_PASSWORD}';"
mysql -u root -e "CREATE DATABASE phpmyadmin;"
mysql -u root -e "GRANT ALL PRIVILEGES ON phpmyadmin.* TO 'pma'@'127.0.0.1';"
mysql -u root -e "FLUSH PRIVILEGES;"
cd "/var/www/phpmyadmin/sql"
mysql -u root "phpmyadmin" < create_tables.sql
mysql -u root "phpmyadmin" < upgrade_tables_mysql_4_1_2+.sql
mysql -u root "phpmyadmin" < upgrade_tables_4_7_0+.sql

sed -i -e "s@<key>@$KEY@g" "/var/www/phpmyadmin/config.inc.php"
sed -i -e "s@<password>@$PHPMYADMIN_PASSWORD@g" "/var/www/phpmyadmin/config.inc.php"
}

set_permissions() {
print "Setting Permissions..."

cd /etc
mkdir -p phpmyadmin
cd phpmyadmin
mkdir -p save upload
case "$OS" in
  debian | ubuntu)
  [ "$WEB_SERVER" == "nginx" ] && chown -R www-data:www-data /var/www/phpmyadmin
  [ "$WEB_SERVER" == "apache2" ] && chown -R www-data:www-data /var/www/phpmyadmin
  ;;
  centos)
  [ "$WEB_SERVER" == "nginx" ] && chown -R nginx:nginx /var/www/phpmyadmin
  [ "$WEB_SERVER" == "apache2" ] && chown -R apache:apache /var/www/phpmyadmin
  ;;
esac
chmod -R 660 /etc/phpmyadmin
chmod 700 /var/www/phpmyadmin/tmp
}

create_user_login() {
print "Creating user access for the panel..."

mysql -u root -e "CREATE USER '${USERNAME}'@'%' IDENTIFIED BY '${PASSWORD}';"
mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO '${USERNAME}'@'%';"
mysql -u root -e "FLUSH PRIVILEGES;"
}

configure_web_server() {
print "Configuring ${WEB_SERVER}..."

if [ "$WEB_SERVER" == "nginx" ]; then
    [ "$CONFIGURE_SSL" == true ] && WEB_FILE="nginx_ssl.conf"
    [ "$CONFIGURE_SSL" == false ] && WEB_FILE="nginx.conf"
  elif [ "$WEB_SERVER" == "apache2" ]; then
    [ "$CONFIGURE_SSL" == true ] && WEB_FILE="apache_ssl.conf"
    [ "$CONFIGURE_SSL" == false ] && WEB_FILE="apache.conf"
fi

case "$OS" in
  debian | ubuntu)
    if [ "$WEB_SERVER" == "nginx" ]; then
        rm -rf /etc/nginx/sites-enabled/default

        curl -so /etc/nginx/sites-available/phpmyadmin.conf $GITHUB/features/PhpMyAdmin/configs/$WEB_FILE

        sed -i -e "s@<domain>@${FQDN}@g" /etc/nginx/sites-available/phpmyadmin.conf

        sed -i -e "s@<php_socket>@${PHP_SOCKET}@g" /etc/nginx/sites-available/phpmyadmin.conf

        [ "$OS" == "debian" ] && [ "$OS_VER_MAJOR" == "9" ] && sed -i 's/ TLSv1.3//' /etc/nginx/sites-available/phpmyadmin.conf

        ln -s /etc/nginx/sites-available/phpmyadmin.conf /etc/nginx/sites-enabled/phpmyadmin.conf
      elif [ "$WEB_SERVER" == "apache2" ]; then
        rm -rf /etc/apache2/sites-available/000-default.conf default-ssl.conf
        rm -rf /etc/apache2/sites-enabled/000-default.conf
        rm -rf /var/www/html

        curl -so /etc/apache2/sites-available/phpmyadmin.conf $GITHUB/features/PhpMyAdmin/configs/$WEB_FILE

        sed -i -e "s@<domain>@${FQDN}@g" /etc/apache2/sites-available/phpmyadmin.conf

        # Fix "AH00558: apache2: Could not reliably determine the server's fully qualified domain name" #
        sed -i -e "\$a ServerName ${FQDN}" /etc/apache2/apache2.conf

        ln -s /etc/apache2/sites-available/phpmyadmin.conf /etc/apache2/sites-enabled/phpmyadmin.conf
    fi
  ;;
  centos)
    if [ "$WEB_SERVER" == "nginx" ]; then
        rm -rf /etc/nginx/conf.d/default

        curl -so /etc/nginx/conf.d/phpmyadmin.conf $GITHUB/features/PhpMyAdmin/configs/$WEB_FILE

        sed -i -e "s@<domain>@${FQDN}@g" /etc/nginx/conf.d/phpmyadmin.conf

        sed -i -e "s@<php_socket>@${PHP_SOCKET}@g" /etc/nginx/conf.d/phpmyadmin.conf
      elif [ "$WEB_SERVER" == "apache2" ]; then
        #rm -rf /etc/nginx/conf.d/default

        mkdir -p /etc/httpd/sites-available
        mkdir -p /etc/httpd/sites-enabled

        curl -so /etc/httpd/sites-available/phpmyadmin.conf $GITHUB/features/PhpMyAdmin/configs/$WEB_FILE

        sed -i -e "s@<domain>@${FQDN}@g" /etc/httpd/sites-available/phpmyadmin.conf

        # Fix "AH00558: apache2: Could not reliably determine the server's fully qualified domain name" #
        sed -i -e "\$a ServerName ${FQDN}" /etc/httpd/conf/httpd.conf

        sed -i -e "\$a IncludeOptional sites-enabled/*.conf" /etc/httpd/conf/httpd.conf

        ln -s /etc/httpd/sites-available/phpmyadmin.conf /etc/httpd/sites-enabled/phpmyadmin.conf

        # If SElinux is enabled, change some policies to avoid errors #
        setsebool -P httpd_can_network_connect on
        setsebool -P httpd_execmem on
        setsebool -P httpd_unified on
        chcon -R -t httpd_sys_rw_content_t /var/www/phpmyadmin/tmp
    fi
  ;;
esac
}

restart_services() {
print "Restarting all services..."

case "$OS" in
  debian | ubuntu)
    restart_all_services_debian
  ;;
  centos)
    restart_all_services_centos
  ;;
esac
}

install_phpmyadmin() {
print "Starting installation, this may take a few minutes, please wait."
sleep 3

case "$OS" in
  debian | ubuntu)
  apt-get update -y && apt-get upgrade -y

  [ "$CONFIGURE_UFW" == true ] && configure_ufw

  [ "$OS" == "ubuntu" ] && deps_ubuntu
  [ "$OS" == "debian" ] && deps_debian
  ;;
  centos)

  [ "$CONFIGURE_UFW_CMD" == true ] && configure_ufw_cmd

  deps_centos
  centos_php
  ;;
esac

download_files
configure_phpmyadmin
set_permissions
create_user_login
configure_web_server
restart_services
bye
}

main() {
# Make sure phpmyadmin is already installed #
if [ -d "/var/www/phpmyadmin" ]; then
  print_warning "PhpMyAdmin is already installed, canceling installation..."
  exit 1
fi

# Exec Check Distro #
check_distro

# Exec Supported OS #
check_support_os

# Ask which user to log into the panel #
echo -ne "* Username to login to your panel (${YELLOW}phpmyadmin${reset}): "
read -r USERNAME
[ -z "$USERNAME" ] && USERNAME="phpmyadmin"

# Ask the user password to log into the panel #
password_input PASSWORD "Password for login to your panel: " "The password cannot be empty!"

# Set FQDN for phpmyadmin #
FQDN=""
while [ -z "$FQDN" ]; do
  echo -ne "* Set the Hostname/FQDN for phpmyadmin (${YELLOW}mysql.example.com${reset}): "
  read -r FQDN
  [ -z "$FQDN" ] && print_error "FQDN cannot be empty"
  echo -ne "* This is the Hostname/FQDN you entered: (${YELLOW}$FQDN${reset}), is this correct? (y/N): "
  read -r CONFIRM_FQDN
  if [[ "$CONFIRM_FQDN" =~ [Nn] ]]; then
    while [ -z "$FQDN" ] || [[ "$CONFIRM_FQDN" =~ [Nn] ]]; do
      echo -ne "* Set the FQDN for phpmyadmin (${YELLOW}mysql.example.com${reset}): "
      read -r FQDN
      [ -z "$FQDN" ] && print_error "FQDN cannot be empty"
      echo -ne "* This is the Hostname/FQDN you entered: (${YELLOW}$FQDN${reset}), is this correct? (y/N): "
      read -r CONFIRM_FQDN
    done
  fi
done

# Install the packages to check FQDN and ask about SSL only if FQDN is a string #
if [[ "$FQDN" == [a-zA-Z]* ]]; then
  inicial_deps
  check_fqdn
  ask_ssl
fi

# Run the web-server chooser menu #
web_server_menu

# Summary #
echo
print_brake 75
echo
echo -e "* PhpMyAdmin Version (${YELLOW}$PHPMYADMIN_VERSION${reset}) with Web-Server (${YELLOW}$WEB_SERVER${reset}) in OS (${YELLOW}$OS $OS_VER${reset})"
echo -e "* PhpMyAdmin Login: $USERNAME"
echo -e "* PhpMyAdmin Password: (censored)"
[ "$CONFIGURE_SSL" == true ] && echo -e "* Email Certificate: $email"
echo -e "* Hostname/FQDN: $FQDN"
echo -e "* Configure Firewall: $CONFIGURE_FIREWALL"
echo -e "* Configure SSL: $CONFIGURE_SSL"
echo
print_brake 75
echo

# Confirm all the choices #
echo -n "* Initial settings complete, do you want to continue to the installation? (y/N): "
read -r CONTINUE_INSTALL
[[ "$CONTINUE_INSTALL" =~ [Yy] ]] && install_phpmyadmin
[[ "$CONTINUE_INSTALL" == [a-xA-X]* ]] && print_error "Installation aborted!" && exit 1
}

bye() {
  echo
  print_brake 70
  echo
  echo -e "${GREEN}* The script has finished the installation process!${reset}"

  [ "$CONFIGURE_SSL" == true ] && APP_URL="https://$FQDN"
  [ "$CONFIGURE_SSL" == false ] && APP_URL="http://$FQDN"

  echo -e "${GREEN}* Your panel should be accessible through the link: ${YELLOW}$(hyperlink "$APP_URL")${reset}"
  echo -e "${GREEN}* Thank you for using this script!"
  echo -e "* Support Group: ${YELLOW}$(hyperlink "$SUPPORT_LINK")${reset}"
  echo
  print_brake 70
  echo
}

# Exec Script #
main
