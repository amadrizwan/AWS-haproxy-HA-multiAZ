# AWS-haproxy-HA-multiAZ

A script that runs on monitor instance and provide high availability to HAPROXY instances in multiple Availability Zones. 
This script is for applications that require single private IP address (and not DNS address) with high avaiablity.

NOTE:
This only works when there is a VPN (AWS VPN or a VPN appliance) in front of LB. 
If EIP is intended, this script should not be used.

The loopback VIP  address can be configured on both HAPROXY instances at the same time.

CENTOS/RedHat: 
vi /etc/sysconfig/network-scripts/ifcfg-lo:1 
DEVICE=lo:1 
BOOTPROTO=static 
ONBOOT=yes 
IPADDR=172.31.xxx.xxx #any IP address NOT in VPC CIDR range
NETMASK=255.255.255.255

the script routes traffic destined to VIP to instance1 ENI if it is healthy. In ase of ping test failure, VPN routing table is changed so that the traffic is routed to haproxy instance2 ENI. 
