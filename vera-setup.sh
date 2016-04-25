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
yum install -y ansible-1.9.4 python-setuptools net-tools lsof ntp bind-utils
yum remove  -y java-1.8.0-openjdk
yum install -y java-1.7.0-openjdk

echo "veraIP=$PUBLIC_IP" > ~vera/.veraIP
echo "export VERA_ENV=$VERA_ENV" > /etc/profile.d/vera_env.sh
echo "export VERA_IP=$PUBLIC_IP" >> /etc/profile.d/vera_env.sh

curl -Is http://www.vera.com | head -1

if [[ $? -ne 0 ]]; then
                echo "Cannot connect to Vera RPM server rpm.vera.com. Please check internet connectivity and re-run."
                exit 1
        fi

mkdir -p /home/vera/bin

cat > /home/vera/bin/vera-appliance << \EOF 
#!/bin/bash -eu

set -e
logfile=/home/vera/.vera-appliance.out
echo "`date` || [vera-appliance] || Beginning vera-appliance Workflow" >> ${logfile}

# Make sure only vera can run our script
if [ "$(id -un)" != "vera" ]; then
   echo "This script must be run as user vera" 1>&2
   exit 1
fi
set +u

# Check for connector set. If not, set it to false
if [ -e ~vera/.connectorOnly ]; then
    export env $(cat ~vera/.connectorOnly | xargs)
else
    echo "connectorOnly=false" > ~vera/.connectorOnly
fi

