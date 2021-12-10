#!/bin/sh

name="wavefier-stable"
ip_number="4"
# SECURITY
cat <<EOF > .security_$name.yaml
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: longhorn-nfs-provisioner-$name
spec:
  fsGroup:
    rule: RunAsAny
  allowedCapabilities:
    - DAC_READ_SEARCH
    - SYS_RESOURCE
  runAsUser:
    rule: RunAsAny
  seLinux:
    rule: RunAsAny
  supplementalGroups:
    rule: RunAsAny
  volumes:
    - configMap
    - downwardAPI
    - emptyDir
    - persistentVolumeClaim
    - secret
    - hostPath
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: longhorn-nfs-provisioner-$name
rules:
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "update"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["create", "update", "patch"]
  - apiGroups: [""]
    resources: ["services", "endpoints"]
    verbs: ["get"]
  - apiGroups: ["extensions"]
    resources: ["podsecuritypolicies"]
    resourceNames: ["nfs-provisioner"]
    verbs: ["use"]
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: longhorn-nfs-provisioner-$name
subjects:
  - kind: ServiceAccount
    name: longhorn-nfs-provisioner-$name
    namespace: longhorn-system
roleRef:
  kind: ClusterRole
  name: longhorn-nfs-provisioner-$name
  apiGroup: rbac.authorization.k8s.io
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: leader-locking-longhorn-nfs-provisioner-$name
  namespace: longhorn-system
rules:
  - apiGroups: [""]
    resources: ["endpoints"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: leader-locking-longhorn-nfs-provisioner-$name
  namespace: longhorn-system
subjects:
  - kind: ServiceAccount
    name: longhorn-nfs-provisioner-$name
    namespace: longhorn-system
roleRef:
  kind: Role
  name: leader-locking-longhorn-nfs-provisioner-$name
  apiGroup: rbac.authorization.k8s.io
EOF

kubectl apply -f .security_$name.yaml


cat <<EOF > .provisioner_$name.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: longhorn-nfs-provisioner-$name
  namespace: longhorn-system
---
kind: Service
apiVersion: v1
metadata:
  name: longhorn-nfs-provisioner-$name
  namespace: longhorn-system
  labels:
    app: longhorn-nfs-provisioner-$name
spec:
  # hardcode a cluster ip for the service
  # so that on delete & recreate of the service the previous pv's still point
  # to this nfs-provisioner, pick a new ip for each new nfs provisioner
  clusterIP: 10.43.111.11$ip_number
  ports:
    - name: nfs
      port: 2049
    - name: nfs-udp
      port: 2049
      protocol: UDP
    - name: nlockmgr
      port: 32803
    - name: nlockmgr-udp
      port: 32803
      protocol: UDP
    - name: mountd
      port: 20048
    - name: mountd-udp
      port: 20048
      protocol: UDP
    - name: rquotad
      port: 875
    - name: rquotad-udp
      port: 875
      protocol: UDP
    - name: rpcbind
      port: 111
    - name: rpcbind-udp
      port: 111
      protocol: UDP
    - name: statd
      port: 662
    - name: statd-udp
      port: 662
      protocol: UDP
  selector:
    app: longhorn-nfs-provisioner-$name
---
kind: Deployment
apiVersion: apps/v1
metadata:
  name: longhorn-nfs-provisioner-$name
  namespace: longhorn-system
spec:
  selector:
    matchLabels:
      app: longhorn-nfs-provisioner-$name
  replicas: 1
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: longhorn-nfs-provisioner-$name
    spec:
      serviceAccount: longhorn-nfs-provisioner-$name
      containers:
        - name: longhorn-nfs-provisioner-$name
          image: quay.io/kubernetes_incubator/nfs-provisioner:latest
          ports:
            - name: nfs
              containerPort: 2049
            - name: nfs-udp
              containerPort: 2049
              protocol: UDP
            - name: nlockmgr
              containerPort: 32803
            - name: nlockmgr-udp
              containerPort: 32803
              protocol: UDP
            - name: mountd
              containerPort: 20048
            - name: mountd-udp
              containerPort: 20048
              protocol: UDP
            - name: rquotad
              containerPort: 875
            - name: rquotad-udp
              containerPort: 875
              protocol: UDP
            - name: rpcbind
              containerPort: 111
            - name: rpcbind-udp
              containerPort: 111
              protocol: UDP
            - name: statd
              containerPort: 662
            - name: statd-udp
              containerPort: 662
              protocol: UDP
          securityContext:
            capabilities:
              add:
                - DAC_READ_SEARCH
                - SYS_RESOURCE
          args:
            - "-provisioner=nfs.longhorn.io/$ip_number"
            - "-device-based-fsids=false"
          env:
            - name: POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
            - name: SERVICE_NAME
              value: longhorn-nfs-provisioner-$name
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
          imagePullPolicy: "IfNotPresent"
          readinessProbe:
            exec:
              command:
                - ls
                - /export
            initialDelaySeconds: 5
            periodSeconds: 5
          livenessProbe:
            exec:
              command:
                - ls
                - /export
            initialDelaySeconds: 5
            periodSeconds: 5
          volumeMounts:
            - name: export-volume
              mountPath: /export
      volumes:
        - name: export-volume
          persistentVolumeClaim:
            claimName: longhorn-nfs-provisioner-$name
      # we want really quick failover
      terminationGracePeriodSeconds: 30
      tolerations:
        - effect: NoExecute
          key: node.kubernetes.io/not-ready
          operator: Exists
          tolerationSeconds: 60
        - effect: NoExecute
          key: node.kubernetes.io/unreachable
          operator: Exists
          tolerationSeconds: 60
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: longhorn-nfs-provisioner-$name # longhorn backing pvc
  namespace: longhorn-system
spec:
  storageClassName: longhorn
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: "10G" # make this 10% bigger then the workload pvc
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-nfs-$name # workload storage class
provisioner: nfs.longhorn.io/$ip_number
mountOptions:
  - "vers=4.1"
  - "noresvport"
EOF

kubectl apply -f .provisioner_$name.yaml
