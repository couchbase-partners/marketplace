from hashlib import sha1
import time

def get_services(context):
    version = context.properties['serverVersion']
    services = ''
    if context.properties['data']:
        services += 'data,'
    if context.properties['index']:
        services += 'index,'
    if context.properties['query']:
        services += 'query,'
    if context.properties['search']:
        services += 'fts,'
    if context.properties['eventing']:
        services += 'eventing,'
    if context.properties['analytics']:
        services += 'analytics,'
    major = int(version[0])
    if major >= 7 and context.properties['backup']:
        services += "backup,"

    if (len(services) > 0):
        # trim last comma and return
        services = services[:-1]
    else:
        services = "data,index,query"
    
    return services

def generate_config(context):
    """ Entry Point for deployment Resources for Couchbase Server """
    resources = []
    tm = str(time.time())
    formattedSuffix = '{}-{}'.format(context.env['name'], tm)
    suffix = sha1(formattedSuffix.encode('utf-8')).hexdigest()[:10]
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
    firewallRule = {
        'name': 'cb-server-firewall-rule-{}'.format(suffix),
        'type': './resources/firewall_rule.py',
        'properties': {
            'nameSuffix': suffix,
            'accessCIDR': context.properties['accessCIDR']
        }
    }
    resources.append(firewallRule)
    bootDiskImage = 'projects/couchbase-public/global/images/' + context.properties['imageName']
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
            'couchbaseServices': get_services(context),
            'serviceAccount': context.properties['svcAccount'],
            'existingRallyUrl': context.properties['existingRallyUrl']
        },
        'metadata': {
            "dependsOn": [ ]
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
    outputs = [
    {
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

