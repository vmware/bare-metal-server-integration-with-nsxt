#!/bin/bash

################################################################################
### Copyright (C) 2018 VMware, Inc.  All rights reserved.
### SPDX-License-Identifier: BSD-2-Clause
################################################################################

if (($# > 1)); then
    echo "Too many parameters: $@"
    exit
elif [ $# -eq 1 ]; then
    app_intf_name=$1
else
    app_intf_name=nsx-eth
fi

BMS_CMT_PREFIX="##BMS "
NSX_ETH=$app_intf_name
NSX_ETH_PEER=$NSX_ETH"-peer"
BMS_CONFIG_FILE="/etc/vmware/nsx-bm/bms.conf"


ip_address=
netmask=
gateway=
migrate_mac=
defaultGatewayIp=
defaultGatewayDev=
config_mode=
migrate_interface=
isStatic=

nsx_bm_log() {
    echo "${1}"
    logger -p daemon.info -t NSX-BMS "${1}"
}

get_os_type() {
    host_os=$(lsb_release -si)
    nsx_bm_log "host_os: $host_os"
    if isRhel; then
        nsx_bm_log "RHEL OS"
    elif isUbuntu; then
        nsx_bm_log "UBUNTU OS"
    else
        nsx_bm_log "unkown OS, abort"
        exit 1
    fi
}

isRhel() {
    if [ "$host_os" == "RedHatEnterpriseServer" ]; then
        return 0
    fi
    if [ "$host_os" == "RedHatEnterprise" ]; then
        return 0
    fi
    if [ "$host_os" == "CentOS" ]; then
        return 0
    fi
    if [ "$host_os" == "OracleServer" ]; then
        return 0
    fi
    return 1
}

isUbuntu() {
    if [ "$host_os" == "Ubuntu" ]; then
        return 0
    fi
    return 1
}

restore_ifcfg_file() {
    local intf_name=$1
    if isRhel; then
        ifcfg_file="/etc/sysconfig/network-scripts/ifcfg-"$intf_name
    elif isUbuntu; then
        ifcfg_file="/etc/network/interfaces"
    else
        nsx_bm_log "unkown OS, abort"
        exit 1
    fi

    nsx_bm_log "ifcfg_file: $ifcfg_file"

    sed -i "s/^$BMS_CMT_PREFIX//g" $ifcfg_file
}


parse_bms_config() {
    if [ ! -f $BMS_CONFIG_FILE ]; then
        nsx_bm_log "ERROR: BMS config file not found"
        exit 1
    fi

    while read line
    do
        output=($(echo $line | awk -F'=' '{print $1,$2}'))
        key="${output[0]}"
        value="${output[1]}"
        if [ "$key" == "config_mode" ]; then
            config_mode=$value
        elif [ "$key" == "migrate_interface" ]; then
            migrate_interface=$value
        elif [ "$key" == "isStatic" ]; then
            isStatic=$value
        elif [ "$key" == "defaultGatewayIp" ]; then
            defaultGatewayIp=$value
        elif [ "$key" == "defaultGatewayDev" ]; then
            defaultGatewayDev=$value
        fi
    done < $BMS_CONFIG_FILE
}

delete_nsx_bms_config() {
    rm -rf $BMS_CONFIG_DIR
}

get_os_type
parse_bms_config
nsx_bm_log "config_mode: $config_mode"
nsx_bm_log "migrate_interface: $migrate_interface"
nsx_bm_log "isStatic: $isStatic"

if [ "$config_mode" != "migrate" ]; then
    nsx_bm_log "config mode is not migration, exit"
    exit
fi

ovs-vsctl del-port $NSX_ETH_PEER

restore_ifcfg_file $migrate_interface

if [ "$isStatic" = false ]; then
    dhclient -r $NSX_ETH
fi

ip link delete $NSX_ETH
ifup $migrate_interface

if [ "$migrate_interface" == "$defaultGatewayDev" ]; then
    route add default gw $defaultGatewayIp
fi

if isRhel; then
    chkconfig --del nsx-baremetal
elif isUbuntu; then
    update-rc.d -f nsx-baremetal remove
fi


delete_nsx_bms_config

rm -f /etc/init.d/nsx-baremetal
rm -f /etc/vmware/nsx/nsx-baremetal.xml
/etc/init.d/nsx-agent restart
