#!/bin/bash

IP_RANGE="\t\t127.0.0.1/8\\;\\
\t\t127.0.1.1/8\\;\\
\t\t192.168.0.0/24\\;\\"

DOMAIN="fslab.flo-os.com"
DOMAIN_IP="192.168.0.205"
DNS_SERVER="${HOSTNAME}"


echo "Bind installation & config _ @fslab 20160426-16:43"

echo "Installing bind9..."
sudo apt-get update -q -y && sudo apt-get -q -y install bind9 bind9-doc

echo "Enabling security logging for bind..."
echo "Log stored in /var/log/named/security.log"
if [ -z "file "/var/log/named/security.log" versions 3 size 30m;" ]; then
  echo '
// Logging security events for fail2ban
logging {
    channel security_file {
        file "/var/log/named/security.log" versions 3 size 30m;
        severity dynamic;
        print-time yes;
    };
    category security {
        security_file;
    };
};' >> '/etc/bind/named.conf.options'
fi

echo "--> Updated /etc/bind/named.conf.options"

command mkdir --parent /var/log/named/
command chown -R bind:bind /var/log/named/
echo "Setup log rotation"
echo '/var/log/named/security.log {
  daily
  missingok
  rotate 7
  compress
  delaycompress
  notifempty
  create 644 bind bind
  postrotate
    /usr/sbin/invoke-rc.d bind9 reload > /dev/null
  endscript
}' > '/etc/logrotate.d/bind9-security'

echo "--> Created /etc/logrotate.d/bind9-security"

echo "Installing fail2ban..."
command apt-get install fail2ban -y -q
echo "Enabling Bind server protection by fail2ban"
if [ ! -e '/etc/fail2ban/jail.local' ]; then
  command touch '/etc/fail2ban/jail.local'
fi
if [ -z "[named-refused-tcp]
enabled = true" ]; then
  echo "
[named-refused-tcp]
enabled = true
" >> '/etc/fail2ban/jail.local'
fi

echo "--> Created /etc/fail2ban/jail.local"

echo "Reloading bind & fail2ban..."
/etc/init.d/bind9 reload
/etc/init.d/fail2ban restart

echo "Setting up opennic Big Brother free DNS"
NAME_SERVERS="\t\t5.9.49.12\\;\\
\t\t193.183.98.154\\;\\
\t\t185.83.217.248\\;\\
\t\t87.98.242.252\\;\\"

echo "--> $NAME_SERVERS"

echo "Redirect DNS request to selected servers"
if [ -n "${NAME_SERVERS}" ]; then
  command sed -i \
              -e '/^[ \t]*forwarders/,/^[ \t]*};/d' \
              -e "/directory/a\\
\\
\t// Forwarding DNS queries to ISP DNS.\\
\tforwarders {\\
${NAME_SERVERS}
\t}\\;" '/etc/bind/named.conf.options'
fi
echo "--> Updated /etc/bind/named.conf.options"

echo "Reloading bind..."
/etc/init.d/bind9 reload

echo "Setting up system to use local DNS..."
command sed -i -e 's/^\([ \t]*nameserver\)/#\1/' '/etc/resolv.conf'
command echo 'nameserver 127.0.0.1' >> '/etc/resolv.conf'

echo "Creating local network IP address ACL..."
command echo -e "
// Local networks access control list.
acl local-networks {
\t127.0.0.0/8;
${IP_RANGES}
};" >> '/etc/bind/named.conf.options'

echo "--> Updated /etc/bind/named.conf.options"
command sed -i -e '/directory/a\
\
\t// Allowing queries for local networks.\
\tallow-query {\
\t\tlocal-networks\;\
\t}\;\
\
\t// Allowing recursion for local networks.\
\tallow-recursion {\
\t\tlocal-networks\;\
\t}\;' '/etc/bind/named.conf.options'

echo "--> Updated /etc/bind/named.conf.options"
echo "Reloading bind..."
/etc/init.d/bind9 reload

echo "Creating the zone file for domain ${DOMAIN} ..."
echo "\$ttl 86400
${DOMAIN}. IN SOA ${DNS_SERVER}. postmaster.${DOMAIN}. (
 2010111504; Serial
 3600; refresh after 3 hours.
 3600; Retry after 1 hour.
 1209600; expire after 1 week.
 86400; Minimum TTL of 1 day.
);

;
; Name servers declaration.
;

${DOMAIN}.  IN NS  ${DNS_SERVER}.;
${DOMAIN}.  IN NS  ns57.domaincontrol.com.;
${DOMAIN}.  IN NS  ns58.domaincontrol.com.;

;
; Hostnames declaration.
;
${HOSTNAME}. IN A ${DOMAIN_IP};
" > "/etc/bind/db.${DOMAIN}"
echo "--> Created /etc/bind/db.${DOMAIN}"


echo "Adding zone to server configuration..."
if [ -z "$(command grep "${DOMAIN}" "/etc/bind/named.conf.local")" ]; then
  echo "
zone \"${DOMAIN}\" in {
 type master;
 file \"/etc/bind/db.${DOMAIN}\";
 allow-query { any; };
};
" >> "/etc/bind/named.conf.local"
fi
echo "--> Updated /etc/bind/named.conf.local"

echo "Reloading bind..."
/etc/init.d/bind9 reload