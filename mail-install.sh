#!/usr/bin/env bash

ESC_SEQ="\x1b["
COL_RESET=$ESC_SEQ"39;49;00m"
COL_RED=$ESC_SEQ"31;01m"
COL_GREEN=$ESC_SEQ"32;01m"
COL_YELLOW=$ESC_SEQ"33;01m"

DOMAIN="xxx.vn"
PASS_DB_ROUNDCUBE="xxx"

if [ "$UID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

function error_check {
    if [ "$?" = "0" ]; then
        echo -e "$COL_GREEN OK. $COL_RESET"
    else
        echo -e "$COL_RED An error has occured. $COL_RESET"
        read -p "Press enter or space to ignore it. Press any other key to abort." -n 1 key

        if [[ $key != "" ]]; then
            exit
        fi
    fi
}

echo "[======= Updating system =======]"
apt-get update
apt-get upgrade -y
echo "[======= Updating system => $(error_check) =======]"

echo "[======= Install Postfix =======]"
debconf-set-selections <<< "postfix postfix/mailname string $DOMAIN"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
apt-get install postfix -y
##Configure postfix main.cf config
postconf -e 'inet_protocols = ipv4'
postconf -e 'home_mailbox = Maildir/'
service postfix restart
echo "[======= Install Postfix => $(error_check) =======]"

echo "[======= Install Dovecot =======]"
apt-get install dovecot-imapd dovecot-pop3d -y
#uncomment !include conf.d/*.conf
sed -i '/\!include conf\.d\/\*\.conf/s/^#//' /etc/dovecot/dovecot.conf
#add protocols = imap pop3 > /etc/dovecot/dovecot.conf
checkProtocols=`grep "protocols = imap pop3" /etc/dovecot/dovecot.conf`
if [ -z "$checkProtocols" ]; then
	echo "protocols = imap pop3" >> /etc/dovecot/dovecot.conf
fi
#add listen = * > /etc/dovecot/dovecot.conf
echo "listen = *" >> /etc/dovecot/dovecot.conf

#10-auth.conf
sed -i '/\disable_plaintext_auth =.*/s/^#//g' /etc/dovecot/conf.d/10-auth.conf
sed -i '/^auth_mechanisms =.*/s/^/#/g' /etc/dovecot/conf.d/10-auth.conf
echo "auth_mechanisms = plain login" >> /etc/dovecot/conf.d/10-auth.conf

#10-mail.conf
sed -i '/^mail_location =.*/s/^/#/g' /etc/dovecot/conf.d/10-mail.conf #comment default mail_location
echo "mail_location = maildir:/home/%u/Maildir" >> /etc/dovecot/conf.d/10-mail.conf

#10-master.conf
if [[ ! -f /etc/dovecot/conf.d/10-master.conf.orig ]]; then
	mv /etc/dovecot/conf.d/10-master.conf /etc/dovecot/conf.d/10-master.conf.orig
fi
dovecotmaster="service imap-login {\n
  inet_listener imap {\n
    port = 143\n
  }\n
  inet_listener imaps {\n
  }\n
}\n
\n
service pop3-login {\n
  inet_listener pop3 {\n
    port = 110\n
  }\n
  inet_listener pop3s {\n
  }\n
}\n
\n
service lmtp {\n
  unix_listener lmtp {\n
  }\n
}\n
\n
service imap {\n
}\n
\n
service pop3 {\n
}\n
\n
service auth {\n
  unix_listener auth-userdb {\n
    mode = 0600\n
    user = postfix\n
    group = postfix\n
  }\n
}\n
\n
service auth-worker {\n
}\n
\n
service dict {\n
  unix_listener dict {\n
  }\n
}\n
"
echo -e $dovecotmaster > /etc/dovecot/conf.d/10-master.conf

#/etc/dovecot/conf.d/20-imap.conf
if [[ ! -f /etc/dovecot/conf.d/20-imap.conf.orig ]]; then
	mv /etc/dovecot/conf.d/20-imap.conf /etc/dovecot/conf.d/20-imap.conf.orig
fi
dovecotimap="
protocol imap {\n
  mail_plugins = $mail_plugins autocreate\n
}\n
\n
plugin { \n
autocreate = Trash \n
autocreate2 = Junk \n
autocreate3 = Drafts \n
autocreate4 = Sent \n
autosubscribe = Trash \n
autosubscribe2 = Junk \n
autosubscribe3 = Drafts \n
autosubscribe4 = Sent \n
}\n
"
echo -e $dovecotimap > /etc/dovecot/conf.d/20-imap.conf

service dovecot restart
service postfix restart
echo "[======= Install Dovecot => $(error_check) =======]"

echo "[======= Install RoundCube =======]"

# Create Database for Round Cube  user/pass = mailadmin
echo "[======= Input Password Mysql =======]"
echo "create database roundcubedb; create user 'mailadmin' identified by '$PASS_DB_ROUNDCUBE'; grant all privileges on roundcubedb.* to 'mailadmin'; FLUSH PRIVILEGES;" | mysql -u root -p

cd /tmp
wget https://github.com/roundcube/roundcubemail/archive/release-1.3.zip
unzip release-1.3.zip -d /usr/share/nginx/html
mv /usr/share/nginx/html/roundcubemail-release-1.3 /usr/share/nginx/html/webmail
chown -R www-data:www-data /usr/share/nginx/html/webmail/*
chown -R www-data:www-data /usr/share/nginx/html/webmail/
echo "[======= Input Password Mysql =======]"
mysql -u root -p roundcubedb < /usr/share/nginx/html/webmail/SQL/mysql.initial.sql

#set host
echo "127.0.0.1 $DOMAIN" >> /etc/hosts

apt-get install -y php-intl php-ldap php-json php-xml php-mbstring
service apache2 restart

echo "Open http://localhost/webmail/installer "
echo "Database: roundcubedb"
echo "User Name: mailadmin"
echo "Password: $PASS_DB_ROUNDCUBE"

echo "Documents: "
echo "https://www.youtube.com/watch?v=uQ2tQuiJmxs"
echo "http://linoxide.com/ubuntu-how-to/install-roundcube-webmail-ubuntu16-04/"
echo "https://easyengine.io/tutorials/linux/ubuntu-postfix-gmail-smtp/"

echo "[======= Install RoundCube => $(error_check) =======]"
