#!/bin/bash
#
#
#
default_route_iface=$(ip route show default | awk '{print $5}')

default_ip=$(ip route show |grep "${default_route_iface}" |awk 'NR>1{print $9}')

echo $default_ip
