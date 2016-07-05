#!/bin/bash
name=${1:?missing name}
cloud_init_file=${2:?missing yaml file}
shift 2
grep -q EDITAR_ ${cloud_init_file} && { echo "ERROR: tenes que editar EDITAR_... en ${cloud_init_file}" ; exit 1; }
image=$(nova image-list | awk '/xenial.*disk1.img/{ print $4 }')
flavor=m1.small
net_id=$(nova net-list | awk '/net_umstack/{ print $2 }')
set -x
nova boot --image ${image} --nic net-id="${net_id}" --flavor ${flavor} --user-data ${cloud_init_file} "$@" ${name}
