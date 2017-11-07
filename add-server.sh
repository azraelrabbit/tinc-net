#!/bin/sh

# Based on http://xmodulo.com/how-to-install-and-configure-tinc-vpn.html

set -ex

server=$1
interface=$2
tincIP=$3
tincName=$4
orgDefaultGateway=$5

if [ ! "$1" ]; then echo "server (IP or hostname) is required as argument #1"; exit 1; fi
if [ ! "$2" ]; then echo "network interface is required as argument #2"; exit 1; fi
if [ ! "$3" ]; then echo "IP-address required as argument #3"; exit 1; fi
if [ ! "$4" ]; then echo "tinc name is required as argument #4"; exit 1; fi
if [ ! "$5" ]; then echo "default gateway to resore is required as argument #5"; exit 1; fi

vpnName=scaleway
tincPath=/etc/tinc/$vpnName

tincGwIP=$(ip addr show tun0 | grep -o 'inet [^/]*' | cut -d' ' -f 2)
myIP=$(ip addr show $interface | grep -o 'inet [^/]*' | cut -d' ' -f 2)
myName=$(cat $tincPath/tinc.conf | awk '/Name/ { print $3}')

rsync -Pavvzessh /var/cache/apt/archives/tinc_*.deb root@${server}:/tmp

remoteScriptFile=$(mktemp)
chmod +x $remoteScriptFile
cat <<EOF > $remoteScriptFile
#!/bin/bash
dpkg -l tinc > /dev/null || dpkg -i /tmp/tinc_*.deb
systemctl enable tinc
systemctl restart tinc
mkdir -p ${tincPath}/hosts
if [ ! -f ${tincPath}/tinc.conf ]; then
	cat <<END > ${tincPath}/tinc.conf
Name = ${tincName}
AddressFamily = ipv4
Interface = tun0
Mode = switch
ConnectTo = ${myName}
END
fi
if [ ! -f ${tincPath}/hosts/${tincName} ]; then
	cat <<END > ${tincPath}/hosts/${tincName}
#Subnet = ${tincIP}/32
END
	tincd -n $vpnName -K4096
fi

cat <<'END' > ${tincPath}/tinc-up
#!/bin/sh
ifconfig INTERFACE ${tincIP} netmask 255.255.255.0
route add -host ${myIP} gw ${orgDefaultGateway}
route add default gw ${tincGwIP}
route del default gw ${orgDefaultGateway}
END

cat <<'END' > ${tincPath}/tinc-down
#!/bin/sh
ifconfig INTERFACE down
route add default gw ${orgDefaultGateway}
route del -host ${myIP} gw ${orgDefaultGateway}
route del default gw ${tincGwIP}
END

chmod +x ${tincPath}/tinc-{up,down}
modprobe tun
EOF
sed -i -e 's/INTERFACE/$INTERFACE/g' $remoteScriptFile
scp $remoteScriptFile root@$server:~/setup-tinc.sh
ssh root@$server 'bash -x ~/setup-tinc.sh'

rsync -Pavvzessh ${tincPath}/hosts/$myName $server:${tincPath}/hosts/
rsync -Pavvzessh $server:${tincPath}/hosts/${tincName} ${tincPath}/hosts/
tincd -n $vpnName -k HUP || tincd -n $vpnName

ssh root@$server "tincd -n $vpnName -k HUP || tincd -n $vpnName"