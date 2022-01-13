from hashlib import sha1

def get_services(version):
    if version.startswith('7'):
        return 'data,index,query,fts,analytics,eventing,backup'
    else:
        return 'data,index,query,fts,analytics,eventing'

def generate_config(context):
    """ Entry Point for deployment Resources for Couchbase Server """
    resources = []
    
    suffix = sha1(context.env['name'].encode('utf-8')).hexdigest()[:10]
    config = {
        'name': 'cb-server-runtime-config-{}'.format(suffix),
        'type': './resources/runtime_config.py',
        'properties': {
            'username': context.properties['username'],
            'password': context.properties['password'],
            'nameSuffix': suffix
        }
    }
    resources.append(config)
    serviceAccount = {
        'name': 'cb-server-service-account-{}'.format(suffix),
        'type': './resources/iam_service_account.py',
        'properties': {
            'nameSuffix': suffix
        }
    }
    resources.append(serviceAccount)
    firewallRule = {
        'name': 'cb-server-firewall-rule-{}'.format(suffix),
        'type': './resources/firewall_rule.py',
        'properties': {
            'nameSuffix': suffix,
            'accessCIDR': context.properties['accessCIDR']
        }
    }
    resources.append(firewallRule)
    bootDiskImage = 'projects/couchbase-public/global/images/family/' + context.properties['imageFamily']
    instanceTemplate = {
        'name': 'cb-server-instance-template-{}'.format(suffix),
        'type': './resources/instance_template.py',
        'properties': {
            'nameSuffix': suffix,
            'network': 'default',
            'serverVersion': context.properties['serverVersion'],
            'runtimeConfigName': '$(ref.{}.runtimeConfigName)'.format(config['name']),
            'networkTag': '$(ref.{}.ruleTag)'.format(firewallRule['name']),
            'bootImage': bootDiskImage,
            'couchbaseServices': get_services(context.properties['serverVersion']),
            'serviceAccount': '$(ref.{}.serviceAccount)'.format(serviceAccount['name'])
        },
        'metadata': {
            "dependsOn": [ serviceAccount['name'], config['name'], firewallRule['name']]
        }
    }
    resources.append(instanceTemplate)
    managedInstanceGroup = {
        'name': 'cb-server-instance-group-{}'.format(suffix),
        'type': './resources/managed_instance_group.py',
        'properties': {
            'nameSuffix': suffix,
            'region': context.properties['region'],
            'instanceTemplate': '$(ref.{}.selfLink)'.format(instanceTemplate['name']),
            'size': context.properties['serverNodeCount']
        },
        'metadata': {
            'dependsOn': [instanceTemplate['name']]
        }

    }
    resources.append(managedInstanceGroup)
    waiter = {
        'name': 'cb-server-waiter-{}'.format(suffix),
        'type': './resources/waiter.py',
        'properties': {
            'nameSuffix': suffix,
            'runtimeConfigName': '$(ref.{}.runtimeConfigName)'.format(config['name']),
            'clusterSize': context.properties['serverNodeCount'],
            'timeout': 3000
        },
        'metadata': {
            'dependsOn': [ managedInstanceGroup['name'], config['name'] ]
        }
    }
    resources.append(waiter)
    outputs = [{
        'name': 'serviceAccount',
        'value': '$(ref.{}.serviceAccount)'.format(serviceAccount['name'])
    }, {
        'name': 'runtimeConfigName',
        'value': '$(ref.{}.runtimeConfigName)'.format(config['name'])
    },{
        'name': 'firewallRuleTag',
        'value': '$(ref.{}.ruleTag)'.format(firewallRule['name'])
    }, {
        'name': 'instanceTemplateName',
        'value': '$(ref.{}.templateName)'.format(instanceTemplate['name'])
    }]
    return { 'resources': resources, 'outputs': outputs }

