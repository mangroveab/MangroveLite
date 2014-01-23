###############################################################################################
# TuxLite - Complete LNMP/LAMP setup script for Debian/Ubuntu                                 #
# Nginx/Apache + PHP5-FPM + MySQL                                                             #
# Stack is optimized/tuned for a 256MB server                                                 #
# Email your questions to s@tuxlite.com                                                       #
###############################################################################################

source ./options.conf

# Detect distribution. Debian or Ubuntu
DISTRO=`lsb_release -i -s`
# Distribution's release. Squeeze, wheezy, precise etc
RELEASE=`lsb_release -c -s`
if  [ $DISTRO = "" ]; then
    echo -e "\033[35;1mPlease run 'aptitude -y install lsb-release' before using this script.\033[0m"
    exit 1
fi


#### Functions Begin ####

function basic_server_setup {

    aptitude update && aptitude -y safe-upgrade

    # Reconfigure sshd - change port and disable root login
    sed -i 's/^Port [0-9]*/Port '${SSHD_PORT}'/' /etc/ssh/sshd_config
    sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    service ssh reload

    # Set hostname and FQDN
    sed -i 's/'${SERVER_IP}'.*/'${SERVER_IP}' '${HOSTNAME_FQDN}' '${HOSTNAME}'/' /etc/hosts
    echo "$HOSTNAME" > /etc/hostname

    service hostname start

    # Basic hardening of sysctl.conf
    sed -i 's/^#net.ipv4.conf.all.accept_source_route = 0/net.ipv4.conf.all.accept_source_route = 0/' /etc/sysctl.conf
    sed -i 's/^net.ipv4.conf.all.accept_source_route = 1/net.ipv4.conf.all.accept_source_route = 0/' /etc/sysctl.conf
    sed -i 's/^#net.ipv6.conf.all.accept_source_route = 0/net.ipv6.conf.all.accept_source_route = 0/' /etc/sysctl.conf
    sed -i 's/^net.ipv6.conf.all.accept_source_route = 1/net.ipv6.conf.all.accept_source_route = 0/' /etc/sysctl.conf

    echo -e "\033[35;1m Root login disabled, SSH port set to $SSHD_PORT. Hostname set to $HOSTNAME and FQDN to $HOSTNAME_FQDN. \033[0m"
    echo -e "\033[35;1m Remember to create a normal user account for login or you will be locked out from your box! \033[0m"

} # End function basic_server_setup


function install_webserver {

    aptitude -y install libapache2-mod-fastcgi apache2-mpm-event

    a2dismod php4
    a2dismod php5
    a2dismod fcgid
    a2enmod actions
    a2enmod fastcgi
    a2enmod ssl
    a2enmod rewrite

    cat ./config/fastcgi.conf > /etc/apache2/mods-available/fastcgi.conf

    mkdir -p /srv/www/fcgi-bin.d

} # End function install_webserver


function install_php {

    apt-get install -y python-software-properties
    add-apt-repository -y ppa:ondrej/php5
    apt-get update

    aptitude -y install $PHP_BASE
    aptitude -y install $PHP_EXTRAS

} # End function install_php


function install_extras {
    # Install any other packages specified in options.conf
    aptitude -y install $MISC_PACKAGES

} # End function install_extras


