# Get image

`aliyun ecs DescribeImages --RegionId us-east-1 --ImageFamily "acs:ubuntu_24_04_x64" | jq -r '.Images.Image[0].ImageId'`

# Create Keypair

`aliyun ecs CreateKeyPair --RegionId us-east-1 --KeyPairName ja-test-kp`

# Create Keypair and retrieve private key

`aliyun ecs CreateKeyPair --RegionId us-east-1 --KeyPairName cli-kp-test | jq -r '.PrivateKeyBody' > ./cli-kp-test.pem`

# Delete Keypair

`aliyun ecs DeleteKeyPairs --RegionId 'us-east-1' --KeyPairNames '["cli-kp-test"]'`

# Create instance
`aliyun ecs RunInstances --region us-east-1 --RegionId 'us-east-1' --ImageId 'ubuntu_24_04_x64_20G_alibase_20241115.vhd' --InstanceType 'ecs.c8i.2xlarge' --InstanceName 'ja-test-instance' --Password 'Sdiqpids1!' --SystemDisk.Size 25 --SystemDisk.Category cloud_essd --SystemDisk.DiskName SystemDisk --InstanceChargeType PostPaid --KeyPairName 'ja-test-kp' --HttpEndpoint enabled --DataDisk.1.Size 100 --DataDisk.1.DiskName datadisk --DataDisk.1.Category cloud_essd --NetworkInterface.1.VSwitchId 'vsw-0xijmr97kq8k6sjwzq0ys' --NetworkInterface.1.NetworkInterfaceName 'eni-20241220' --NetworkInterface.1.SecurityGroupId 'sg-0xiawxbg1mecv8pxhjba' --NetworkInterface.1.NetworkInterfaceTrafficMode standard --NetworkInterface.1.InstanceType Primary`

List of things I need to do:

* Generate Password
* Get VPC ID
aliyun vpc DescribeVpcs --RegionId us-east-1 | jq -r '.Vpcs.Vpc[]|select(.IsDefault=true).VpcId'
* Get a zoneId in the Region
aliyun ecs DescribeZones --RegionId us-east-1 | jq -r '.Zones.Zone[0].ZoneId'
* Create vSwitch
aliyun vpc CreateVSwitch --RegionId us-east-1 --VpcId vpc-0xirc0equ9ao05nveoqe4 --CidrBlock 172.16.1.0/28 --VSwitchName ja-test-switch --ZoneId us-east-1a | jq -r '.VSwitchId'
vsw-0xigizryzcfkackekd8mf
* Create Security Group
aliyun ecs CreateSecurityGroup --region us-east-1 --RegionId 'us-east-1' --VpcId 'vpc-0xirc0equ9ao05nveoqe4' --SecurityGroupName 'test-group' --Description 'test group' --SecurityGroupType normal | jq -r '.SecurityGroupId'
aliyun ecs AuthorizeSecurityGroup --region us-east-1 --RegionId 'us-east-1' --SecurityGroupId 'sg-0xiawxbg1medfcu9tpck' --Permissions.1.Policy accept --Permissions.1.IpProtocol TCP --Permissions.1.SourceCidrIp '0.0.0.0/0' --Permissions.1.PortRange '22/22' --Permissions.1.Description SSH --method POST --force
* Create Instance
`aliyun ecs RunInstances --region us-east-1 --RegionId 'us-east-1' --ImageId 'ubuntu_24_04_x64_20G_alibase_20241115.vhd' --InstanceType 'ecs.c8i.2xlarge' --InstanceName 'ja-test-instance' --Password 'Sdiqpids1!' --SystemDisk.Size 25 --SystemDisk.Category cloud_essd --SystemDisk.DiskName SystemDisk --InstanceChargeType PostPaid --KeyPairName 'ja-test-kp' --HttpEndpoint enabled --DataDisk.1.Size 100 --DataDisk.1.DiskName datadisk --DataDisk.1.Category cloud_essd --NetworkInterface.1.VSwitchId 'vsw-0xijmr97kq8k6sjwzq0ys' --NetworkInterface.1.NetworkInterfaceName 'eni-20241220' --NetworkInterface.1.SecurityGroupId 'sg-0xiawxbg1mecv8pxhjba' --NetworkInterface.1.NetworkInterfaceTrafficMode standard --NetworkInterface.1.InstanceType Primary`
* Create EIP
aliyun ecs AllocatePublicIpAddress --InstanceId <InstanceId>
* SCP exploder/startup
* Setup Image
* Create Image From Instance
* Teardown Instance
* Delete vSwitch
* Delete ENI
* Delete EIP
* Delete Security Group
* Create github action to create AMI
* Create a github action to deploy multiple AMI's to test clustering


Create an instance
`aliyun ecs RunInstances --region us-east-1 --RegionId 'us-east-1' --ImageId '' --InstanceType 'ecs.c8i.2xlarge' --InstanceName 'ja-test-instance' --Password 'Sdiqpids1!' --SystemDisk.Size 25 --SystemDisk.Category cloud_essd --SystemDisk.DiskName SystemDisk --InstanceChargeType PostPaid --KeyPairName 'ja-test-kp' --HttpEndpoint enabled --DataDisk.1.Size 100 --DataDisk.1.DiskName datadisk --DataDisk.1.Category cloud_essd --NetworkInterface.1.VSwitchId 'vsw-0xijmr97kq8k6sjwzq0ys' --NetworkInterface.1.NetworkInterfaceName 'eni-20241220' --NetworkInterface.1.SecurityGroupId 'sg-0xiawxbg1mecv8pxhjba' --NetworkInterface.1.NetworkInterfaceTrafficMode standard --NetworkInterface.1.InstanceType Primary`