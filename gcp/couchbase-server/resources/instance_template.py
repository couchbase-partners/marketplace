def generate_config(context):
    # Here is where work is done.  This method is what is called to retrieve a dictionary that represents the type.
    # All required parameters defined in the schema will be present on the context object.  This must return a
    # python dict with a structure that matches the API items found
    resources = []
    outputs = []
    project = context.env['project']
    network = context.properties['network']
    network = 'projects/{}/global/networks/{}'.format(project, network)
    networkTag = context.properties['networkTag']
    suffix = context.properties['nameSuffix']
    serverInstanceType = context.properties['serverInstanceType']
    bootImage = context.properties['bootImage']
    serverDiskSize = context.properties['serverDiskSize']
    serverVersion = context.properties['serverVersion']
    runtimeConfigName = context.properties['runtimeConfigName']
    couchbaseServices = context.properties['couchbaseServices']
    serviceAccount = context.properties['serviceAccount']

    instanceTemplate = {
        'name': 'cb-server-instance-template-{}'.format(suffix),
        'type': 'compute.v1.instanceTemplate',
        'properties': {
            'properties': {
                'machineType': serverInstanceType,
                'tags': { 'items': [ networkTag ] },
                'networkInterfaces': [{
                    'network': network,
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
                        'sourceImage': bootImage,
                        'diskType': 'pd-ssd',
                        'diskSizeGb': 10
                    }                  
                }, {
                    'deviceName': 'data',
                    'type': 'PERSISTENT',
                    'boot': False,
                    'autoDelete': False,
                    'initializeParams': {
                        'diskType': 'pd-ssd',
                        'diskSizeGb': serverDiskSize
                    } 
                }],
                'metadata': {
                    'items': [
                        { 'key': 'couchbase-server-version', 'value': serverVersion },
                        { 'key': 'couchbase-server-make-cluster', 'value': 'true' },
                        { 'key': 'couchbase-server-runtime-config', 'value': runtimeConfigName },
                        { 'key': 'couchbase-server-services', 'value': couchbaseServices },
                        { 'key': 'status-success-base-path', 'value': 'status/cluster/cb-cluster-{}/success'.format(suffix) },
                        { 'key': 'status-failure-base-path', 'value': 'status/cluster/cb-cluster-{}/failure'.format(suffix) },
                        { 'key': 'external-ip-variable-path', 'value': 'ExternalIp' },
                    ]
                },
                'serviceAccounts': [{
                    'email': serviceAccount,
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
    resources.append(instanceTemplate)
    outputs.append({
        'name': 'templateName',
        'value': 'cb-server-instance-template-{}'.format(suffix)
    })
    outputs.append({
        'name': 'selfLink',
        'value': '$(ref.{}.selfLink)'.format('cb-server-instance-template-{}'.format(suffix))
    })

    return {'resources': resources, 'outputs': outputs }