#!/bin/bash

function usage () {
	printf \
"usage: icingaclient [client_fqdn] [client_address] [parent_fqdn] \n
                     [parent_address] [parent_zone]"
}

function checkParam() {
	local param="$1"

	if [ -z "$param" ] ; then
		usage
		exit
	fi
}

function setParam() {
	local param="$1"
	local name="$2"

	if [ -z "$param" ] ; then
		read -p "Enter the ${name}:  " param
	fi	

	echo "$param"
}

function createClientCert() {
	local client="$1"
	local clientkey="${client}.key"
	local clientcsr="${client}.csr"
	local clientcert="${client}.crt"

	# Generate client's SSL key and csr.
	icinga2 pki new-cert \
		--cn $client \
		--key $clientkey \
		--csr $clientcsr
	
	# Sign the client cert
	icinga2 pki sign-csr \
		--csr $clientcsr \
		--cert $clientcert
}

if [ ! -z "$1" ] ; then
	checkParam "$2"
	checkParam "$3"
	checkParam "$4"
	checkParam "$5"
fi

client_name=$(setParam "$1" "fqdn of the client")
client_ip=$(setParam "$2" "client IP")
parent_name=$(setParam "$3" "fqdn of the parent")
parent_ip=$(setParam "$4" "parent IP")
parent_zone=$(setParam "$5" "zone name of the parent")

server_zones_file="/etc/icinga2/zones.d/${parent_zone}/${client_name}.conf"
agentconf="/usr/local/share/icingaclient/agent.conf"
childnodeconf="/usr/local/share/icingaclient/childnode.conf"
nsis_script="/usr/local/share/icingaclient/buildclient.nsis"
clientdir="/var/icingaclient"


if [ -f "${server_zones_file}" ]; then 
	echo "Client configuration for ${client_name} exists already" \
	    "see ${$server_zones_file}" \
	    "exiting..."
	exit 1
fi

# Generate client Icinga node configuration.
echo "Adding cluster definitions to ${parent_zone}..."
sed -n \
    -e "s/%cname/${client_name}/g" \
    -e "s/%caddr/${client_ip}/g" \
    -e "s/%pzone/${parent_zone}/g" \
    ${childnodeconf} > /etc/icinga2/zones.d/${parent_zone}/${client_name}.conf

# Build the agent for the child.
mkdir -p ${agentdir}/${client_name}
cd ${agentdir}/${client_name}
echo "===> ${agentdir}/${client_name}"

echo "Building agent's configuration..."
sed -n \
    -e "s/%%CLIENT_NAME%%/${client_name}/g" \
    -e "s/%%CLIENT_IP%%/${client_ip}/g" \
    -e "s/%%PARENT_NAME%%/${parent_name}/g" \
    -e "s/%%PARENT_IP%%/${parent_ip}/g" \
    -e "s/%%PARENT_ZONE%%/${parent_zone}/g" \
    ${agentconf} > icinga2.conf

# Generate agent certificates and copy in the master's CA. Since the privsep
# icinga user generates certificates, assign the correct privileges.
chown -R nagios:nagios .
chmod 770 .
echo "Generating signed certificates for ${client_name}..."
createClientCert "${client_name}"
echo "Copying in the master CA certificate..."
cp "/etc/icinga2/pki/ca.crt" ca.crt

echo "Compiling the Windows EXE installer..."
makensis -v1 \
    -DPARENT_NAME="${parent_name}" \
    -DCLIENT_NAME="${client_name}" \
    "${nsis_script}"
echo "done."

mv "icingaclient_${client_name}.exe" ${agentdir}
echo "Icinga2 agent installer created: " \
    "${agentdir}/icingaclient_${client_name}.exe"

echo "Cleaning up temporary working files..."
rm -rf ${agentdir}/${client_name}

echo "Reloading the icinga2 daemon..."
/etc/init.d/icinga2 restart
echo "To finish, transfer the generated installer " \
    "to ${client_name} then run it"
exit 0
