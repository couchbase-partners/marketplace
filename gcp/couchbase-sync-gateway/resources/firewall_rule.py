def generate_config(context):
    # Here is where work is done.  This method is what is called to retrieve a dictionary that represents the type.
    # All required parameters defined in the schema will be present on the context object.  This must return a
    # python dict with a structure that matches the API items found
    network = context.properties['network']
    suffix = context.properties['nameSuffix']
    project = context.env['project']
    sourceCidr = context.properties['accessCIDR']
    network = 'projects/{}/global/networks/{}'.format(project, network)
    tag = 'couchbase-server-{}'.format(suffix)
    resources = []
    output = []

    rule = {
        'name': 'cb-gateway-firewall-rule-{}'.format(suffix),
        'type': 'gcp-types/compute-v1:firewalls',
        'properties': {
            'network': network,
            'priority': 1000,
            'project': project,
            'description': 'Firewall tag for Couchbase Sync Gateway,  allows ingress from {} CIDR and network tag: {}'.format(sourceCidr, tag),
            'sourceRanges': [sourceCidr],
            'destinationRanges': [],
            'targetTags': [tag],
            'sourceTags': [tag],
            'allowed': [{
                'IPProtocol': 'tcp',
                'ports': ['4984', '4985', '4986']
            }],
            'direction': 'INGRESS',
        }
    }
    resources.append(rule)
    output.append({
        'name': 'ruleTag',
        'value': tag
    })
    return {'resources': resources, 'outputs': output}