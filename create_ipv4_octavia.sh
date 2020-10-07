#!/bin/bash

# generate initial bundle files
./generate-bundle.sh --octavia --octavia-ipv4 --create-model --name octavia --series focal --use-stable-charms --run

# wait for services to come up
#while true; do
#    [[ `juju status octavia --format json | jq -r '.applications.octavia.units."octavia/0"."workload-status".current'` = blocked ]] \
#    && break
#    echo "waiting for octavia"
#    if [[ `juju status octavia --format json | jq -r '.applications.octavia.units."octavia/0"."workload-status".current'` = error ]] 
#    then 
#      echo "ERROR: Octavia deployment failed" 
#      break
#    fi 
#done

#while true; do
#    [[ `juju status keystone --format json | jq -r '.applications.keystone.units."keystone/0"."workload-status".current'` = active ]] \
#    && break
#    if [[ `juju status keystone --format json | jq -r '.applications.keystone.units."keystone/0"."workload-status".current'` = error ]]
#    then
#      echo "ERROR: Octavia deployment failed" 
#      break
#    fi
#done

sudo snap install juju-wait --classic

# wait for octavia 
juju wait -x octavia

# execute main configure script, networking to openstack
source ~/novarc
./configure

#add octavia credentials to novarc
export OS_PASSWORD=$(juju run --unit octavia/0 "grep -v "auth" /etc/octavia/octavia.conf | grep password" | awk '{print $3}')
export OS_PROJECT_DOMAIN_NAME=service_domain
export OS_USERNAME=octavia
export OS_PROJECT_NAME=services
export OS_USER_DOMAIN_NAME=service_domain
source ~/novarc

# run security group setup
./tools/sec_groups.sh

# creates the octavia network, subnet, router, add subnet to router
openstack network create lb-mgmt-net --tag charm-octavia
openstack subnet create --tag charm-octavia --subnet-range 20.0.0.0/29 --dhcp  --ip-version 4 --network lb-mgmt-net lb-mgmt-subnet
openstack router create lb-mgmt --tag charm-octavia
openstack router add subnet lb-mgmt lb-mgmt-subnet

# add security rules
openstack security group create lb-mgmt-sec-grp --tag charm-octavia
openstack security group create lb-health-mgr-sec-grp --tag charm-octavia-health
openstack security group rule create lb-mgmt-sec-grp --protocol icmp
openstack security group rule create lb-mgmt-sec-grp --protocol tcp --protocol tcp --dst-port 21
openstack security group rule create lb-mgmt-sec-grp --protocol tcp --dst-port 9443

# run octavia network setup with octavia credentials
./tools/configure_octavia.sh
# create vm for testing
./tools/instance_launch.sh 1 cirros
# use floating ip for newly create vm 
./tools/float_all.sh
juju wait
# upload glance image for vm
./tools/upload_octavia_amphora_image.sh --release ussuri
# create loadbalancer 
./tools/create_octavia_lb.sh

