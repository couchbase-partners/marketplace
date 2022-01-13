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
        'name': 'cb-gateway-waiter-{}'.format(suffix),
        'type': 'runtimeconfig.v1beta1.waiter',
        'properties': {
            'parent': parent,
            'waiter': 'cb-gateway-waiter-{}'.format(suffix),
            'timeout': '{}s'.format(timeout),
            'success': {
                'cardinality': {
                    'number': size,
                    'path': 'status/gateway/cb-gateway-{}/success'.format(suffix),
                },
            },
            'failure': {
                'cardinality': {
                    'number': 1,
                    'path': 'status/gateway/cb-gateway-{}/failure'.format(suffix),
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
        'value': 'status/gateway/cb-gateway-{}/success'.format(suffix)
    })
    outputs.append({
        'name': 'failurePath',
        'value': 'status/gateway/cb-gateway-{}/failure'.format(suffix)
    })
    return { 'resources': resources, 'outputs': outputs}