case "$1" in
    'install')
        if [ -f "/etc/riak/ftu_conf_riak" ]; then
            echo "Riak has been configured. This will erase your Riak data. Are you sure?"
            select yn in "Yes" "No"; do
                case $yn in
                    Yes ) break;;
                    No ) exit 1;;
                esac
            done
        fi

        echo "Installing Vera On-Premise"
        
        echo "`date` || [vera-appliance] || ip set as ${VERA_IP}" >> ${logfile}

        # Question Add Node vs Fresh Install
        echo "Are you installing Vera for the first time, or would you like to add a node to an existing cluster?"
            select yn in "First Install" "Add a Node"; do
                case $yn in
                    'First Install' )
                    echo "`date` || [vera-appliance] || User Selected First Install" >> ${logfile};
                    echo "Would you like full on premise or just the connector?";
                         select yn in "Full Install" "Connector Install"; do
                            case $yn in
                                'Full Install' )
                                    echo "`date` || [vera-appliance] || User Selected Full Install" >> ${logfile};
                                    break;;
                                'Connector Install' )
                                    echo "`date` || [vera-appliance] || User Selected Connector Install" >> ${logfile};
                                    echo "connectorOnly=true" > ~vera/.connectorOnly;
                                    break;;
                            esac
                        done
                    export env $(cat ~vera/.connectorOnly | xargs);
                    echo "`date` || [vera-appliance] || connectorOnly is set to ${connectorOnly}" >> ${logfile};
                    break;;
                    'Add a Node' )
                        echo "`date` || [vera-appliance] || User Selected Add a Node" >> ${logfile};
                        sudo yum clean all; sudo yum install -y VeraBase;
                        ansible-playbook /etc/ansible/vera/play_onprem.yml --tags onprem_ssh -e ec2_tag=localhost -e vera_env=onprem -e onprem_env=$VERA_ENV -c local --diff;
                        sh /etc/ansible/vera/roles/common/files/bashrc;
                        sudo yum erase -y VeraBase;
                        echo "Please log in to your Vera Portal and add this node, IP $VERA_IP";
                        touch /home/vera/.vera-config-done;
                        exit 1;;
                esac
            done

        # Install veraBase Playbook
        sudo yum clean all | tee -a ${logfile}
        sudo yum install -y VeraBase | tee -a ${logfile}

        # Run Playbook
        ansible-playbook /etc/ansible/vera/play_onprem.yml --tags tomcat_configure_onprem,mailproxy_configure,nginx_install,nginx_configure,nginx_configure_vhosts,nginx_configure_vhosts_onprem,riak_install_onprem,riak_performance,elasticsearch_install_onprem,elasticsearch_datadormat_plugin,onprem_ssh,riak_performance,configure_rpmserver_onprem,grub_config,ansible_config,shared_onprem_tasks -e connectorOnly=$connectorOnly -e ec2_tag=localhost -e vera_env=onprem -e onprem_env=$VERA_ENV -c local --diff | tee -a ${logfile}

        # If Successful
        if [ $? == 0 ]; then
            # Remove Temp Vera Repo
            sudo rm -f /etc/yum.repos.d/tempvera.repo

            # Run Init
            echo "`date` || [vera-appliance] || Running /etc/rc.local" >> ${logfile}
            sudo sh /etc/rc.local | tee -a ${logfile}
            echo "`date` || [vera-appliance] || Running .bashrc" >> ${logfile}
            sh ~/.bashrc | tee -a ${logfile}

            # Run VConfig
            echo "`date` || [vera-appliance] || Running vconfig postSetIP" >> ${logfile}
            sudo vconfig postSetIP
        fi
    ;;
    'add-node')
        TEMP="${@:2}"
        echo "`date` || [vera-appliance] || Add-Node Called with Opts: ${TEMP}" >> ${logfile}
        eval set -- "$TEMP"

        # Pull in Versions and Set to Vars
        while [ $# -gt 0 ] ; do
            case "$1" in
                --vba)
                    vbase="-$2" ; shift 2 ;;
                --vse)
                    vserver="-$2" ; shift 2 ;;
                --vsh)
                    vshell="-$2" ; shift 2 ;;
                --vpo)
                    vportal="-$2" ; shift 2 ;;
                --vmp)
                    vmailproxy="-$2" ; shift 2 ;;
                --connector)
                    echo "connectorOnly=$2" > ~vera/.connectorOnly;
                    export env $(cat ~vera/.connectorOnly | xargs);
                    echo "`date` || [vera-appliance] || connectorOnly is set to ${connectorOnly}" >> ${logfile};
                    shift 2 ;;
                *)
                    break ;;
            esac
        done

        # Install veraBase Playbook
        sudo yum clean all | tee -a ${logfile}
        sudo yum install -y VeraBase${vbase} >> ${logfile}

        # Run Initial Playbook
        echo "`date` || [vera-appliance] || Executing Base On_Prem Play" >> ${logfile}
        ansible-playbook /etc/ansible/vera/play_onprem.yml --tags tomcat_configure_onprem,mailproxy_configure,nginx_install,nginx_configure,nginx_configure_vhosts,nginx_configure_vhosts_onprem,riak_install_onprem,riak_performance,elasticsearch_install_onprem,elasticsearch_datadormat_plugin,riak_performance,configure_rpmserver_onprem,grub_config,ansible_config,shared_onprem_tasks -e connectorOnly=$connectorOnly -e ec2_tag=localhost -e vera_env=onprem -e onprem_env=$VERA_ENV -c local --diff >> ${logfile}

        # If Successful
        if [ $? == 0 ]; then
            # Remove Temp Vera Repo
            sudo rm -f /etc/yum.repos.d/tempvera.repo

            # Run Init
            echo "`date` || [vera-appliance] || Executing rc.local" >> ${logfile}
            sudo sh /etc/rc.local
            echo "`date` || [vera-appliance] || Executing .bashrc" >> ${logfile}
            sh ~/.bashrc

            # Run VConfig with Versions
            echo "`date` || [vera-appliance] || Executing VConfig with opts: --vse ${vserver} --vsh ${vshell} --vpo ${vportal} --vmp ${vmailproxy}" >> ${logfile}
            sudo vconfig postSetIP version_spec --vse ${vserver} --vsh ${vshell} --vpo ${vportal} --vmp ${vmailproxy}
        else
            echo "Initial Installation Script Failed. Please Retry" >> ${logfile}
            exit 1
        fi
    ;;
    'upgrade')
        if [ ! -f "/home/vera/.vera-config-done" -a ! -f "/home/vera/.vera-change-ip-done" -a "$2" != "-force" ]; then
            echo "Vera has not been installed. Please install first." | tee -a ${logfile}
            exit 1
        fi

        echo "Updating Vera On-Premise"
        echo "`date` || [vera-appliance] || Updating Vera On-Premise" >> ${logfile}
        echo ""

        if [ -f "/home/vera/.vera-change-ip-done" ]; then
            echo "Detected Legacy Controller" | tee -a ${logfile}
            echo "Would you like to upgrade?"
            select yn in "Yes" "No"; do
                case $yn in
                    Yes ) echo "`date` || [vera-appliance] || User Selected Yes" >> ${logfile}; break;;
                    No ) echo "`date` || [vera-appliance] || User Selected No" >> ${logfile}; exit 1;;
                esac
            done

            # Set VERA_ENV Variable
            read -e -p "Enter Environment Type (prod|stage|dev|qa): " env_type;
            echo "`date` || [vera-appliance] || User Entered Environment: ${env_type}" >> ${logfile}
            echo "export VERA_ENV=${env_type}" | sudo tee /etc/profile.d/vera_env.sh > /dev/null
            VERA_ENV=${env_type}

            # Copy Scripts to Expected Places
            cp -f ./set_ip.sh /usr/bin/set_ip
            chmod +x /usr/bin/set_ip
            mkdir -p /home/vera/bin
            cp ./vera_runMe.sh /home/vera/bin/vera-appliance
            chmod +x /home/vera/bin/vera-appliance
            cat ./run_on_login.sh >> /home/vera/.bash_profile

            # Execute Set_IP To Init Necessary Vars
            sudo set_ip
        fi

        # Exit on failure
        if [ $? -ne 0 ]; then
            touch /home/vera/.vera-config-done
            exit 1
        fi

        # Install veraBase Playbook
        sudo yum clean all | tee -a ${logfile}
        sudo yum install -y VeraBase | tee -a ${logfile}

        # Run Playbook
        ansible-playbook /etc/ansible/vera/play_onprem.yml --tags tomcat_configure_onprem,mailproxy_configure,nginx_install,nginx_configure,nginx_configure_vhosts,nginx_configure_vhosts_onprem,riak_install_onprem,riak_performance,elasticsearch_install_onprem,elasticsearch_datadormat_plugin,onprem_ssh,riak_performance,configure_rpmserver_onprem,grub_config,ansible_config,shared_onprem_tasks -e connectorOnly=$connectorOnly -e ec2_tag=localhost -e vera_env=onprem -e onprem_env=$VERA_ENV -c local --diff | tee -a ${logfile}

        if [ $? -ne 0 ]; then
            echo "Upgrade Failed. Please Try Again"
            touch /home/vera/.vera-config-done
            exit 1
        fi

        # Remove legacy donefile If Exists and Update .bashrc
        if [ -f "/home/vera/.vera-change-ip-done" ]; then
            echo "Removing Legacy Controller Done File"
            rm -rf /home/vera/.vera-change-ip-done
            cp /home/vera/bashrc.template /home/vera/.bashrc
        fi

        # Run VConfig
        sudo vconfig postSetIP -update
    ;;
    'change-ip')

        # Run VConfig
        sudo vconfig -force
    ;;
    *)
        echo $"Usage: vera-appliance {install|upgrade|change-ip}"
        exit 1
