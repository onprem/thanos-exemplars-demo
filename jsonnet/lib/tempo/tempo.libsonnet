// These are the defaults for this components configuration.
// When calling the function to generate the component's manifest,
// you can pass an object structured like the default to overwrite default values.
local defaults = {
  local defaults = self,

  name: 'tempo',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  replicas: error 'must provide replicas',
  resources: {},
  ports: {
    http: {
      port: 3100,
      protocol: 'TCP',
    },
    'jaeger-http': {
      port: 14268,
      protocol: 'TCP',
    },
    'jaeger-compact': {
      port: 6831,
      protocol: 'UDP',
    },
  },
  serviceMonitor: false,

  // Tempo config.
  config:: {
    auth_enabled: false,

    server: {
      http_listen_port: defaults.ports.http.port,
    },

    distributor: {
      receivers: {
        jaeger: {
          protocols: {
            grpc: null,
            thrift_http: null,
            thrift_binary: null,
            thrift_compact: null,
          },
        },
      },
    },

    ingester: {
      trace_idle_period: '10s',
      max_block_bytes: 1000000,
      max_block_duration: '5m',
    },

    compactor: {
      compaction: {
        compaction_window: '1h',
        max_block_bytes: 100000000,
        block_retention: '1h',
        compacted_block_retention: '10m'
      },
    },
    
    storage: {
      trace: {
        backend: 'local',
        block: {
          bloom_filter_false_positive: 0.05,
          index_downsample_bytes: 1000,
          encoding: 'zstd',
        },
        wal: {
          path: '/data/tempo/wal',
          encoding: 'none',
        },
        'local': {
          path: '/data/tempo/blocks',
        },
        pool: {
          max_workers: 100,
          queue_depth: 10000,
        },
      },
    },
  },

  commonLabels:: {
    'app.kubernetes.io/name': 'tempo',
    'app.kubernetes.io/instance': defaults.name,
    'app.kubernetes.io/version': defaults.version,
  },

  podLabelSelector:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if labelName != 'app.kubernetes.io/version'
  },
};

function(params) {
  local tempo = self,

  // Combine the defaults and the passed params to make the component's config.
  config:: defaults + params,
  // Safety checks for combined config of defaults and params.
  assert std.isNumber(tempo.config.replicas) && tempo.config.replicas >= 0 : 'tempo replicas has to be number >= 0',
  assert std.isObject(tempo.config.resources) : 'resources has to be an object',
  assert std.isBoolean(tempo.config.serviceMonitor),

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      name: tempo.config.name,
      namespace: tempo.config.namespace,
      labels: tempo.config.commonLabels,
    },
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: tempo.config.name,
      namespace: tempo.config.namespace,
      labels: tempo.config.commonLabels,
    },
    spec: {
      selector: tempo.config.podLabelSelector,
      ports: [
        {
          name: name,
          port: tempo.config.ports[name].port,
          targetPort: tempo.config.ports[name].port,
          protocol: tempo.config.ports[name].protocol,
        }
        for name in std.objectFields(tempo.config.ports)
      ],
    },
  },

  configmap: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: {
      name: tempo.config.name,
      namespace: tempo.config.namespace,
      labels: tempo.config.commonLabels,
    },
    data: {
      'config.yaml': std.manifestYamlDoc(tempo.config.config),
    },
  },

  deployment: {
    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: {
      name: tempo.config.name,
      namespace: tempo.config.namespace,
      labels: tempo.config.commonLabels,
    },
    spec: {
      replicas: tempo.config.replicas,
      selector: { matchLabels: tempo.config.podLabelSelector },
      strategy: {
        rollingUpdate: {
          maxSurge: 0,
          maxUnavailable: 1,
        },
      },
      template: {
        metadata: {
          labels: tempo.config.commonLabels,
        },
        spec: {
          serviceAccountName: tempo.serviceAccount.metadata.name,
          containers: [
            {
              name: 'tempo',
              image: tempo.config.image,
              args: [
                '-config.file=/etc/tempo/config/config.yaml',
              ],
              ports: [
                { name: name, containerPort: tempo.config.ports[name].port, protocol: tempo.config.ports[name].protocol }
                for name in std.objectFields(tempo.config.ports)
              ],
              volumeMounts: [
                { name: 'config', mountPath: '/etc/tempo/config/', readOnly: false },
                { name: 'storage', mountPath: '/data', readOnly: false },
              ],
              resources: if tempo.config.resources != {} then tempo.config.resources else {},
            },
          ],
          volumes: [
            { name: 'config', configMap: { name: tempo.configmap.metadata.name } },
            { name: 'storage', emptyDir: {} },
          ],
        },
      },
    },
  },

  serviceMonitor: if tempo.config.serviceMonitor == true then {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata+: {
      name: tempo.config.name,
      namespace: tempo.config.namespace,
    },
    spec: {
      selector: {
        matchLabels: tempo.config.commonLabels,
      },
      endpoints: [{ port: 'http' }],
    },
  },
}
