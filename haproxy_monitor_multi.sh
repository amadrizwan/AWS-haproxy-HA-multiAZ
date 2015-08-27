#!/bin/sh
# This script will monitor both VPN instances and swap routes
# if communication with the other instance fails

# LB instance variables
VIP=""   #IP address that is configured on looback interface. Should not be in VPC CIDR range
LB1_ID=""
LB2_ID=""
RT_ID=""   # VPN routing table ID
#remote range is usually 0.0.0.0/0
REMOTE_RANGE="0.0.0.0/0"


# Specify the EC2 region that this will be running in (e.g. https://ec2.eu-west-1.amazonaws.com)
EC2_URL=""

# Health Check variables
Num_Pings=3
Ping_Timeout=1
Wait_Between_Pings=1
Wait_for_Instance_Stop=60
Wait_for_Instance_Start=120



# Run aws-apitools-common.sh to set up default environment variables and to
# leverage AWS security credentials provided by EC2 roles
. /etc/profile.d/aws-apitools-common.sh

# Determine the VPN instances private IP so we can ping the both instance, swap
# its route, and reboot it. Requires EC2 DescribeInstances, ReplaceRoute, and Start/RebootInstances
# permissions. The following example EC2 Roles policy will authorize these commands:
# {
# "Statement": [
# {
# "Action": [
# "ec2:DescribeInstances",
# "ec2:CreateRoute",
# "ec2:ReplaceRoute",
# "ec2:StartInstances",
# "ec2:StopInstances"
# ],
# "Effect": "Allow",
# "Resource": "*"
# }
# ]
# }

# Get LB1 instance's IP
LB1_IP=`/opt/aws/bin/ec2-describe-instances $LB1_ID -U $EC2_URL | grep PRIVATEIPADDRESS -m 1 | awk -F$'\t' '{print $2;}'`
# Get LB2 instance's IP
LB2_IP=`/opt/aws/bin/ec2-describe-instances $LB2_ID -U $EC2_URL | grep PRIVATEIPADDRESS -m 1 | awk -F$'\t' '{print $2;}'`

# Get ENI ID of LB1 eth0
ENI_LB1=`/opt/aws/bin/ec2-describe-instances $LB1_ID -U $EC2_URL | grep NIC -m 1 | awk -F$'\t' '{print $2;}'`
# Get ENI ID of LB2 eth0
ENI_LB2=`/opt/aws/bin/ec2-describe-instances $LB2_ID -U $EC2_URL | grep NIC -m 1 | awk -F$'\t' '{print $2;}'`

# Get alloc ID for EIP
#EIP_ALLOC=`/opt/aws/bin/ec2-describe-addresses -U $EC2_URL | grep $EIP | awk -F$'\t' '{print $5;}'`

########################  Starting Script #######################

echo `date` "-- Starting VPN monitor"
echo `date` "-- Assigning VIP to LB1 ENI-1"
/opt/aws/bin/ec2-replace-route $RT_ID -r ${VIP}/32 -n $ENI_LB1 -U $EC2_URL
# If replace-route failed, then the route might not exist and may need to be created instead
if [ "$?" != "0" ]; then
 /opt/aws/bin/ec2-create-route $RT_ID -r ${VIP}/32 -n $ENI_LB1 -U $EC2_URL
fi
# Who has VIP, LB1 or 2
WHO_HAS_VIP="LB1"



while [ . ]; do
 # Check health of LB1 instance
 pingresult_LB1=`ping -c $Num_Pings -W $Ping_Timeout $LB1_IP | grep time= | wc -l`
 # Check to see if any of the health checks succeeded, if not
 if [ "$pingresult_LB1" == "0" ]; then
 # Set HEALTHY variables to unhealthy (0)
 LB1_HEALTHY=0
 STOPPING_LB1=0
 while [ "$LB1_HEALTHY" == "0" ]; do
 # LB1 instance is unhealthy, loop while we try to fix it
 if [ "$WHO_HAS_VIP" == "LB1" ]; then
 echo `date` "-- LB1 heartbeat failed, assigning VIP to LB2 instance ENI-1"
