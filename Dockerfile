FROM debian:12.6-slim

# Versi
ARG BUILD_ISPCONFIG_VERSION="3.2.12"
ENV BUILD_PHP_VERS="8.2"

# Database
ARG BUILD_ISPCONFIG_DROP_EXISTING="no"
ARG BUILD_MYSQL_HOST="localhost"
ARG BUILD_ISPCONFIG_MYSQL_USER="ispconfig"
ARG BUILD_ISPCONFIG_MYSQL_DATABASE="dbispconfig"
ARG BUILD_MYSQL_PW="pass"
ARG BUILD_MYSQL_REMOTE_ACCESS_HOST="172.%.%.%"

# SSL
#ARG BUILD_CERTBOT="yes"
#ARG BUILD_ISPCONFIG_USE_SSL="yes"
#ARG BUILD_ISPCONFIG_USE_SSL="yes"


# Argument
ARG BUILD_HOSTNAME="myhost.test.com"
ARG BUILD_ISPCONFIG_PORT="8080"
ARG BUILD_LOCALE="C"
ARG BUILD_TZ="Asia/Makassar"

# prep
ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]
# timezone and locale
ENV LANG="${BUILD_LOCALE}.UTF-8"
ENV LANGUAGE="${BUILD_LOCALE}:en"
ENV LC_ALL="${BUILD_LOCALE}.UTF-8"

RUN . /etc/os-release && \
    touch /etc/apt/sources.list && \
    echo "deb-src http://deb.debian.org/debian $VERSION_CODENAME main non-free-firmware" >> /etc/apt/sources.list && \
    echo "deb-src http://deb.debian.org/debian $VERSION_CODENAME-updates main non-free-firmware" >> /etc/apt/sources.list && \
    echo "deb-src http://deb.debian.org/debian-security/ $VERSION_CODENAME-security main non-free-firmware" >> /etc/apt/sources.list && \
    apt-get -qq -o Dpkg::Use-Pty=0 update && \
    apt-get -qq -o Dpkg::Use-Pty=0 --no-install-recommends install apt-utils locales libtimedate-perl supervisor ufw cron apache2 \
                                    apache2-suexec-pristine apache2-utils ca-certificates dirmngr dnsutils \
                                    gnupg gnupg2 haveged imagemagick libapache2-mod-fcgid libapache2-mod-passenger \
                                    libapache2-mod-python libruby lsb-release mcrypt memcached python3 software-properties-common \
                                    wget vim vim-nox mariadb-client iputils-ping net-tools procps borgbackup patch rsyslog rsyslog-relp \
                                    mariadb-server logrotate git sendemail sudo ntp ntpdate && \
    sed -i -e "s/# ${BUILD_LOCALE}.UTF-8 UTF-8/${BUILD_LOCALE}.UTF-8 UTF-8/" /etc/locale.gen && \
    locale-gen && \
    ln -fs /usr/share/zoneinfo/${BUILD_TZ} /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata && \
# --- systemctl fix
    ln -fs /usr/bin/true /usr/bin/systemctl && \
# --- Create log file
    touch /var/log/cron.log && \
    touch /var/spool/cron/root && \
    crontab /var/spool/cron/root
    # --- Change The Default Shell
    #printf "dash  dash/sh boolean no n" | debconf-set-selections && \
    #dpkg-reconfigure dash && \
    # --- MySQL (optional)
    #if [ "${BUILD_MYSQL_HOST}" = "localhost" ]; then \
    #printf "mariadb-server mariadb-server/root_password password %s\n" "${BUILD_MYSQL_PW}"       | debconf-set-selections && \
    #printf "mariadb-server mariadb-server/root_password_again password %s\n" "${BUILD_MYSQL_PW}" | debconf-set-selections && \
    #apt-get -qq -o Dpkg::Use-Pty=0 --no-install-recommends install mariadb-server; \
    #fi;

