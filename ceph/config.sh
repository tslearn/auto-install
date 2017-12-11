#!/usr/bin/env bash

ADMIN_IP="192.168.0.82"
ADMIN_HOSTNAME="ceph-admin"

MONITOR_CLUSTER_NAMES="mon01"
MONITOR_IP_mon01="192.168.0.83"

OSD_CLUSTER_NAMES="osd01 osd02 osd03"
OSD_IP_osd01="192.168.0.91"
OSD_DISK_osd01="sdb"
OSD_IP_osd02="192.168.0.92"
OSD_DISK_osd02="sdb"
OSD_IP_osd03="192.168.0.93"
OSD_DISK_osd03="sdb"

NTP_SERVER="ntp5.aliyun.com"
CEPH_USER_NAME="ceph"
CEPH_CLUSTER_ADMIN_DIRECTORY="/opt/ceph/cluster"
CEPH_PUBLIC_NETWORK="192.168.0.0/24"
