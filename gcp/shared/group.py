import naming

URL_BASE = 'https://www.googleapis.com/compute/v1/projects/'

WAITER_TIMEOUT = '900s'

def GenerateConfig(context):
    runtimeconfigName = context.properties['runtimeconfigName']
    instanceGroupTargetSize = context.properties['nodeCount']

    externalIpCreateAction = GenerateExternalIpCreateActionConfig(context, runtimeconfigName)
    externalIpCreateActionName = externalIpCreateAction['name']

    instanceTemplate = GenerateInstanceTemplateConfig(context, runtimeconfigName)
    instanceTemplateName = instanceTemplate['name']

    instanceGroupManager = GenerateInstanceGroupManagerConfig(context, instanceTemplateName, instanceGroupTargetSize, externalIpCreateActionName)
    instanceGroupManagerName = instanceGroupManager['name']

    groupWaiter = GenerateGroupWaiterConfig(context, runtimeconfigName, instanceGroupManagerName, instanceGroupTargetSize)
    groupWaiterName = groupWaiter['name']

    config={}
    config['resources'] = [
        externalIpCreateAction,
        instanceTemplate,
        instanceGroupManager,
        groupWaiter,
    ]
    config['outputs'] = [
        {
            'name': 'externalIp',
            'value': '$(ref.%s.text)' % externalIpCreateActionName
        }
    ]
    return config

def GenerateExternalIpCreateActionConfig(context, runtimeconfigName):
    clusterName = context.properties['cluster']
    groupName = context.properties['group']
    project = context.env['project']

    externalIpVariablePath = _ExternalIpVariablePath(clusterName, groupName)
    actionName = naming.ExternalIpVariableCreateActionName(context, clusterName, groupName)
    action = {
        'name': actionName,
        'type': 'runtimeconfig.v1beta1.variable',
        'properties': {
            'parent': 'projects/%s/configs/%s' % (project, runtimeconfigName),
            'variable': externalIpVariablePath,
            'text': '<new_unknown>'
        },
        'metadata': {
            'dependsOn': [runtimeconfigName]
        }
    }
    return action

def GenerateInstanceTemplateConfig(context, runtimeconfigName):
    license = context.properties['license']

    # As I dropped the schema files to fix the disk issue this broke.  Need to dig in more here to figure out what's going on.
    # useImageFamily = context.properties['useImageFamily']
    useImageFamily = False

    if 'syncGateway' in context.properties['services']:
        sourceImage = _SyncGatewayImageUrl(license, useImageFamily)
    else:
        sourceImage = _ServerImageUrl(license, useImageFamily)

    clusterName = context.properties['cluster']
    groupName = context.properties['group']

    instanceTemplateName = naming.InstanceTemplateName(context, clusterName, groupName)

    instanceTemplate = {
        'name': instanceTemplateName,
        'type': 'compute.v1.instanceTemplate',
        'properties': {
            'properties': {
                'machineType': context.properties['nodeType'],
                'networkInterfaces': [{
                    'network': URL_BASE + context.env['project'] + '/global/networks/default',
                    'accessConfigs': [{
                        'name': 'External NAT',
                        'type': 'ONE_TO_ONE_NAT'
                    }]
                }],
                'disks': [{
                    'deviceName': 'boot',
                    'type': 'PERSISTENT',
                    'boot': True,
                    'autoDelete': True,
                    'initializeParams': {
                        'sourceImage': sourceImage,
                        'diskType': 'pd-ssd',
                        'diskSizeGb': context.properties['diskSize']
                    }
                }],
                'metadata': {
                    'items': [
                        { 'key': 'startup-script', 'value': GenerateStartupScript(context, runtimeconfigName) },
                        { 'key': 'runtime-config-name', 'value': runtimeconfigName },
                        { 'key': 'external-ip-variable-path', 'value': _ExternalIpVariablePath(clusterName, groupName) },
                        { 'key': 'status-success-base-path', 'value': _WaiterSuccessPath(clusterName, groupName) },
                        { 'key': 'status-failure-base-path', 'value': _WaiterFailurePath(clusterName, groupName) },
                    ]
                },
                'serviceAccounts': [{
                    'email': 'default',
                    'scopes': [
                        'https://www.googleapis.com/auth/cloud-platform',
                        'https://www.googleapis.com/auth/cloud.useraccounts.readonly',
                        'https://www.googleapis.com/auth/devstorage.read_only',
                        'https://www.googleapis.com/auth/logging.write',
                        'https://www.googleapis.com/auth/monitoring.write',
                        'https://www.googleapis.com/auth/cloudruntimeconfig'
                    ]
                }]
            }
        }
    }
    return instanceTemplate

