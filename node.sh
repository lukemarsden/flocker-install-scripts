#!/bin/sh

set -x -e

# Usage: ./stage2.sh node_ip control_service_ip
FLOCKER_NODE_NAME=$1
FLOCKER_CONTROL_NODE=$2

yum install -y https://s3.amazonaws.com/archive.zfsonlinux.org/epel/zfs-release.el7.noarch.rpm
yum install -y https://s3.amazonaws.com/clusterhq-archive/centos/clusterhq-release$(rpm -E %dist).noarch.rpm
yum install -y clusterhq-flocker-node

if selinuxenabled; then setenforce 0; fi
test -e /etc/selinux/config && sed --in-place='.preflocker' 's/^SELINUX=.*$/SELINUX=permissive/g' /etc/selinux/config
systemctl enable docker.service
systemctl start docker.service
mkdir -p /var/opt/flocker
truncate --size 10G /var/opt/flocker/pool-vdev
zpool create flocker /var/opt/flocker/pool-vdev

cat <<EOF >/etc/sysconfig/flocker-agent
FLOCKER_NODE_NAME = ${FLOCKER_NODE_NAME}
FLOCKER_CONTROL_NODE = ${FLOCKER_CONTROL_NODE}
EOF

systemctl enable flocker-agent
systemctl start flocker-agent
