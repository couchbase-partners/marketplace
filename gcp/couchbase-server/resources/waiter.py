def generate_config(context):
    resources = []
    outputs = []
    suffix = context.properties['nameSuffix']
    runtimeConfigName = context.properties['runtimeConfigName']
    timeout = context.properties['timeout']
    size = context.properties['clusterSize']
    parent = 'projects/{}/configs/{}'.format(context.env['project'], runtimeConfigName)

    # create waiter for success/fail
    groupWaiter = {
        'name': 'cb-cluster-waiter-{}'.format(suffix),
        'type': 'runtimeconfig.v1beta1.waiter',
        'properties': {
            'parent': parent,
            'waiter': 'cb-cluster-waiter-{}'.format(suffix),
            'timeout': '{}s'.format(timeout),
            'success': {
                'cardinality': {
                    'number': size,
                    'path': 'status/cluster/cb-cluster-{}/success'.format(suffix),
                },
            },
            'failure': {
                'cardinality': {
                    'number': 1,
                    'path': 'status/cluster/cb-cluster-{}/failure'.format(suffix),
                },
            },
        },
        'metadata': {
            'dependsOn': [ runtimeConfigName ]
        }
    }
    resources.append(groupWaiter)
    outputs.append({
        'name': 'successPath',
        'value': 'status/cluster/cb-cluster-{}/success'.format(suffix)
    })
    outputs.append({
        'name': 'failurePath',
        'value': 'status/cluster/cb-cluster-{}/failure'.format(suffix)
    })
    return { 'resources': resources, 'outputs': outputs}
