#!/bin/bash

set +x

if ! command -v jq &> /dev/null
then
    echo "can't find jq, please install jq first"
    exit 1
fi

set -x

BASEDIR=$(dirname "$0")

kubectl -n default apply -f $BASEDIR/redis-client.yaml
kubectl -n external-redis apply -f $BASEDIR/redis-cluster.yaml
kubectl -n external-redis rollout status --watch statefulset/redis-cluster --timeout=600s
kubectl -n external-redis wait pod --selector=app=redis-cluster --for=condition=ContainersReady=True --timeout=600s -o jsonpath='{.status.podIP}'
kubectl exec -it redis-cluster-0 -c redis -n external-redis -- redis-cli --cluster create --cluster-yes --cluster-replicas 1 $(kubectl get pod -n external-redis -l=app=redis-cluster -o json | jq -r '.items[] | .status.podIP + ":6379"')
