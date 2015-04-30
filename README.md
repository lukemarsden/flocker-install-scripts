# Moving a database in Docker with Flocker and `curl`

**NOT OFFICIALLY SUPPORTED - if this breaks you get to keep both pieces.**

## Flocker 0.4 API demo on CentOS 7

This repo contains some install scripts that can help you get started with an API-based flocker deployment on CentOS 7 quickly using our alpha-quality ZFS backend.

## Background

At ClusterHQ, we have been working hard at integrating Flocker's volume management capabilities with common orchestration frameworks such as Swarm and Kubernetes (Mesos/Marathon coming soon) via the upcoming Docker plugins project.

Some features of Flocker aren't easy to integrate with these frameworks, however, such as 2-phase push, because it requires the orchestration framework saying "I'm going to want to move this container over there, please pre-replicate the data". So, we have been working on a minimal orchestration framework of our own: **just enough orchestration** to demo these cool data features. We hope to integrate these advanced data features into other orchestration frameworks in due course.

This document shows you how to kick the tyres and use our volumes API and containers API together to create a volume, attach it to a container, and then move that container along with its volume between hosts with minimal downtime using 2-phase push -- all just using `curl`!

This doc is derived from https://docs.clusterhq.com/en/0.4.0/indepth/installation.html#installing-on-centos-7

## Big picture architecture
[insert architecture diagram here]

## Install steps:

`1.` Provision some VMs. One master for the control service and several agent nodes for user containers. For example on OpenStack you could run:

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

(TODO: maybe a similar example on AWS/DigitalOcean/Vagrant for general consumption.)

`2.` Wait for the VMs to boot and then note down their IPs:
```
nova list

MASTER_IP="1.2.3.100"
NODE_IPS="1.2.3.101 1.2.3.102"
```

Note that when referring to "nodes" throughout the rest of this document we are *not* referring to the master.

`3.` Log into the master and each of the nodes and run:

```
NODE_IP=...
ssh -i ${KEYPAIR_LOCATION} centos@${NODE_IP}
sudo yum install -y git
git clone https://github.com/lukemarsden/flocker-install-scripts
cd flocker-install-scripts
sudo ./stage1.sh
```

This will upgrade the kernel and reboot the node.

`4.` Log into the master and run:

```
ssh -i ${KEYPAIR_LOCATION} centos@${MASTER_IP}
cd flocker-install-scripts
sudo ./master.sh
```

`5.` Log into the each of the nodes in turn and run:

```
NODE_IP=...
ssh -i ${KEYPAIR_LOCATION} centos@${NODE_IP}
cd flocker-install-scripts
sudo ./node.sh $NODE_IP $MASTER_IP
```

Note that this permanently configures the nodes so they know where to talk to the master.
For a more flexible solution consider using a DNS name for the master (control service) node.

`6.` Teach the nodes (not the master) to trust eachother as root by copying (first generating if necessary) root's public key on each node into all other nodes' `/root/.ssh/authorized_keys` file.
This is only necessary for the ZFS backend since it uses SSH for peer-to-peer data migration.

`7.` You should now be able to make volume and container API requests to the master on port 4523 according to https://docs.clusterhq.com/en/0.4.0/advanced/api.html

`8.` **Bonus section!**

Note that the API in 0.4 has no authentication, authorization or secrecy. If you expose the control service publicly, anyone on the internet will be able to spin up privileged containers on your hosts. Be careful to use this in private environments! We are working on adding TLS to the API...

As a warm-up exercise, here's a demo of using `curl` to provision a simple stateless container on a host. We do this by modifying the configuration (*desired state*) and then polling the actual *state* while we wait for the image to download:

```
$ MASTER_IP=1.2.3.100
$ NODE_IP=1.2.3.101 # pick a node to create the container on
$ curl -s -XPOST -d '{"host": "'${NODE_IP}'", "name": "webserver", "image": "nginx:latest"}' \
  --header "Content-type: application/json" http://${MASTER_IP}:4523/v1/configuration/containers | jq .
```