def GenerateInstanceGroupManagerConfig(context, instanceTemplateName, instanceGroupTargetSize, externalIpCreateActionName):
    clusterName = context.properties['cluster']
    groupName = context.properties['group']

    instanceGroupManagerName = naming.InstanceGroupManagerName(context, clusterName, groupName)
    baseInstanceName = naming.InstanceGroupInstanceBaseName(context, clusterName, groupName)

    instanceGroupManager = {
        'name': instanceGroupManagerName,
        'type': 'compute.v1.regionInstanceGroupManager',
        'properties': {
            'region': context.properties['region'],
            'baseInstanceName': baseInstanceName,
            'instanceTemplate': '$(ref.' + instanceTemplateName + '.selfLink)',
            'targetSize': instanceGroupTargetSize
        },
        'metadata': {
            'dependsOn': [externalIpCreateActionName, naming.UsernameVariableName(context), naming.PasswordVariableName(context)]
        }
    }
    return instanceGroupManager

def GenerateGroupWaiterConfig(context, runtimeconfigName, instanceGroupManagerName, instanceGroupTargetSize):
    clusterName = context.properties['cluster']
    groupName = context.properties['group']

    groupWaiterName = naming.WaiterName(context, clusterName, groupName)
    groupWaiter = {
        'name': groupWaiterName,
        'type': 'runtimeconfig.v1beta1.waiter',
        'metadata': {
            'dependsOn': [instanceGroupManagerName],
        },
        'properties': {
            'parent': '$(ref.%s.name)' % runtimeconfigName,
            'waiter': groupWaiterName,
            'timeout': WAITER_TIMEOUT,
            'success': {
                'cardinality': {
                    'number': instanceGroupTargetSize,
                    'path': _WaiterSuccessPath(clusterName, groupName),
                },
            },
            'failure': {
                'cardinality': {
                    'number': 1,
                    'path': _WaiterFailurePath(clusterName, groupName),
                },
            },
        },
    }
    return groupWaiter

