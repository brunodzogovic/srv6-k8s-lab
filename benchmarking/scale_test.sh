#!/bin/bash
NUM_CLIENTS=${1:-5}
DURATION=${2:-30}
SERVER_IP="${3}"

# Launch multiple iperf3 client jobs in cluster1
for i in $(seq 1 $NUM_CLIENTS); do
  kubectl --context=kind-cluster1 create job --image=networkstatic/iperf3 \
    --restart=Never iperf-client-$i -- \
    iperf3 -c $SERVER_IP -t $DURATION
done

# Wait for jobs to complete and collect results
echo "Waiting for jobs to finish..."
kubectl --context=kind-cluster1 wait --for=condition=complete jobs --all --timeout=120s

echo "Results:"
TOTAL=0
for i in $(seq 1 $NUM_CLIENTS); do
  THROUGHPUT=$(kubectl --context=kind-cluster1 logs job/iperf-client-$i | grep -oP '\d+\.\d+ Mbits/sec' | tail -1)
  echo " Client $i: $THROUGHPUT"
  # (Parse value and accumulate if needed)
done

