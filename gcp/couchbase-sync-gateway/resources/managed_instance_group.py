def generate_config(context):
    # Here is where work is done.  This method is what is called to retrieve a dictionary that represents the type.
    # All required parameters defined in the schema will be present on the context object.  This must return a
    # python dict with a structure that matches the API items found
    resources = []
    outputs = []
    suffix = context.properties['nameSuffix']
    region = context.properties['region']
    instanceTemplate = context.properties['instanceTemplate']
    size = context.properties['size']
    instanceGroupManager = {
        'name': 'cb-gateway-instance-group-{}'.format(suffix),
        'type': 'compute.v1.regionInstanceGroupManager',
        'properties': {
            'region': region,
            'baseInstanceName': 'cb-gateway',
            'instanceTemplate': instanceTemplate,
            'targetSize': size
        }
    }
    resources.append(instanceGroupManager)
    return { 'resources': resources, 'outputs': outputs }
