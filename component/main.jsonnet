local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.maxscale;
local namespace = params.namespace;

local secret = kube.Secret('maxscale') {
  metadata+: {
    namespace: params.namespace,
  },
  // Required for kube.SecretKeyRef()
  data: {
    service_pwd: '',
    monitor_pwd: '',
  },
  // Secrets are assumed to be Vault refs
  stringData: {
    service_pwd: params.maxscale.service_pwd,
    monitor_pwd: params.maxscale.monitor_pwd,
  },
};

local configvolume = {
  name: 'maxscale-cnf-volume',
  configMap: {
    name: 'maxscale-config',
    items: [
      {
        key: 'maxscale.cnf',
        path: 'maxscale.cnf',
      },
    ],
  },
};

local deployment = kube.Deployment('maxscale') {
  metadata+: {
    namespace: params.namespace,
    labels+: {
      'app.kubernetes.io/name': 'maxscale',
      'app.kubernetes.io/instance': inv.parameters.cluster.name,
      'app.kubernetes.io/managed-by': 'syn',
    },
  },
  spec+: {
    template+: {
      spec+: {
        containers_+: {
          maxscale: kube.Container('maxscale') {
            image: params.images.maxscale.image + ':' + params.images.maxscale.tag
            ,
            env_+: std.prune(com.proxyVars {
              MASTER_ONLY_LISTEN_ADDRESS: params.maxscale.master_only_listen_address,
              READ_WRITE_LISTEN_ADDRESS: params.maxscale.read_write_listen_address,
              DB1_ADDRESS: params.maxscale.db1_address,
              DB1_PORT: params.maxscale.db1_port,
              DB2_ADDRESS: params.maxscale.db2_address,
              DB2_PORT: params.maxscale.db2_port,
              DB3_ADDRESS: params.maxscale.db3_address,
              DB3_PORT: params.maxscale.db3_port,
              SERVICE_USER: params.maxscale.service_user,
              SERVICE_PWD: params.maxscale.service_pwd,
              MONITOR_USER: params.maxscale.monitor_user,
              MONITOR_PWD: params.maxscale.monitor_pwd,
            }),
            ports_+: {
              masteronly: { containerPort: 3306 },
              rwsplit: { containerPort: 3307 },
            },
            livenessProbe: {
              tcpSocket: {
                port: 'masteronly',
              },
              initialDelaySeconds: 15,
            },
            resources: {
              requests: {
                cpu: params.containers.resources.requests.cpu,
                memory: params.containers.resources.requests.memory,
              },
              limits: {
                cpu: params.containers.resources.limits.cpu,
                memory: params.containers.resources.limits.memory,
              },
            },
            volumeMounts: [
              {
                name: 'maxscale-cnf-volume',
                mountPath: '/etc/maxscale.cnf',
                subPath: 'maxscale.cnf',
              },
            ],
          },
        },
        volumes: [
          configvolume,
        ],
      },
    },
  },
};

local service_masteronly = kube.Service('maxscale-masteronly') {
  metadata+: {
    namespace: params.namespace,
    labels+: {
      'app.kubernetes.io/name': 'maxscale',
      'app.kubernetes.io/instance': inv.parameters.cluster.name,
      'app.kubernetes.io/managed-by': 'syn',
    },
  },
  target_pod: deployment.spec.template,
  spec+: {
    ports: [
      {
        name: 'masteronly',
        port: 3306,
        targetPort: deployment.spec.template.spec.containers[0].ports[0].containerPort,
      },
    ],
  },
};

local service_rwsplit = kube.Service('maxscale-rwsplit') {
  metadata+: {
    namespace: params.namespace,
    labels+: {
      'app.kubernetes.io/name': 'maxscale',
      'app.kubernetes.io/instance': inv.parameters.cluster.name,
      'app.kubernetes.io/managed-by': 'syn',
    },
  },
  target_pod: deployment.spec.template,
  spec+: {
    ports: [
      {
        name: 'rwsplit',
        port: 3306,
        targetPort: deployment.spec.template.spec.containers[0].ports[1].containerPort,
      },
    ],
  },
};

local configfile = kube.ConfigMap('maxscale-config') {
  metadata+: {
    namespace: params.namespace,
  },
  data: {
    'maxscale.cnf': kap.file_read('maxscale/configs/maxscale.cnf'),
  },
};


{
  '10_maxscale': [ secret, deployment, service_masteronly, service_rwsplit, configfile ],
}
