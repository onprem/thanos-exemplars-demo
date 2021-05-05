# Thanos Exemplars Demo

## Run this yourself

- We need a kubernetes cluster to install the manifests. You can run one locally using tools like minikube or KIND.

  ```
  kind create cluster --name demo
  ```

- After cluster gets created we can start by deploying the Kube Prometheus stack.

  ```
  kubectl apply -f manifests/kube-prometheus/setup
  kubectl apply -f manifests/kube-prometheus
  ```

- After Prometheus (and other deployements in the Kube Prometheus stack) comes up, we will deploy Thanos components.

  ```
  kubectl create ns thanos
  kubectl apply -f manifests/thanos
  ```

- At the same time, we will deploy Tempo as our tracing backend of choice.

  ```
  kubectl create ns tempo
  kubectl apply -f manifests/tempo
  ```

- After our metrics and tracing stack comes online, we can go ahead with deploying our demo application.

  ```
  kubectl create ns tns
  kubectl apply -f manifests/tns
  ```

- Now you can go to the Grafana by port-forwarding

  ```
  kubectl port-forward -n monitoring svc/grafana 3000
  ```

- Navigate to the `Explore` tab in Grafana and run this query to view exemplars:
  ```
  histogram_quantile(.99, sum(rate(tns_request_duration_seconds_bucket{}[1m])) by (le))
  ```
