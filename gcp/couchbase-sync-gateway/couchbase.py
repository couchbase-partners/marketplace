from hashlib import sha1
from time import time

def generate_config(context):
    """ Entry Point for deployment Resources for Couchbase Gateway """
    resources = []
    
    tm = str(time.time())
    formattedSuffix = '{}-{}'.format(context.env['name'], tm)
    suffix = sha1(formattedSuffix.encode('utf-8')).hexdigest()[:10]
    config = {
        'name': 'cb-gateway-runtime-config-{}'.format(suffix),
        'type': './resources/runtime_config.py',
        'properties': {
            'username': context.properties['username'],
            'password': context.properties['password'],
            'nameSuffix': suffix,
            'connectionString': context.properties['couchbaseConnectionString'],
            'bucket': context.properties['bucket']
        }
    }
    resources.append(config)
    firewallRule = {
        'name': 'cb-gateway-firewall-rule-{}'.format(suffix),
        'type': './resources/firewall_rule.py',
        'properties': {
            'nameSuffix': suffix,
            'accessCIDR': context.properties['accessCIDR']
        }
    }
    resources.append(firewallRule)
    bootDiskImage = 'projects/couchbase-public/global/images/' + context.properties['imageName']
    instanceTemplate = {
        'name': 'cb-gateway-instance-template-{}'.format(suffix),
        'type': './resources/instance_template.py',
        'properties': {
            'nameSuffix': suffix,
            'network': 'default',
            'serverVersion': context.properties['serverVersion'],
            'runtimeConfigName': '$(ref.{}.runtimeConfigName)'.format(config['name']),
            'networkTag': '$(ref.{}.ruleTag)'.format(firewallRule['name']),
            'bootImage': bootDiskImage,
            'serviceAccount': context.properties['svcAccount']
        },
        'metadata': {
            "dependsOn": [config['name'], firewallRule['name']]
        }
    }
    resources.append(instanceTemplate)
    managedInstanceGroup = {
        'name': 'cb-gateway-instance-group-{}'.format(suffix),
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
        'name': 'cb-gateway-waiter-{}'.format(suffix),
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

