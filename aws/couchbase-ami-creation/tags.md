# Supported Tags

When launching an AMI via EC2 or CFT, you can apply tags to the instance.  These tags will determine what Couchbase Server will do upon launch.  If no tags are present, the AMI will complete installation of couchbase server and start in a "Join or Create cluster" mode. See [Couchbase Server Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html) for details

## Utilizing Tags

For an EC2 instance to use tags, It must be assigned an EC2 role with a policy with access to certain SSM, EC2, and secretsmanager permissions.  Below are the specified permissions, They can be associated to a specific resource, however in the example they are not.

All tag operations require ec2:DescribeTags, ec2:CreateTags, and ec2:DescribeInstances, without these, the ec2 instance is unable to retrieve tags and will behave as if there are no tags present.  ssm:GetParameter, ssm:AddTagsToResource, and ssm:PutParameter are only required if "couchbase:server:rally_parameter" is used.  secretsmanager:GetSecretValue is only required if "couchbase:server:secret" is used. autoscaling:DescribeAutoScalingGroups is only required if instance is being launched as part of an autoscaling group. See [AWS Documentation](https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonec2.html) for details regarding these permissions.

**Example:**
```{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "ssm:PutParameter",
                "ec2:DescribeInstances",
                "secretsmanager:GetSecretValue",
                "ssm:AddTagsToResource",
                "ec2:DescribeTags",
                "ec2:CreateTags",
                "autoscaling:DescribeAutoScalingGroups",
                "ssm:GetParameter"
            ],
            "Resource": "*"
        }
    ]
}
```

## Supported Tags

### **couchbase:server:version**
Type:  string

Description:  Defines what version of couchbase server to deploy.  If this is not the version present on the AMI initially, it will download the appropriate version and install it.  It is expected to match a Couchbase Server version number.

Example Value:  "7.0.2"

### **couchbase:server:services**
Type: Comma Delimited String

Description:  Defines what services should be executing on this instance.  Values can be data, index, query, analytics, fts, eventing, and backup

Example Value: "data,index,query"

### **couchbase:server:rally_url**
Type: String

Description:  The url to use to join a cluster.  If rally_parameter and rally_url are both passed, rally_url will be ignored.

Example Value:  "ec2-3-222-200-75.compute-1.amazonaws.com"

### **couchbase:server:rally_parameter**
Type: AWS SSM Parameter Name

Description: The name of a SSM Parameter that stores the rally point dns for a node to join a cluster

Example Value: "couchbase_server_rallyurl"

### **couchbase:server:secret**
Type: AWS Secrets Manager Secret ARN

Description:  The ARN of a secret manager which is a JSON string with a "username" and "password" property that contains the couchbase server user/password to use.

Example Value: "arn:aws:secretsmanager:us-east-1:516524556673:secret:ja-test-mds-server-CouchbaseSecret-GoQj7J"

Example Secret:

```
{
    "username": "couchbase",
    "password": "Foo123!"
}
```

### **couchbase:server:make_cluster**
Type: Boolean

Description:  Specifies that the instance should try to create a cluster and update couchbase:server:rally_parameter with it's DNS (if passed).  If sent as part of an Auto-scaling group (All instances will get this tag), one of the instances will be elected as the rally point.

Example Value: true

### **couchbase:server:username**
Type: String

Description: The couchbase user to use when initializing a node/cluster

Example Value: "couchbase"

### **couchbase:server:password**
Type: String

Description: The password for the couchbase user to use when initializing a node/cluster.  This should be removed after initlializing the cluster.  Recommended to use a Secret Manager Secret.

Example Value: "Foo123!

## Future Supported Tags

* Service Memory - Currently only allows default allocations
* Volume Selection - Currently must have /dev/sdk specified as data volume
* Indvidual Service Tags - Currently must use comma delimted list