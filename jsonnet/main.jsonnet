local common = {
  local cfg = self,
  prometheus: {
    namespace: 'monitoring',
  },
  thanos: {
    namespace: 'thanos',
    baseImage: 'quay.io/thanos/thanos',
    version: 'v0.20.1',
  },
  tempo: {
    namespace: 'tempo',
  },
  tracing: {
    host: 'tempo.' + common.tempo.namespace + '.svc',
    sampler_type: 'const',
    sampler_param: '1',
  },
};

local kp =
  (import 'kube-prometheus/main.libsonnet') +
  (import 'kube-prometheus/addons/all-namespaces.libsonnet') +
  // Uncomment the following imports to enable its patches
  // (import 'kube-prometheus/addons/anti-affinity.libsonnet') +
  // (import 'kube-prometheus/addons/managed-cluster.libsonnet') +
  // (import 'kube-prometheus/addons/node-ports.libsonnet') +
  // (import 'kube-prometheus/addons/static-etcd.libsonnet') +
  // (import 'kube-prometheus/addons/custom-metrics.libsonnet') +
  // (import 'kube-prometheus/addons/external-metrics.libsonnet') +
  {
    values+:: {
      common+: {
        namespace: common.prometheus.namespace,
      },
      prometheus+: {
        // Enable Operator for all namespaces.
        namespaces: [],
        thanos: {
          baseImage: common.thanos.baseImage,
          version: common.thanos.version,
        },
      },
      grafana+: {
        datasources: [
          {
            name: 'prometheus',
            type: 'prometheus',
            access: 'proxy',
            orgId: 1,
            url: 'http://thanos-query.' + common.thanos.namespace + '.svc:9090',
            version: 1,
            editable: false,
            jsonData: {
              exemplarTraceIdDestinations: [
                {
                  datasourceUid: 'tempo1',
                  name: 'traceID',
                },
              ],
            },
          },
          {
            name: 'tempo',
            type: 'tempo',
            access: 'proxy',
            orgId: 1,
            uid: 'tempo1',
            url: 'http://tempo.' + common.tempo.namespace + '.svc:3100',
            version: 1,
            editable: false,
          },
        ],
      },
    },
  };

local prometheus = kp.prometheus {
  prometheus+: {
    spec+: {
      enableFeatures: ['exemplar-storage'],
    },
  },
};

{ 'kube-prometheus/setup/0namespace-namespace': kp.kubePrometheus.namespace } +
{
  ['kube-prometheus/setup/prometheus-operator-' + name]: kp.prometheusOperator[name]
  for name in std.filter((function(name) name != 'serviceMonitor' && name != 'prometheusRule'), std.objectFields(kp.prometheusOperator))
} +
// serviceMonitor and prometheusRule are separated so that they can be created after the CRDs are ready
{ 'kube-prometheus/prometheus-operator-serviceMonitor': kp.prometheusOperator.serviceMonitor } +
{ 'kube-prometheus/prometheus-operator-prometheusRule': kp.prometheusOperator.prometheusRule } +
{ 'kube-prometheus/kube-prometheus-prometheusRule': kp.kubePrometheus.prometheusRule } +
{ ['kube-prometheus/alertmanager-' + name]: kp.alertmanager[name] for name in std.objectFields(kp.alertmanager) } +
{ ['kube-prometheus/blackbox-exporter-' + name]: kp.blackboxExporter[name] for name in std.objectFields(kp.blackboxExporter) } +
{ ['kube-prometheus/grafana-' + name]: kp.grafana[name] for name in std.objectFields(kp.grafana) } +
{ ['kube-prometheus/kube-state-metrics-' + name]: kp.kubeStateMetrics[name] for name in std.objectFields(kp.kubeStateMetrics) } +
{ ['kube-prometheus/kubernetes-' + name]: kp.kubernetesControlPlane[name] for name in std.objectFields(kp.kubernetesControlPlane) }
{ ['kube-prometheus/node-exporter-' + name]: kp.nodeExporter[name] for name in std.objectFields(kp.nodeExporter) } +
{ ['kube-prometheus/prometheus-' + name]: prometheus[name] for name in std.objectFields(prometheus) } +
{ ['kube-prometheus/prometheus-adapter-' + name]: kp.prometheusAdapter[name] for name in std.objectFields(kp.prometheusAdapter) } +

