#!/bin/sh

set -x -e

yum install -y https://s3.amazonaws.com/archive.zfsonlinux.org/epel/zfs-release.el7.noarch.rpm
yum install -y https://s3.amazonaws.com/clusterhq-archive/centos/clusterhq-release$(rpm -E %dist).noarch.rpm
yum install -y clusterhq-flocker-node

if selinuxenabled; then setenforce 0; fi
test -e /etc/selinux/config && sed --in-place='.preflocker' 's/^SELINUX=.*$/SELINUX=disabled/g' /etc/selinux/config

systemctl enable flocker-control
systemctl start flocker-control
