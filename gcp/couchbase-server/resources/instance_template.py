def generate_config(context):
    # Here is where work is done.  This method is what is called to retrieve a dictionary that represents the type.
    # All required parameters defined in the schema will be present on the context object.  This must return a
    # python dict with a structure that matches the API items found
    resources = []
    outputs = []
    project = context.env['project']
    network = context.properties['network']
    if isinstance(network, list):
         network = network[0]
    if network == "default":
            network = 'projects/{}/global/networks/{}'.format(project, network)
    subnetwork = None
    if 'subnetwork' in context.properties:
        subnetwork = context.properties['subnetwork']
    networkTag = context.properties['networkTag']
    suffix = context.properties['nameSuffix']
    serverInstanceType = context.properties['serverInstanceType']
    bootImage = context.properties['bootImage']
    serverDiskSize = context.properties['serverDiskSize']
    serverVersion = context.properties['serverVersion']
    runtimeConfigName = context.properties['runtimeConfigName']
    couchbaseServices = context.properties['couchbaseServices']
    serviceAccount = context.properties['serviceAccount']
    existingRally = context.properties['existingRallyUrl']
    createCluster = str(existingRally == "").lower()
    metadataItems = []
    if existingRally:
        metadataItems.append({ 'key': 'couchbase-server-rally-url', 'value': existingRally})
    
    metadataItems.append({ 'key': 'couchbase-server-version', 'value': serverVersion })
    metadataItems.append({ 'key': 'couchbase-server-make-cluster', 'value': createCluster })
    metadataItems.append({ 'key': 'couchbase-server-runtime-config', 'value': runtimeConfigName })
    metadataItems.append({ 'key': 'couchbase-server-services', 'value': couchbaseServices })
    metadataItems.append({ 'key': 'status-success-base-path', 'value': 'status/cluster/cb-cluster-{}/success'.format(suffix) })
    metadataItems.append({ 'key': 'status-failure-base-path', 'value': 'status/cluster/cb-cluster-{}/failure'.format(suffix) })
    metadataItems.append({ 'key': 'external-ip-variable-path', 'value': 'ExternalIp' })
    metadataItems.append({ 'key': 'couchbase-server-disk', 'value': 'cb-server-data' })
    
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
                    'deviceName': 'cb-server-data',
                    'type': 'PERSISTENT',
                    'boot': False,
                    'autoDelete': False,
                    'initializeParams': {
                        'diskType': 'pd-ssd',
                        'diskSizeGb': serverDiskSize
                    } 
                }],
                'metadata': {
                    'items': metadataItems
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

    if subnetwork != None:
        instanceTemplate['properties']['properties']['networkInterfaces'][0]['subnetwork'] = subnetwork
    
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