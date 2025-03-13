# Couchbase Ali Baba Cloud Image Tags

Tags are custom metadata key value pairs that can be applied to a couchbase server instance.  These tags control the behavior of the instance upon first boot.  Things such as the version of couchbase, the username and password, whether to create a cluster or not can be controlled via these tags. 
To use tags, you must create a Ram Role for the ECS instances that has the `AliyunECSReadOnlyAccess` permission.  This permission is used to access the tags placed on the instance to control startup behavior.  A less permissible policy can be used giving access to the ecs:ListTagResources action for resource types of instance.

```
{
    "Version": "1",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "ecs:ListTagResources",
            "Resource": "acs:ecs:*:*:instance/*"
        }
    ]
}
```

If no tags are present, the pre-installed version of Couchbase Server will launch in a create/join cluster mode.

### **couchbase-server-version**
Type: String

Description: Defines what version of couchbase server to deploy.  If this is not the version present on the AMI initially, it will download the appropriate version and install it.  It is expected to match a Couchbase Server Version.

Example Value: "7.6.4"

### **couchbase-server-services**
Type: Comma Delimited String

Description:  Defines what services should be executing on this instance.  Values can be data, index, query, analytics, fts, eventing, and backup

Example Value: "data,index,query"

### **couchbase-server-rally-url**
Type: String

Description:  The url to use to join a cluster.

Example Value:  "47.87.33.102"


### **couchbase-server-make-cluster**
Type: Boolean

Description:  Specifies that the instance should try to create a cluster.

Example Value: true

### **couchbase-server-username**
Type: String

Description: The couchbase user to use when initializing a node/cluster

Example Value: "couchbase"

### **couchbase-server-password**
Type: String

Description: The password for the couchbase user to use when initializing a node/cluster.  This should be removed after initlializing the cluster. 

Example Value: "Foo123!"

### **couchbase-server-disk**
Type: String

Description:  The disk to be used as the datadisk for Couchbase Server.  
*** Warning ***:  You cannot name disks when launching an instance via the console. Because of this limitation on the console, you cannot use this tag to use a separate data disk.

Example Value: "/dev/nvme1n1"