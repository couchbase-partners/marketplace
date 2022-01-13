def GenerateConfig(context):
    suffix = context.properties['nameSuffix']
    project = context.env['project']
    accountName = 'cb-gateway-sa-{}'.format(suffix)
    resources = []
    outputs = []
    outputs.append({
        'name': 'serviceAccount',
        'value': '{}@{}.iam.gserviceaccount.com'.format(accountName, project)
    })
    # create a service account and assign it to the created role
    serviceAccount = {
        'name': accountName,
        'type': 'iam.v1.serviceAccount',
        'properties': {
            'accountId': accountName,
            'displayName': 'Couchbase Gateway Service Account'
        }
    }
    resources.append(serviceAccount)
    # add a key to the user
    accountKey = {
        'name': 'cb-gateway-sa-key-{}'.format(suffix),
        'type': 'iam.v1.serviceAccounts.key',
        'properties': {
            'parent': 'projects/{}/serviceAccounts/{}@{}.iam.gserviceaccount.com'.format(project, accountName, project),
            'privateKeyType': 'TYPE_GOOGLE_CREDENTIALS_FILE'
        },
        'metadata': {
            'dependsOn': [accountName]
        }
    }
    resources.append(accountKey)
    # add a project bindings
    accessorBinding = {
        'name': 'cb-gateway-sa-secret-binding-{}'.format(suffix),
        'type': 'gcp-types/cloudresourcemanager-v1:virtual.projects.iamMemberBinding',
        'properties': {
            'role': 'roles/secretmanager.secretAccessor',
            'member': 'serviceAccount:{}@{}.iam.gserviceaccount.com'.format(accountName, project),
            'resource': project
        },
        'metadata': {
            'dependsOn': [accountName]
        }
    }
    resources.append(accessorBinding)
        # add a project binding?
    editorBinding = {
        'name': 'cb-gateway-sa-editor-binding-{}'.format(suffix),
        'type': 'gcp-types/cloudresourcemanager-v1:virtual.projects.iamMemberBinding',
        'properties': {
            'role': 'roles/editor',
            'member': 'serviceAccount:{}@{}.iam.gserviceaccount.com'.format(accountName, project),
            'resource': project
        },
        'metadata': {
            'dependsOn': [accountName]
        }
    }
    resources.append(editorBinding)
    return { 'resources': resources, 'outputs': outputs }