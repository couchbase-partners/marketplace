# Couchbase GCP Image Tags

Tags are custom metadata key value pairs that can be applied to a couchbase server instance.  These tags control the behavior of the instance upon first boot.  Things such as the version of couchbase, the username and password, whether to create a cluster or not can be controlled via these tags.

## Couchbase Server Tags

Server tags control the behavior of a Couchbase server upon launch.  If no tags are present, the pre-installed version of Couchbase Server will launch in a create/join cluster mode.

### **couchbase-server-version**
Type: String

Description: Defines what version of couchbase server to deploy.  If this is not hte version present on the AMI initially, it will download the appropriate version and install it.  It is expected to match a Couchbase Server Version.

Example Value: "7.0.2"

### **couchbase-server-services**
Type: Comma Delimited String

Description:  Defines what services should be executing on this instance.  Values can be data, index, query, analytics, fts, eventing, and backup

Example Value: "data,index,query"

### **couchbase-server-rally-url**
Type: String

Description:  The url to use to join a cluster.  If rally_parameter and rally_url are both passed, rally_url will be ignored.

Example Value:  "ec2-3-222-200-75.compute-1.amazonaws.com"

### **couchbase-server-rally-parameter**
Type: String

Description: The name of a Google Secrets Manager Secret that either contains the rally url or will contain the rally url if make-cluster is true.

Example Value: "couchbase-server-rally"

### **couchbase-server-make-cluster**
Type: Boolean

Description:  Specifies that the instance should try to create a cluster and update couchbase:server:rally_parameter with it's DNS (if passed).  If sent as part of an Auto-scaling group (All instances will get this tag), one of the instances will be elected as the rally point.

Example Value: true

### **couchbase-server-username**
Type: String

Description: The couchbase user to use when initializing a node/cluster

Example Value: "couchbase"

### **couchbase-server-password**
Type: String

Description: The password for the couchbase user to use when initializing a node/cluster.  This should be removed after initlializing the cluster.  Recommended to use a Secret Manager Secret.

Example Value: "Foo123!

### **couchbase-server-secret**
Type: String

Description: The name of a Google Secret Manager Secret that contains a json structure that holds the admin username and password for the Couchbase Cluster.

Example Value: 

```
{
    "username": "couchbase",
    "password": "Foo123!"
}
```

### **couchbase-server-disk**
Type: String

Description:  The disk to be used as the datadisk for Couchbase Server.  Defaults to /dev/sdb

Example Value: "/dev/sdb"

### **couchbase-server-runtime-config**
Type: String

Description:  The name of the runtime config to use for parameters when being deployed via Deployment Manager.  It will look for parameters for:  Username and Password within that Runtime Config.

Example Value: "couchbase-server-runtime-config-x6345234"


## Couchbase Sync Gateway Tags

Gateway tags control the behavior of a Couchbase Sync Gateway upon launch.  If no tags are present, the pre-installed version of Couchbase Sync Gateway will be initialized with default configuration.

### **couchbase-gateway-secret**
Type: String

Description: The name of a Google Secret Manager Secret that contains a json structure that holds the admin username and password for the Couchbase Cluster.

Example Value: 

```
{
    "username": "couchbase",
    "password": "Foo123!"
}
```

### **couchbase-gateway-username**
Type: String

Description: The couchbase user to use for Sync Gateway's connection to the Couchbase Cluster

Example Value: "couchbase"

### **couchbase-gateway-password**
Type: String

Description: The password for the couchbase user to use for Sync Gateway's connection to the Couchbase Cluster.  This should be removed after initlializing the instance.  Recommended to use a Secret Manager Secret.

Example Value: "Foo123!

### **couchbase-gateway-version**
Type: String

Description: Defines what version of Couchbase Sync Gateway to deploy.  If this is not the version present on the AMI initially, it will download the appropriate version and install it.  It is expected to match a Couchbase Sync Gateway Version.

Example Value: "7.0.2"

### **couchbase-gateway-connection-parameter**
Type: String

Description: The name of a Google Secrets Manager Secret that either contains the rally url or will contain the rally url if make-cluster is true.

Example Value: "couchbase-server-rally"

### **couchbase-gateway-connection-string**
Type: String

Description:  The url to use to join a cluster.  If rally_parameter and rally_url are both passed, rally_url will be ignored.

Example Value:  "ec2-3-222-200-75.compute-1.amazonaws.com"

### **couchbase-gateway-bucket**
Type: String

Description:  The name of the bucket to use for the initial database creation

Example Value: "travel-sample"