# Established MySQL 
COPY ./etc/mysql/debian.cnf /etc/mysql
RUN if [ "${BUILD_MYSQL_HOST}" = "localhost" ]; then \
        sed -i "s|password =|password = ${BUILD_MYSQL_PW}|" /etc/mysql/debian.cnf && \
        printf "mysql soft nofile 65535\nmysql hard nofile 65535\n" >> /etc/security/limits.conf && \
        mkdir -p /etc/systemd/system/mysql.service.d/ && \
        printf "[Service]\nLimitNOFILE=infinity\n" >> /etc/systemd/system/mysql.service.d/limits.conf && \
        service mariadb restart && \
        printf "SET PASSWORD = PASSWORD('%s');\n" "${BUILD_MYSQL_PW}" | mysql -h ${BUILD_MYSQL_HOST} -uroot -p${BUILD_MYSQL_PW}; \
    elif ! mysql -h ${BUILD_MYSQL_HOST} -uroot -p${BUILD_MYSQL_PW}; then \
        printf "\e[31mConnection to mysql host \"%s\" with password \"%s\" failed!\e[0m\n" "${BUILD_MYSQL_HOST}" "${BUILD_MYSQL_PW}" && \
        exit 1; \
    fi;

# --- PHP & PHP-FPM
RUN apt-get -qq -o Dpkg::Use-Pty=0 --no-install-recommends install libapache2-mod-php${BUILD_PHP_VERS} php${BUILD_PHP_VERS}-{cgi,cli,common,curl,fpm,gd,imagick,imap,intl,mbstring,mysql,opcache,pspell,readline,redis,soap,sqlite3,tidy,xml,xsl,yaml,zip} && \
    ln -sf /etc/php/${BUILD_PHP_VERS} /etc/php/current && \
    ln -sf /var/lib/php${BUILD_PHP_VERS}-fpm /var/lib/php-fpm && \
    /usr/sbin/a2enmod setenvif suexec rewrite ssl actions include dav_fs dav auth_digest cgi headers actions proxy_fcgi alias && \
    printf "ServerName %s\n" "${BUILD_HOSTNAME}" > /etc/apache2/conf-available/fqdn.conf && \
    /usr/sbin/a2enconf fqdn && \
    /usr/sbin/a2enconf php${BUILD_PHP_VERS}-fpm && \
    service apache2 restart

# --- Install ISPConfig 3
WORKDIR /tmp
RUN wget "https://ispconfig.org/downloads/ISPConfig-${BUILD_ISPCONFIG_VERSION}.tar.gz" -q && \
    tar xfz ISPConfig-${BUILD_ISPCONFIG_VERSION}.tar.gz
