def GenerateConfig(context):
    suffix = context.properties['nameSuffix']
    configName = 'cb-gateway-runtime-config-{}'.format(suffix)
    parent = 'projects/{}/configs/{}'.format(context.env['project'], configName)
    config={}
    config['resources'] = []
    config['outputs'] = []
    # Set Outputs of runtime config
    config['outputs'].append({
        'name': 'runtimeConfigName',
        'value': configName
    })
    # create runtime config
    rc = {
        'name': configName,
        'type': 'gcp-types/runtimeconfig-v1beta1:projects.configs',
        'properties': {
            'config': configName,
            'description': context.properties['description']
        }
    }
    config['resources'].append(rc)

    # create Username Variable
    user = {
        'name': 'cb-username-{}'.format(suffix),
        'type': 'runtimeconfig.v1beta1.variable',
        'properties': {
            'parent': parent,
            'variable': 'Username',
            'text': context.properties['username'] 
        },
        'metadata': {
            'dependsOn': [configName]
        }
    }
    config['resources'].append(user)
    # create Password Variable
    password = {
        'name': 'cb-password-{}'.format(suffix),
        'type': 'runtimeconfig.v1beta1.variable',
        'properties': {
            'parent': parent,
            'variable': 'Password',
            'text': context.properties['password'] 
        },
        'metadata': {
            'dependsOn': [configName]
        }
    }
    config['resources'].append(password)
    # create RallySecretName
    rally = {
        'name': 'cb-connection-string-{}'.format(suffix),
        'type': 'runtimeconfig.v1beta1.variable',
        'properties': {
            'parent': parent,
            'variable': 'ConnectionString',
            'text': context.properties['connectionString'] 
        },
        'metadata': {
            'dependsOn': [configName]
        }
    }
    config['resources'].append(rally)
    # create SecretSecretName
    secret = {
        'name': 'cb-bucket-{}'.format(suffix),
        'type': 'runtimeconfig.v1beta1.variable',
        'properties': {
            'parent': parent,
            'variable': 'Bucket',
            'text': context.properties['bucket']
        },
        'metadata': {
            'dependsOn': [configName]
        }
    }
    config['resources'].append(secret)
    return config    
