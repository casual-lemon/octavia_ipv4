#!/bin/bash

# generate initial bundle files
./generate-bundle.sh --octavia --octavia-ipv4 --create-model --name octavia --use-stable-charms --run

# wait for services start
while true; do
    [[ `juju status keystone --format json | jq -r '.applications.keystone.units."keystone/0"."workload-status".current'` = active ]] \
    && break
    if [[ `juju status keystone --format json | jq -r '.applications.keystone.units."keystone/0"."workload-status".current'` = error ]]
    then
      echo "ERROR: Octavia deployment failed" 
      break
    fi
done

# execute main configure script, networking to openstack
source novarc
./configure
./tools/sec_groups.sh

# create file extract password
touch novarc.services

cat << EOF > novarc.services 
OS_PROJECT_DOMAIN_NAME=service_domain
OS_USERNAME=octavia
OS_PROJECT_NAME=services
OS_USER_DOMAIN_NAME=service_domain
OS_PASSWORD=$(juju run --unit octavia/0 "grep -v "auth" /etc/octavia/octavia.conf | grep password" | awk '{print $3}')
EOF
source novarc.services

# creates the octavia network, subnet, router, add subnet to router
openstack network create lb-mgmt-net --tag charm-octavia
openstack subnet create --tag charm-octavia --subnet-range 21.0.0.0/29 --dhcp  --ip-version 4 --network lb-mgmt-net lb-mgmt-subnet
openstack router create lb-mgmt --tag charm-octavia
openstack router add subnet lb-mgmt lb-mgmt-subnet

# add security rules
openstack security group create lb-mgmt-sec-grp --tag charm-octavia
openstack security group create lb-health-mgr-sec-grp --tag charm-octavia-health
openstack security group rule create lb-mgmt-sec-grp --protocol icmp
openstack security group rule create lb-mgmt-sec-grp --protocol tcp --protocol tcp --dst-port 22
openstack security group rule create lb-mgmt-sec-grp --protocol tcp --dst-port 9443

# run octavia network setup with octavia credentials
./tools/configure_octavia.sh
# create vm for testing
./tools/instance_launch.sh 1 cirros
# use floating ip for newly create vm 
./tools/float_all.sh
# upload glance image for vm
./tools/upload_octavia_amphora_image.sh --release ussuri
# create loadbalancer 
./tools/create_octavia_lb.sh    