Now can now log into `$NODE_IP` via SSH and watch the image being downloaded (e.g. using `top`, `bmon`, `docker images`). Note that this can take some time, depending on the image you chose, your internet connection and other factors. Be patient!

Once the image is downloaded on the target node, Flocker's container control service will automatically start the container on the specified host and report this back via the containers state endpoint. Let's see it show up in the desired state:

```
$ curl -s http://${MASTER_IP}:4523/v1/state/containers | jq .
[...]
```

You should get a non-empty list from the control service by the time the container is started on the host.

`9.` **Advanced demo - moving a stateful container**

OK, we've done the warm-up exercise. Time to move a stateful container between hosts! First step here is creating a dataset using the Flocker datasets API. We'll give it some metadata, a "name" in case we want to remember later why we created it:

```
$ curl -s -XPOST -d '{"primary": "'${NODE_IP}'", "metadata": {"name": "redis_data"}}' \
  --header "Content-type: application/json" http://${MASTER_IP}:4523/v1/configuration/datasets | jq .
```

Now let's poll the datasets state of the cluster until the volume shows up:
```
$ curl -s http://${MASTER_IP}:4523/v1/state/datasets | jq .
[...]
```

Keep running this command until you get a non-empty list as a result. The volume is now ready to get bound to a container! Make a note of the dataset id from the above json output, we'll need it later:

```
$ DATASET_ID=...
```

To make the rest of the demo quick, let's go and pre-fetch the image we're going to use on the hosts. This isn't strictly necessary but it makes the demo more fun.

```
$ NODE_IP_1=1.2.3.101
$ NODE_IP_2=1.2.3.102
$ ssh centos@NODE_IP_1 docker pull dockerfile/redis & \
  ssh centos@NODE_IP_2 docker pull dockerfile/redis
```

Let's start a Redis container with the volume. We'll also expose the port so we can connect to it:

```
$ curl -s -XPOST -d '{"host": "'${NODE_IP}'", "name": "redis", "image": "dockerfile/nginx:latest", ' \
  '"ports": [{"internal": 6379, "external": 6379}],' \
  '"volumes": [{"dataset_id": "'${DATASET_ID}'", "mountpoint": "/data"}]}' \
  --header "Content-type: application/json" http://${MASTER_IP}:4523/v1/configuration/containers | jq .
{...}
```

Now poll the state of the cluster and we'll see the container show up...

```
$ curl -s http://${MASTER_IP}:4523/v1/state/containers | jq .
[...]
```

We can now connect to either IP address of the container hosts and insert some data into Redis:

```
$ redis-cli ${NODE_IP_1}
redis> set hello world
redis> get hello
world
redis> save
```

You can log into the hosts and run `docker ps` to verify that the container is running on host 1:
```
$ echo "NODE 1:" && ssh ${NODE_IP_1} docker ps && \
  echo "NODE 2:" && ssh ${NODE_IP_2} docker ps
```

Now we can update the host of the container and Flocker will magically 2-phase-push the container to the second host... we can do this just by referencing the container's name and changing the host.

```
$ curl -s -XPOST -d '{"host": "'${NODE_IP}'"
  --header "Content-type: application/json" http://${MASTER_IP}:4523/v1/configuration/containers/redis | jq .
{...}
```

You can now watch as the container gets moved to the new host:

```
$ echo "NODE 1:" && ssh ${NODE_IP_1} docker ps && \
  echo "NODE 2:" && ssh ${NODE_IP_2} docker ps
```

You can also poll the control service to see the container's host change:

```
$ curl -s http://${MASTER_IP}:4523/v1/state/containers | jq .
```

As an exercise for the reader, why not find out what happens when you try to migrate a 1GB PostgreSQL database? Watch the output of `zfs list` and observe the small amount of downtime in the database...

What did you think of this demo? Let us know in the comments, on IRC on #clusterhq on Freenode, or on Hacker News...