// Thanos

local t = import 'kube-thanos/thanos.libsonnet';

local thanosCommon = {
  config+:: {
    local cfg = self,
    namespace: common.thanos.namespace,
    version: common.thanos.version,
    image: common.thanos.baseImage + ':' + cfg.version,
    volumeClaimTemplate: {
      spec: {
        accessModes: ['ReadWriteOnce'],
        resources: {
          requests: {
            storage: '10Gi',
          },
        },
      },
    },
  },
};

local q = t.query(thanosCommon.config {
  replicas: 1,
  replicaLabels: ['prometheus_replica', 'rule_replica'],
  serviceMonitor: true,
  stores+: ['dnssrv+_grpc._tcp.prometheus-k8s-thanos-sidecar.' + common.prometheus.namespace + '.svc.cluster.local'],
  tracing: {
    type: 'JAEGER',
    config: {
      service_name: 'thanos_query',
      agent_host: common.tracing.host,
      sampler_type: common.tracing.sampler_type,
      sampler_param: 1,
      tags: 'namespace=' + common.thanos.namespace
    },
  },
});

local qnew = q {
  deployment+: {
    spec+: {
      template+: {
        spec+: {
          containers: [
            local c = q.deployment.spec.template.spec.containers[0];
            c {
              args: c.args +
                ['--target=dnssrv+_grpc._tcp.prometheus-k8s-thanos-sidecar.' + common.prometheus.namespace + '.svc.cluster.local'] +
                ['--exemplar=dnssrv+_grpc._tcp.prometheus-k8s-thanos-sidecar.' + common.prometheus.namespace + '.svc.cluster.local'],
            },
          ],
        },
      },
    },
  },
};

{ ['thanos/thanos-query-' + name]: qnew[name] for name in std.objectFields(qnew) } +

// Tempo

local tempo = (import './lib/tempo/tempo.libsonnet')({
  local cfg = self,
  namespace: common.tempo.namespace,
  version: '0.7.0',
  image: 'grafana/tempo:' + cfg.version,
  replicas: 1,
  serviceMonitor: true,
});

{ ['tempo/tempo-' + name]: tempo[name] for name in std.objectFields(tempo) } +

// Demo Application - grafana/tns

local tns = import './lib/tns/tns.libsonnet';

local tnsCommon = {
  config+:: {
    local cfg = self,
    namespace: 'tns',
    version: 'latest',
    replicas: 1,
    env: [
      {
        name: 'JAEGER_AGENT_HOST',
        value: common.tracing.host,
      },
      {
        name: 'JAEGER_TAGS',
        value: 'namespace=' + cfg.namespace,
      },
      {
        name: 'JAEGER_SAMPLER_TYPE',
        value: common.tracing.sampler_type,
      },
      {
        name: 'JAEGER_SAMPLER_PARAM',
        value: common.tracing.sampler_param,
      },
    ],
    serviceMonitor: true,
  },
};

local tnsapp = tns.app(tnsCommon.config {
  image: 'grafana/tns-app:' + tnsCommon.config.version,
});

local tnsdb = tns.db(tnsCommon.config {
  image: 'grafana/tns-db:' + tnsCommon.config.version,
});

local tnsloadgen = tns.loadgen(tnsCommon.config {
  image: 'grafana/tns-loadgen:' + tnsCommon.config.version,
});

{ ['tns/tns-app-' + name]: tnsapp[name] for name in std.objectFields(tnsapp) } +
{ ['tns/tns-db-' + name]: tnsdb[name] for name in std.objectFields(tnsdb) } +
{ ['tns/tns-loadgen-' + name]: tnsloadgen[name] for name in std.objectFields(tnsloadgen) }