esac
set -u
EOF

chmod +x /home/vera/bin/vera-appliance

cat > /etc/yum.repos.d/tempvera.repo <<EOF
[Vera]
name= Vera`echo $VERA_ENV | tr '[:lower:]' '[:upper:]'`
baseurl=https://vera:V^3raR0cZ!@rpm$VERA_ENV.veraeng.com
enabled=1
gpgcheck=0
sslverify=0
EOF

cat >> /home/vera/.bash_profile <<EOF
if [ ! -f "/etc/riak/ftu_conf_riak" -a ! -f "/home/vera/.vera-config-done" ]; then
    echo ""
    echo "#####################################"
    echo "#                                   #"
    echo "#          Welcome to Vera          #"
    echo "#        Beginning Installation     #"
    echo "#                                   #"
    echo "#####################################"
    echo ""
    vera-appliance install
else
    echo ""
    echo "#####################################"
    echo "#                                   #"
    echo "#          Welcome to Vera          #"
    echo "# Run vera-appliance to get started #"
    echo "#                                   #"
    echo "#####################################"
    echo ""
    vera-appliance
    echo ""
fi
EOF

cat > /etc/motd <<-EOF
*************************************************************************************
           	   W A R N I N G! AUTHORIZED USE ONLY
*************************************************************************************
This computer system belongs to Vera. It is for authorized use only.
Users have no explicit or implicit expectation of privacy.

Unauthorized or improper use of this system may result in administrative disciplinary
ction, civil and criminal penalties. By continuing to use this system, you indicate
your awareness of and consent to these terms and conditions of use.

		https://www.vera.com/terms-of-service/

Do not continue to use this system if you do not agree to the conditions stated in
this warning.
************************************************************************************
EOF

#Update Ulimit
echo "ulimit -n 65536" >> /etc/rc.d/rc.local
echo "vera soft nofile 65536" >> /etc/security/limits.conf
echo "vera hard nofile 65536" >> /etc/security/limits.conf

sed -i 's/enforcing/disabled/g' /etc/selinux/config /etc/selinux/config
setenforce 0
sed -i "s/^.*requiretty/#Defaults requiretty/" /etc/sudoers
ntpdate 0.amazon.pool.ntp.org
