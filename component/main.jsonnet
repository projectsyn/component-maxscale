local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.maxscale;
local res = if std.objectHas(params, 'resources') then params.resources else null;

local default_resources = {
  limits: {
    cpu: '2000m',
    memory: '512Mi',
  },
  requests: {
    cpu: '1000m',
    memory: '128Mi',
  },
};

local resources = if res != null then std.mergePatch(default_resources, res) else null;

local namespace = kube.Namespace(params.namespace) {
  metadata+: {
    labels+: {
      SYNMonitoring: 'main',
    },
  },
};

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
    service_pwd: params.service_pwd,
    monitor_pwd: params.monitor_pwd,
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
    replicas: params.replicas,
    template+: {
      spec+: {
        containers_+: {
          maxscale: kube.Container('maxscale') {
            image: params.images.maxscale.image + ':' + params.images.maxscale.tag,
            env_+: std.prune(com.proxyVars {
              MASTER_ONLY_LISTEN_ADDRESS: params.master_only_listen_address,
              READ_WRITE_LISTEN_ADDRESS: params.read_write_listen_address,
              DB1_ADDRESS: params.db1_address,
              DB1_PORT: params.db1_port,
              DB2_ADDRESS: params.db2_address,
              DB2_PORT: params.db2_port,
              DB3_ADDRESS: params.db3_address,
              DB3_PORT: params.db3_port,
              SERVICE_USER: params.service_user,
              SERVICE_PWD: params.service_pwd,
              MONITOR_USER: params.monitor_user,
              MONITOR_PWD: params.monitor_pwd,
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
            [if resources != null then 'resources']: resources,
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
  '00_namespace': namespace,
  '10_maxscale': [ secret, deployment, service_masteronly, service_rwsplit, configfile ],
}
