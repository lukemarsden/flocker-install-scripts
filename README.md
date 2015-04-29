# Flocker quick install for OpenStack

This repo contains some install scripts that can help you get started with an API-based flocker deployment on CentOS 7 quickly.

This doc is derived from https://docs.clusterhq.com/en/0.4.0/indepth/installation.html#centos-7-install

## Install steps:

1. Provision some VMs. One master and several agent nodes. For example on OpenStack you could run:

```
IMAGE=8387fdff-cb2a-43ae-9418-f54441e7e8bd
FLAVOR=3
NET_ID=15b00747-b5ed-4afd-87fa-11548d3c9a1a
KEYPAIR_NAME=clusterhq_luke
KEYPAIR_LOCATION=~/.ssh/id_rsa_clusterhq_luke
VM_NAME_PREFIX=chq_luke_flocker_04

nova boot --image $IMAGE --flavor ${FLAVOR} --nic net-id=$NET_ID ${VM_NAME_PREFIX}_master --key-name ${KEYPAIR_NAME}
nova boot --image $IMAGE --flavor ${FLAVOR} --nic net-id=$NET_ID ${VM_NAME_PREFIX}_node001 --key-name ${KEYPAIR_NAME}
nova boot --image $IMAGE --flavor ${FLAVOR} --nic net-id=$NET_ID ${VM_NAME_PREFIX}_node002 --key-name ${KEYPAIR_NAME}
```

2. Wait for the VMs to boot and then note down their IPs:
```
nova list

MASTER_IP="1.2.3.100"
NODE_IPS="1.2.3.101 1.2.3.102"
```

2. Log into the each of the nodes (both master and nodes) and run:

```
ssh -i ${KEYPAIR_LOCATION} centos@NODE_IP
git clone https://github.com/clusterhq/flocker-install-scripts
cd flocker-install-scripts
sudo ./stage1.sh
```

This will upgrade the kernel and reboot the node.

3. Log into the master and run:

```
ssh -i ${KEYPAIR_LOCATION} centos@${MASTER_IP}
cd flocker-install-scripts
sudo ./master.sh
```

4. Log into the each of the nodes in turn and run:

```
ssh -i ${KEYPAIR_LOCATION} centos@NODE_IP
cd flocker-install-scripts
sudo ./node.sh
```
