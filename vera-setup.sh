#!/bin/bash 

#param VERA_ENV the selected Vera enviornment

PRIVATE_IP=`curl -s http://169.254.169.254/latest/meta-data/local-ipv4`
PUBLIC_IP=`curl -s http://169.254.169.254/latest/meta-data/public-ipv4`

USER=vera
usermod  -l $USER centos
groupmod -n $USER centos
usermod  -d /home/$USER -m $USER
sed -i "s/centos/$USER/g" /etc/sudoers.d/90-cloud-init-users
echo "vera" | passwd --stdin vera

yum clean all
rpm -ivh http://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-6.noarch.rpm
yum install -y ansible1.9-1.9.4-2.el7 python-setuptools net-tools lsof ntp bind-utils
yum remove  -y java-1.8.0-openjdk
yum install -y java-1.7.0-openjdk

echo "veraIP=$PRIVATE_IP" > ~vera/.veraIP
echo "export VERA_ENV=$VERA_ENV" > /etc/profile.d/vera_env.sh
echo "export VERA_IP=$PRIVATE_IP" >> /etc/profile.d/vera_env.sh
echo "export PUBLIC_IP=$PUBLIC_IP" >> /etc/profile.d/vera_env.sh

cat > /etc/yum.repos.d/tempvera.repo <<EOF
[Vera]
name= Vera`echo $VERA_ENV | tr '[:lower:]' '[:upper:]'`
baseurl=https://vera:V^3raR0cZ!@rpm$VERA_ENV.veraeng.com
enabled=1
gpgcheck=0
sslverify=0
EOF

# rpm -ivh ftp://128.199.194.137/VeraBaseAWS-1-0.noarch.rpm
yum install -y VeraBaseAWS.noarch

mkdir -p /home/vera/bin
cp /etc/ansible/vera/bin/vera-appliance /home/vera/bin/vera-appliance 
chmod +x /home/vera/bin/vera-appliance
chown -R vera:vera /home/vera/bin

cp /etc/ansible/vera/bin/post-setup.sh /tmp/post-setup.sh
chmod +x /tmp/post-setup.sh
sh /tmp/post-setup.sh

#Update Ulimit
echo "ulimit -n 65536" >> /etc/rc.d/rc.local
echo "vera soft nofile 65536" >> /etc/security/limits.conf
echo "vera hard nofile 65536" >> /etc/security/limits.conf

sed -i 's/enforcing/disabled/g' /etc/selinux/config /etc/selinux/config
setenforce 0
sed -i "s/^.*requiretty/#Defaults requiretty/" /etc/sudoers
ntpdate 0.amazon.pool.ntp.org
touch /home/vera/.vera-init