#/opt/aws/bin/ec2-associate-address -a $EIP_ALLOC -n $ENI_LB2 --allow-reassociation -U $EC2_URL
/opt/aws/bin/ec2-assign-private-ip-addresses -n $ENI_LB2 --secondary-private-ip-address $VIP --allow-reassignment -U $EC2_URL
 echo `date` "-- LB1 heartbeat failed, LB2 instance taking over $LB_RT_ID and $NODE_RT_ID routes"
/opt/aws/bin/ec2-replace-route $RT_ID -r $REMOTE_RANGE -n $ENI_LB2 -U $EC2_URL

        WHO_HAS_VIP="LB2"
 fi
 # Check LB1 state to see if we should stop it or start it again
 LB1_STATE=`/opt/aws/bin/ec2-describe-instances $LB1_ID -U $EC2_URL | grep INSTANCE | awk -F$'\t' '{print $6;}'`
 if [ "$LB1_STATE" == "stopped" ]; then
 echo `date` "-- LB1 instance stopped, starting it back up"
 /opt/aws/bin/ec2-start-instances $LB1_ID -U $EC2_URL
        LB1_HEALTHY=1
 sleep $Wait_for_Instance_Start
 else
        if [ "$STOPPING_LB1" == "0" ]; then
 echo `date` "-- LB1 instance $LB1_STATE, attempting to stop for reboot"
        /opt/aws/bin/ec2-stop-instances $LB1_ID -U $EC2_URL
        STOPPING_LB1=1
        fi
 sleep $Wait_for_Instance_Stop
 fi
 done
#else
fi

# Check health of LB2 instance
 pingresult_LB2=`ping -c $Num_Pings -W $Ping_Timeout $LB2_IP | grep time= | wc -l`
 # Check to see if any of the health checks succeeded, if not
 if [ "$pingresult_LB2" == "0" ]; then
 # Set HEALTHY variables to unhealthy (0)
 LB2_HEALTHY=0
 STOPPING_LB2=0
 while [ "$LB2_HEALTHY" == "0" ]; do
 # LB2 instance is unhealthy, loop while we try to fix it
 if [ "$WHO_HAS_VIP" == "LB2" ]; then
 echo `date` "-- LB2 heartbeat failed, assigning VIP to LB1 instance ENI-1"
#/opt/aws/bin/ec2-associate-address -a $EIP_ALLOC -n $ENI_LB1 --allow-reassociation -U $EC2_URL
/opt/aws/bin/ec2-assign-private-ip-addresses -n $ENI_LB1 --secondary-private-ip-address $VIP --allow-reassignment -U $EC2_URL
 echo `date` "-- LB2 heartbeat failed, LB1 instance taking over $LB_RT_ID and $NODE_RT_ID routes"
/opt/aws/bin/ec2-replace-route $NODE_RT_ID -r $REMOTE_RANGE -n $ENI_LB1 -U $EC2_URL
        WHO_HAS_VIP="LB1"
 fi
 # Check LB2 state to see if we should stop it or start it again
 LB2_STATE=`/opt/aws/bin/ec2-describe-instances $LB2_ID -U $EC2_URL | grep INSTANCE | awk -F$'\t' '{print $6;}'`
 if [ "$LB2_STATE" == "stopped" ]; then
 echo `date` "-- LB2 instance stopped, starting it back up"
 /opt/aws/bin/ec2-start-instances $LB2_ID -U $EC2_URL
        LB2_HEALTHY=1
 sleep $Wait_for_Instance_Start
 else
        if [ "$STOPPING_LB2" == "0" ]; then
 echo `date` "-- LB2 instance $LB2_STATE, attempting to stop for reboot"
        /opt/aws/bin/ec2-stop-instances $LB2_ID -U $EC2_URL
        STOPPING_LB2=1
        fi
 sleep $Wait_for_Instance_Stop
 fi
 done


 else
 sleep $Wait_Between_Pings
 fi
done
