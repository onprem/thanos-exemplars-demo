local defaults = {
  local defaults = self,
  name: 'tns-loadgen',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  replicas: error 'must provide replicas',
  ports: {
    'http-metrics': 80,
  },
  resources: {},
  env: [],
  appURL: 'http://tns-app',
  serviceMonitor: false,

  commonLabels:: {
    'app.kubernetes.io/name': 'tns-loadgen',
    'app.kubernetes.io/instance': defaults.name,
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'loadgen',
  },

  podLabelSelector:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
};

function(params) {
  local tns = self,

  // Combine the defaults and the passed params to make the component's config.
  config:: defaults + params,
  // Safety checks for combined config of defaults and params
  assert std.isNumber(tns.config.replicas) && tns.config.replicas >= 0 : 'tns loadgen replicas has to be number >= 0',
  assert std.isObject(tns.config.resources),
  assert std.isBoolean(tns.config.serviceMonitor),

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      name: tns.config.name,
      namespace: tns.config.namespace,
      labels: tns.config.commonLabels,
    },
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: tns.config.name,
      namespace: tns.config.namespace,
      labels: tns.config.commonLabels,
    },
    spec: {
      selector: tns.config.podLabelSelector,
      ports: [
        {
          name: name,
          port: tns.config.ports[name],
          targetPort: tns.config.ports[name],
        }
        for name in std.objectFields(tns.config.ports)
      ],
    },
  },

  deployment: {
    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: {
      name: tns.config.name,
      namespace: tns.config.namespace,
      labels: tns.config.commonLabels,
    },
    spec: {
      replicas: tns.config.replicas,
      selector: { matchLabels: tns.config.podLabelSelector },
      strategy: {
        rollingUpdate: {
          maxSurge: 0,
          maxUnavailable: 1,
        },
      },
      template: {
        metadata: { labels: tns.config.commonLabels },
        spec: {
          serviceAccountName: tns.serviceAccount.metadata.name,
          containers: [
            {
              name: 'tns-app',
              image: tns.config.image,
              args: [
                '-log.level=debug',
                tns.config.appURL,
              ],
              env: tns.config.env,
              ports: [
                { name: name, containerPort: tns.config.ports[name] }
                for name in std.objectFields(tns.config.ports)
              ],
              resources: if tns.config.resources != {} then tns.config.resources else {},
            },
          ],
        },
      },
    },
  },

  serviceMonitor: if tns.config.serviceMonitor == true then {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata+: {
      name: tns.config.name,
      namespace: tns.config.namespace,
    },
    spec: {
      selector: {
        matchLabels: tns.config.commonLabels,
      },
      endpoints: [{ port: 'http-metrics' }],
    },
  },
}
