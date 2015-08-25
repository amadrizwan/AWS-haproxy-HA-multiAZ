# AWS-haproxy-HA-multiAZ

A script that runs on monitor instance and provide high availability to HAPROXY instances in multiple Availability Zones. <br />
This script is for applications that require single private IP address (and not DNS address) with high availablity.

NOTE:<br />
This only works when there is a VPN (AWS VPN or a VPN appliance) in front of LB.<br /> 
If EIP is intended, this script should not be used.<br />

The loopback VIP  address can be configured on both HAPROXY instances at the same time.

CENTOS/RedHat: <br />
vi /etc/sysconfig/network-scripts/ifcfg-lo:1 <br />
DEVICE=lo:1 <br />
BOOTPROTO=static <br />
ONBOOT=yes <br />
IPADDR=172.31.xxx.xxx #any IP address NOT in VPC CIDR range<br />
NETMASK=255.255.255.255<br />

The script routes traffic destined for VIP to HAPROXY instance1's ENI if it is healthy. In case of ping test failure, VPN routing table is changed so that the traffic is routed to haproxy instance2's ENI. 