COPY ./autoinstall.ini /tmp/ispconfig3_install/install/autoinstall.ini
RUN touch "/etc/mailname" && \
    sed -i "s|mysql_hostname=localhost|mysql_hostname=${BUILD_MYSQL_HOST}|" "/tmp/ispconfig3_install/install/autoinstall.ini" && \
    sed -i "s/^ispconfig_port=8080$/ispconfig_port=${BUILD_ISPCONFIG_PORT}/g" "/tmp/ispconfig3_install/install/autoinstall.ini" && \
    sed -i "s|mysql_root_password=pass|mysql_root_password=${BUILD_MYSQL_PW}|" "/tmp/ispconfig3_install/install/autoinstall.ini" && \
    sed -i "s|mysql_database=dbispconfig|mysql_database=${BUILD_ISPCONFIG_MYSQL_DATABASE}|" "/tmp/ispconfig3_install/install/autoinstall.ini" && \
    sed -i "s/^hostname=server1.example.com$/hostname=${BUILD_HOSTNAME}/g" "/tmp/ispconfig3_install/install/autoinstall.ini" && \
    sed -i "s/^ssl_cert_common_name=server1.example.com$/ssl_cert_common_name=${BUILD_HOSTNAME}/g" "/tmp/ispconfig3_install/install/autoinstall.ini" && \
    sed -i "s/^ispconfig_use_ssl=y$/ispconfig_use_ssl=$(printf "%s" ${BUILD_ISPCONFIG_USE_SSL} | cut -c1)/g" "/tmp/ispconfig3_install/install/autoinstall.ini" && \
    [ "${BUILD_MYSQL_HOST}" = "localhost" ] && service mariadb restart; \
    if [ -n "$(printf "SHOW DATABASES LIKE '%s';" "${BUILD_ISPCONFIG_MYSQL_DATABASE}" | mysql -h "${BUILD_MYSQL_HOST}" -uroot -p"${BUILD_MYSQL_PW}" 2> /dev/null)" ]; then \
        if [ "${BUILD_ISPCONFIG_DROP_EXISTING}" = "yes" ]; then \
            printf "DROP DATABASE %s;" "${BUILD_ISPCONFIG_MYSQL_DATABASE}" | mysql -h "${BUILD_MYSQL_HOST}" -uroot -p"${BUILD_MYSQL_PW}"; \
        else \
            printf "\e[31mERROR: ISPConfig database '%s' already exists and build argument 'BUILD_ISPCONFIG_DROP_EXISTING' = 'no'. Move the existing database aside before continuing\e[0m" "${BUILD_ISPCONFIG_MYSQL_DATABASE}" && \
            exit 1; \
        fi; \
    fi; \
    if [ "$(printf "SELECT * FROM mysql.global_priv WHERE User = '%s';" "${BUILD_ISPCONFIG_MYSQL_USER}" | mysql -N -h ${BUILD_MYSQL_HOST} -uroot -p${BUILD_MYSQL_PW})" -eq 1 ]; then \
        if [ "${BUILD_ISPCONFIG_DROP_EXISTING}" = "yes" ]; then \
            printf "DELETE FROM mysql.global_priv WHERE User = \"%s\"; FLUSH PRIVILEGES;" "${BUILD_ISPCONFIG_MYSQL_USER}" | mysql -h "${BUILD_MYSQL_HOST}" -uroot -p"${BUILD_MYSQL_PW}"; \
        else \
            printf "\e[31mERROR: ISPConfig user '%s' already exists and build argument 'BUILD_ISPCONFIG_DROP_EXISTING' = 'no'. Move the existing user aside before continuing\e[0m" "${BUILD_ISPCONFIG_MYSQL_USER}" && \
            exit 1; \
        fi; \
    fi; \
    php -q "/tmp/ispconfig3_install/install/install.php" --autoinstall=/tmp/ispconfig3_install/install/autoinstall.ini && \
    if [ "${BUILD_MYSQL_HOST}" != "localhost" ]; then \
        ISP_ADMIN_PASS=$(grep "\$conf\['db_password'\] = '\(.*\)'" "/usr/local/ispconfig/interface/lib/config.inc.php" | sed "s|\$conf\['db_password'\] = '\(.*\)';|\1|") && \
        printf "GRANT ALL PRIVILEGES ON %s.* TO '%s'@'%s' IDENTIFIED BY '%s';" "${BUILD_ISPCONFIG_MYSQL_DATABASE}" "${BUILD_ISPCONFIG_MYSQL_USER}" "${BUILD_MYSQL_REMOTE_ACCESS_HOST}" "${ISP_ADMIN_PASS}" | \
        mysql -h "${BUILD_MYSQL_HOST}" -uroot -p"${BUILD_MYSQL_PW}"; \
    fi; \
    sed -i "s|NameVirtualHost|#NameVirtualHost|" "/etc/apache2/sites-enabled/000-ispconfig.conf" && \
    sed -i "s|NameVirtualHost|#NameVirtualHost|" "/etc/apache2/sites-enabled/000-ispconfig.vhost"

# --- supervisord
COPY ./supervisor /etc/supervisor

# --- link /etc/init.d startup to supervisor
RUN ln -sf /etc/supervisor/systemctl /bin/systemctl && \
    chmod a+x /etc/supervisor/* /etc/supervisor/*.d/*


# --- cleanup
ENV TERM=xterm
RUN printf "export TERM=xterm\n" >> /root/.bashrc && \
    apt-get autoremove && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /tmp/*

EXPOSE 80 8080 443

ENTRYPOINT [ "/usr/bin/supervisord" ]