def GenerateStartupScript(context, runtimeconfigName):
    services=context.properties['services']
    version = context.properties['serverVersion'] if 'syncGateway' not in services else context.properties['syncGatewayVersion']
    sg = '-g' if 'syncGateway' in services else ''
    script = '''
#!/usr/bin/env bash
until apt-get update > /dev/null; do
    sleep 0.5
done

until apt-get install --assume-yes jq -qq; do
    sleep 0.5
done

function __get_gcp_metadata_value() {{ 
    wget -O - --header="Metadata-Flavor:Google" -q --retry-connrefused --waitretry=1 --read-timeout=10 --timeout=10 -t 5 "http://metadata/computeMetadata/v1/$1" 
}}

function __get_gcp_attribute_value() {{
    __get_gcp_metadata_value "instance/attributes/$1"
}}

ACCESS_TOKEN=$(__get_gcp_metadata_value "instance/service-accounts/default/token" | jq -r '.access_token')
PROJECT_ID=$(__get_gcp_metadata_value "project/project-id")
EXTERNAL_IP=$(__get_gcp_metadata_value "instance/network-interfaces/0/access-configs/0/external-ip")
CONFIG=$(__get_gcp_attribute_value "runtime-config-name")
EXTERNAL_IP_VAR_PATH=$(__get_gcp_attribute_value "external-ip-variable-path")
SUCCESS_STATUS_PATH="$(__get_gcp_attribute_value "status-success-base-path")/$(hostname)"
FAILURE_STATUS_PATH="$(__get_gcp_attribute_value "status-failure-base-path")/$(hostname)"
NODE_PRIVATE_DNS=$(__get_gcp_metadata_value "instance/hostname")
EXTERNAL_IP_PAYLOAD="$(printf '{{"name": "%s", "text": "%s"}}' "projects/$PROJECT_ID/configs/$CONFIG/variables/$EXTERNAL_IP_VAR_PATH" "$EXTERNAL_IP")"
wget -O - -q --retry-connrefused --waitretry=1 --read-timeout=10 --timeout=10 -t 5 --header="Authorization: Bearer $ACCESS_TOKEN" --header "Content-Type: application/json" --header "X-GFE-SSL: yes" --method=PUT --body-data="$EXTERNAL_IP_PAYLOAD" "https://runtimeconfig.googleapis.com/v1beta1/projects/$PROJECT_ID/configs/variables/$EXTERNAL_IP_VAR_PATH"
echo "Getting Cluster Host"
if [[ $(hostname) != *"syncgateway"* ]]; then
    gcp_hostname=$(curl -H "Metadata-Flavor: Google" -s http://metadata/computeMetadata/v1/instance/hostname)

    if ! gcloud beta runtime-config configs variables set {cluster}/{dnsconfig} $gcp_hostname --config-name={config} --fail-if-present; then
        CLUSTER_HOST=$(gcloud beta runtime-config configs variables get-value {cluster}/{dnsconfig} --config-name={config})
        until [[ -n "$CLUSTER_HOST" ]]; do
            sleep 0.5
            CLUSTER_HOST=$(gcloud beta runtime-config configs variables get-value {cluster}/{dnsconfig} --config-name={config})
        done
    else
        CLUSTER_HOST=$gcp_hostname
    fi
else
    CLUSTER_HOST=$(gcloud beta runtime-config configs variables get-value {cluster}/{dnsconfig} --config-name={config})
    count=0
    until [[ ! -z "$CLUSTER_HOST" ]] || [[ "$count" == "10" ]] ; do
        CLUSTER_HOST=$(gcloud beta runtime-config configs variables get-value {cluster}/{dnsconfig} --config-name={config})
        sleep 1
        count=$((count + 1))
    done
    if [[ "$count" == 10 ]]; then
        CLUSTER_HOST=$(curl -H "Metadata-Flavor: Google" -s http://metadata/computeMetadata/v1/instance/hostname)
    fi
fi
echo "Cluster Host is $CLUSTER_HOST"
echo "Installing version: {version}"
VERSION={version}
echo "Getting Username/Passwords"
USERNAME=$(gcloud beta runtime-config configs variables get-value {username} --config-name={config})
until [[ -n "$USERNAME" ]]; do
    sleep 0.5
    USERNAME=$(gcloud beta runtime-config configs variables get-value {username} --config-name={config})
done
PASSWORD=$(gcloud beta runtime-config configs variables get-value {password} --config-name={config})
until [[ -n "$PASSWORD" ]]; do
    sleep 0.5
    PASSWORD=$(gcloud beta runtime-config configs variables get-value {password} --config-name={config})
done
echo "Username: $USERNAME"
echo "Password: $PASSWORD"
NODE_COUNT={node_count}
echo "RETRIEVED USERNAME/PASSWORD"

# Before we install.  we need to specify the cluster host dns to the deployment
gcp_hostname=$(curl -H "Metadata-Flavor: Google" -s http://metadata/computeMetadata/v1/instance/hostname)
if [[ "$CLUSTER_HOST" == "$gcp_hostname" ]]; then
    external_ip=$(curl -H "Metadata-Flavor: Google" -s http://metadata/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)
    gcloud beta runtime-config configs variables set external-ip/clusters/{cluster}/groups/server  "$external_ip" --config-name={config}
fi

echo "Downloading Install Script"
if [[ ! -e "couchbase_installer.sh" ]]; then
    curl -L --output "couchbase_installer.sh" "__SCRIPT_URL__"
fi
echo "Executing Install Script"
bash ./couchbase_installer.sh -ch "$CLUSTER_HOST" -u "$USERNAME" -p "$PASSWORD" -v "$VERSION" -os UBUNTU -e GCP -s -c -d -w $NODE_COUNT {sg}
echo "Performing Post Install Configuration"
host=$(hostname)
SUCCESS_PAYLOAD="$(printf '{{"name": "%s", "text": "%s"}}' \
"projects/$PROJECT_ID/configs/$CONFIG/variables/$SUCCESS_STATUS_PATH/$host" \\
"success")"

# Notify waiter
wget -O - \\
    --retry-connrefused \\
    --waitretry=1 \\
    --read-timeout=10 \\
    --timeout=10 \\
    -t 5 \\
    --body-data="$SUCCESS_PAYLOAD" \\
    --header="Authorization: Bearer $ACCESS_TOKEN" \\
    --header "Content-Type: application/json" \\
    --header "X-GFE-SSL: yes" \\
    --method=POST \\
    "https://runtimeconfig.googleapis.com/v1beta1/projects/$PROJECT_ID/configs/$CONFIG/variables"
    '''.format(cluster=context.properties['cluster'], 
               username='cb-username', 
               password='cb-password', 
               dnsconfig='rallyPrivateDNS', 
               config=runtimeconfigName, 
               node_count=str(context.properties['clusterNodesCount']), 
               version=version, 
               sg=sg)

    return script

def _SyncGatewayImageUrl(license, useFamily):
    if useFamily:
        return URL_BASE + 'couchbase-public/global/images/family/couchbase-sync-gateway' + license
    else:
        return URL_BASE + 'couchbase-public/global/images/couchbase-sync-gateway' + license + '-v20210408'

def _ServerImageUrl(license, useFamily):
    if (useFamily):
        return URL_BASE + 'couchbase-public/global/images/family/couchbase-server' + license
    else:
        return URL_BASE + 'couchbase-public/global/images/couchbase-server' + license + '-v20210408'

def _WaiterSuccessPath(clusterName, groupName):
    return 'status/clusters/%s/groups/%s/success' % (clusterName, groupName)

def _WaiterFailurePath(clusterName, groupName):
    return 'status/clusters/%s/groups/%s/failure' % (clusterName, groupName)

def _ExternalIpVariablePath(clusterName, groupName):
    return 'external-ip/clusters/%s/groups/%s' % (clusterName, groupName)
