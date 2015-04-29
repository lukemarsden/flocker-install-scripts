#!/bin/sh

set -x -e

yum install -y kernel-devel kernel
yum install -y epel-release
sync
shutdown -r now
