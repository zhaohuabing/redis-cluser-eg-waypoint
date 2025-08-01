# redis-cluser-eg-waypoint

This is a simple example to show how to use Envoy Gateway (EG) waypoint to proxy the redis traffic in an Istio ambient mesh.

1. install Istio Amibent

```
istioctl install --set profile=ambient
```

1. install EG in the same cluster of the ambient mesh.

```
helm install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v0.0.0-latest \
  --set config.envoyGateway.provider.kubernetes.deploy.type=GatewayNamespace \
  --set config.envoyGateway.extensionApis.enableEnvoyPatchPolicy=true \
  -n envoy-gateway-system \
  --create-namespace
```

2. label the default namespace to enable ambient

```
kubectl label namespace default istio.io/dataplane-mode=ambient
```

3. install a test redis cluster in the external-redis namespace-this step is just for my testing. You can use an existing redis cluster. This script also installs a redis-client pod to test the connections to the redis cluster.
Note: please put all these files into one directory, and run install.sh.

After finishing installation, you should see output like this:

```
M: 61d939dcb93ec0f1f5a4a58edf3711e4a508e7ff 10.244.0.13:6379
   slots:[5461-10922] (5462 slots) master
   1 additional replica(s)
[OK] All nodes agree about slots configuration.
>>> Check for open slots...
>>> Check slots coverage...
[OK] All 16384 slots covered.
```

Then you can use the redis client to access the “exeternal redis cluster” service redis.external-redis, since it’s a cluster with 6 nodes, when run the set foo bar command, you probably will see a MOVED ... redirect response, which means that the slot is not on that node.

```
kubectl exec -it `kubectl get pod -l app=redis-client -o jsonpath="{.items[0].metadata.name}"` -c redis-client  -- redis-cli -h redis.external-redis

redis.external-redis:6379> set foo bar
(error) MOVED 12182 10.244.0.23:6379
redis.external-redis:6379>
```

5. Create the EG waypoint and EnvoyPatchPolicy to route the traffic through the redis proxy within EG.

```
kubectl apply -f envoy-gateway-waypoint.yaml
```

This configuration uses the test redis cluster redis.external-redis installed in the step 3, you can replace it with your own redis cluster:


```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyPatchPolicy
metadata:
  name: redis-envoy-patch-policy
  namespace: default
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: redis-waypoint
  type: JSONPatch
  jsonPatches:
  - name: default/redis-waypoint/redis
    type: type.googleapis.com/envoy.config.listener.v3.Listener
    operation:
      op: replace
      path: /filter_chains/0/filters/0
      value:
        name: envoy.filters.network.redis_proxy
        typed_config:
          '@type': type.googleapis.com/envoy.extensions.filters.network.redis_proxy.v3.RedisProxy
          prefix_routes:
            catch_all_route:
              cluster: redis_cluster
          settings:
            enable_redirection: true
            op_timeout: 5s
          stat_prefix: redis_stats
  - name: redis_cluster
    type: type.googleapis.com/envoy.config.cluster.v3.Cluster
    operation:
      op: add
      path: ""
      value:
        name: redis_cluster
        connect_timeout: 10s
        cluster_type:
          name: envoy.clusters.redis
        load_assignment:
          cluster_name: redis-cluster
          endpoints:
          - lb_endpoints:
            - endpoint:
                address:
                  socket_address:
                    address: redis.external-redis # please replace this with your redis service address
                    port_value: 6379
```

Then use the redis client to access the redis service in the default namesapce, which is proxied by the EG waypoint.

```
kubectl exec -it `kubectl get pod -l app=redis-client -o jsonpath="{.items[0].metadata.name}"` -c redis-client  -- redis-cli -h redis

redis:6379> set foo bar
OK
redis:6379> set foo1 bar1
OK
redis:6379>
```

waypoint log:

```
kubectl logs deployments/redis-waypoint |grep redis_proxy
...
[2025-07-29 13:19:46.543][55][debug][redis] [source/extensions/filters/network/redis_proxy/command_splitter_impl.cc:886] splitting '["set", "foo", "bar"]'
[2025-07-29 13:19:52.046][55][debug][redis] [source/extensions/filters/network/redis_proxy/command_splitter_impl.cc:886] splitting '["set", "foo1", "bar1"]'
```