function install_mysql {
    echo "mysql-server mysql-server/root_password password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
    echo "mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD" | debconf-set-selections

    aptitude -y install mysql-server mysql-client

    echo -e "\033[35;1m Securing MySQL... \033[0m"
    sleep 5

    aptitude -y install expect

    SECURE_MYSQL=$(expect -c "
        set timeout 10
        spawn mysql_secure_installation
        expect \"Enter current password for root (enter for none):\"
        send \"$MYSQL_ROOT_PASSWORD\r\"
        expect \"Change the root password?\"
        send \"n\r\"
        expect \"Remove anonymous users?\"
        send \"y\r\"
        expect \"Disallow root login remotely?\"
        send \"y\r\"
        expect \"Remove test database and access to it?\"
        send \"y\r\"
        expect \"Reload privilege tables now?\"
        send \"y\r\"
        expect eof
    ")

    echo "$SECURE_MYSQL"
    aptitude -y purge expect

} # End function install_mysql


function optimize_stack {

    cat ./config/apache2.conf > /etc/apache2/apache2.conf

    # Change logrotate for Apache2 log files to keep 10 days worth of logs
    sed -i 's/\tweekly/\tdaily/' /etc/logrotate.d/apache2
    sed -i 's/\trotate .*/\trotate 10/' /etc/logrotate.d/apache2

    # Remove Apache server information from headers.
    sed -i 's/ServerTokens .*/ServerTokens Prod/' /etc/apache2/conf.d/security
    sed -i 's/ServerSignature .*/ServerSignature Off/' /etc/apache2/conf.d/security

    # Add *:443 to ports.conf
    cat ./config/apache2_ports.conf > /etc/apache2/ports.conf

    service php5-fpm stop
    php_fpm_conf="/etc/php5/fpm/pool.d/www.conf"
    # Limit FPM processes
    sed -i 's/^pm.max_children.*/pm.max_children = '${FPM_MAX_CHILDREN}'/' $php_fpm_conf
    sed -i 's/^pm.start_servers.*/pm.start_servers = '${FPM_START_SERVERS}'/' $php_fpm_conf
    sed -i 's/^pm.min_spare_servers.*/pm.min_spare_servers = '${FPM_MIN_SPARE_SERVERS}'/' $php_fpm_conf
    sed -i 's/^pm.max_spare_servers.*/pm.max_spare_servers = '${FPM_MAX_SPARE_SERVERS}'/' $php_fpm_conf
    sed -i 's/\;pm.max_requests.*/pm.max_requests = '${FPM_MAX_REQUESTS}'/' $php_fpm_conf
    # Change to socket connection for better performance
    sed -i 's/^listen =.*/listen = \/var\/run\/php5-fpm-www-data.sock/' $php_fpm_conf

    php_ini_dir="/etc/php5/fpm/php.ini"
    # Tweak php.ini based on input in options.conf
    sed -i 's/^max_execution_time.*/max_execution_time = '${PHP_MAX_EXECUTION_TIME}'/' $php_ini_dir
    sed -i 's/^memory_limit.*/memory_limit = '${PHP_MEMORY_LIMIT}'/' $php_ini_dir
    sed -i 's/^max_input_time.*/max_input_time = '${PHP_MAX_INPUT_TIME}'/' $php_ini_dir
    sed -i 's/^post_max_size.*/post_max_size = '${PHP_POST_MAX_SIZE}'/' $php_ini_dir
    sed -i 's/^upload_max_filesize.*/upload_max_filesize = '${PHP_UPLOAD_MAX_FILESIZE}'/' $php_ini_dir
    sed -i 's/^expose_php.*/expose_php = Off/' $php_ini_dir
    sed -i 's/^disable_functions.*/disable_functions = exec,system,passthru,shell_exec,escapeshellarg,escapeshellcmd,proc_close,proc_open,dl,popen,show_source/' $php_ini_dir

    # Generating self signed SSL certs for securing phpMyAdmin, script logins etc
    echo -e " "
    echo -e "\033[35;1m Generating self signed SSL cert... \033[0m"
    mkdir /etc/ssl/localcerts

    aptitude -y install expect

    GENERATE_CERT=$(expect -c "
        set timeout 10
        spawn openssl req -new -x509 -days 3650 -nodes -out /etc/ssl/localcerts/webserver.pem -keyout /etc/ssl/localcerts/webserver.key
        expect \"Country Name (2 letter code) \[AU\]:\"
        send \"\r\"
        expect \"State or Province Name (full name) \[Some-State\]:\"
        send \"\r\"
        expect \"Locality Name (eg, city) \[\]:\"
        send \"\r\"
        expect \"Organization Name (eg, company) \[Internet Widgits Pty Ltd\]:\"
        send \"\r\"
        expect \"Organizational Unit Name (eg, section) \[\]:\"
        send \"\r\"
        expect \"Common Name (eg, YOUR name) \[\]:\"
        send \"\r\"
        expect \"Email Address \[\]:\"
        send \"\r\"
        expect eof
    ")

    echo "$GENERATE_CERT"
    aptitude -y purge expect

    # Tweak my.cnf. Commented out. Best to let users configure my.cnf on their own
    #cp /etc/mysql/{my.cnf,my.cnf.bak}
    #if [ -e /usr/share/doc/mysql-server-5.1/examples/my-medium.cnf.gz ]; then
    #gunzip /usr/share/doc/mysql-server-5.1/examples/my-medium.cnf.gz
    #cp /usr/share/doc/mysql-server-5.1/examples/my-medium.cnf /etc/mysql/my.cnf
    #else
    #gunzip /usr/share/doc/mysql-server-5.0/examples/my-medium.cnf.gz
    #cp /usr/share/doc/mysql-server-5.0/examples/my-medium.cnf /etc/mysql/my.cnf
    #fi
    #sed -i '/myisam_sort_buffer_size/ a\skip-innodb' /etc/mysql/my.cnf
    #sleep 1
    #service mysql restart

    restart_webserver
    sleep 2
    service php5-fpm start
    sleep 2
    service php5-fpm restart
    echo -e "\033[35;1m Optimize complete! \033[0m"

} # End function optimize


function install_postfix {

    # Install postfix
    echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections
    echo "postfix postfix/mailname string $HOSTNAME_FQDN" | debconf-set-selections
    echo "postfix postfix/destinations string localhost.localdomain, localhost" | debconf-set-selections
    aptitude -y install postfix

    # Allow mail delivery from localhost only
    /usr/sbin/postconf -e "inet_interfaces = loopback-only"

    sleep 1
    postfix stop
    sleep 1
    postfix start

} # End function install_postfix

function restart_webserver {

    apache2ctl graceful

} # End function restart_webserver



#### Main program begins ####

# Show Menu
if [ ! -n "$1" ]; then
    echo ""
    echo -e  "\033[35;1mNOTICE: Edit options.conf before using\033[0m"
    echo -e  "\033[35;1mA standard setup would be: apt + basic + install + optimize\033[0m"
    echo ""
    echo -e  "\033[35;1mSelect from the options below to use this script:- \033[0m"

    echo -n "$0"
    echo -ne "\033[36m apt\033[0m"
    echo     " - Reconfigure or reset /etc/apt/sources.list."

    echo -n  "$0"
    echo -ne "\033[36m basic\033[0m"
    echo     " - Disable root SSH logins, change SSH port and set hostname."

    echo -n "$0"
    echo -ne "\033[36m install\033[0m"
    echo     " - Installs LNMP or LAMP stack. Also installs Postfix MTA."

    echo -n "$0"
    echo -ne "\033[36m optimize\033[0m"
    echo     " - Optimizes webserver.conf, php.ini, AWStats & logrotate. Also generates self signed SSL certs."

    exit
fi
# End Show Menu


case $1 in
basic)
    basic_server_setup
    ;;
install)
    install_webserver
    install_mysql
    install_php
    install_extras
    install_postfix
    restart_webserver
    service php5-fpm restart
    echo -e "\033[35;1m Webserver + PHP-FPM + MySQL install complete! \033[0m"
    ;;
optimize)
    optimize_stack
    ;;
esac


