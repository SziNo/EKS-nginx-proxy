# EKS + NGINX DaemonSet reverse proxy – referencia megoldás

## A felépítés

```
Internet
   │
   ▼
AWS NLB (publikus subnet, saját security group)
   │  target-type: instance, externalTrafficPolicy: Local
   ▼
node:NodePort  → kernel DNAT (a kube-proxy szabályai alapján) → a helyi nginx pod
   │
   ▼
nginx (DaemonSet, nginx.conf a ConfigMap-ből, path alapú routing)
   ├── /api/sa → service-a.demo.svc.cluster.local (ClusterIP) → service-a podok
   └── /api/sb → service-b.demo.svc.cluster.local (ClusterIP) → service-b podok
```

A feladat ábráján a „Service A → Service B” nyíl **nem** hívási láncot jelent: az nginx útvonal alapján **párhuzamosan** osztja szét a kéréseket. Az app podok sem feltétlenül vannak minden node-on (Deploymentek), csak az nginx (DaemonSet).

## Mappaszerkezet

```
terraform/          VPC, EKS (managed node group), ECR, NLB security group, AWS Load Balancer Controller (IRSA + Helm)
apps/service-a/     Flask app + multi-stage Dockerfile + .dockerignore
apps/service-b/     ugyanez a B szolgáltatásnak
k8s/                Namespace, Deploymentek, ClusterIP Service-ek, nginx ConfigMap, DaemonSet, NLB Service, kustomization
scripts/            build-push.sh (ECR), render.sh (helyőrzők kitöltése a Terraform kimenetből)
```

## Előfeltételek

- AWS CLI bejelentkezve (`aws sts get-caller-identity`), Terraform ≥ 1.6, kubectl, Docker buildx.
- **Költség:** az EKS control plane, a NAT gateway, az NLB és a 3 EC2 óradíjas. A végén mindenképp bontsd le (lásd lent).

## Lépések

### 1. Infrastruktúra

```bash
cd terraform
terraform init
terraform apply          # ~15-20 perc, főleg az EKS
cd ..
$(terraform -chdir=terraform output -raw kubeconfig_command)
kubectl get nodes                                   # 3 node, Ready
kubectl get deploy -n kube-system aws-load-balancer-controller
```

### 2. Image-ek az ECR-be

```bash
./scripts/build-push.sh 1.0.0
```

### 3. Helyőrzők kitöltése és telepítés

```bash
./scripts/render.sh 1.0.0      # ECR cím, tag, NLB security group ID
kubectl kustomize k8s/         # ellenőrzés: mit fog létrehozni
kubectl apply -k k8s/
```

### 4. Ellenőrzés

```bash
kubectl get pods -n demo -o wide          # nginx minden node-on, A és B 2-2 replika
kubectl get endpointslices -n demo        # a Service-ek mögött ott vannak a pod IP-k
kubectl get svc nginx-proxy -n demo       # EXTERNAL-IP: az NLB DNS neve (pár perc)

NLB=$(kubectl get svc nginx-proxy -n demo -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://$NLB/api/sa     # Hello from Service A!
curl http://$NLB/api/sb     # Hello from Service B!
curl http://$NLB/           # 404, ahogy kell
```

Az NLB DNS neve és a targetek egészségessé válása 2–5 percig is eltarthat.

### 5. Lebontás (sorrend fontos!)

```bash
kubectl delete -k k8s/      # ELŐSZÖR: így a controller törli az NLB-t
# várj, amíg az NLB eltűnik (EC2 konzol → Load Balancers)
terraform -chdir=terraform destroy
```

Ha fordítva csinálod, a `terraform destroy` elakadhat a VPC törlésénél, mert az NLB (amit a controller hozott létre, nem a Terraform) még használja a subneteket és a security groupot.

## Döntések és indoklásuk

| Döntés                                                           | Miért                                                                                                                                               |
| ---------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Node-ok privát subnetben, NLB publikusban                        | Az internet csak az NLB-t éri el; kifelé NAT gateway                                                                                                |
| `/20`-as privát subnetek                                         | A VPC CNI miatt a podok is a subnetből kapnak IP-t                                                                                                  |
| `single_nat_gateway = true`                                      | Gyakorláshoz olcsóbb; élesben AZ-nként egy kell a magas rendelkezésre álláshoz                                                                      |
| `for_each` az ECR repókra, szolgáltatásnév kulccsal              | Stabil identitás; nincs index-eltolódás                                                                                                             |
| AWS Load Balancer Controller IRSA-val                            | Csak a controller ServiceAccountja kap ELB jogokat, nem az egész node                                                                               |
| `aws-load-balancer-type: external` + `scheme: internet-facing`   | Különben belső NLB jönne létre                                                                                                                      |
| `target-type: instance` + `externalTrafficPolicy: Local`         | DaemonSet esetén minden node-on van nginx: nincs extra ugrás, megmarad a kliens IP, és csak az egészséges nginx-et futtató node-ok kapnak forgalmat |
| Saját NLB security group + `manage-backend-security-group-rules` | A feladat kéri; a controller a node SG-be felveszi a szükséges bejövő szabályt                                                                      |
| `nginx-unprivileged`, 8080-as port                               | Nem rootként fut                                                                                                                                    |
| `proxy_pass` perjel nélkül                                       | A teljes útvonal (`/api/sa`) továbbmegy, a Flask pont erre figyel                                                                                   |
| Service DNS név, nem IP                                          | A ClusterIP állandó; a pod IP-k változnak                                                                                                           |
| `/healthz` minden komponensen                                    | Readiness probe-ok és az NLB health check                                                                                                           |
| gunicorn a Flask fejlesztői szervere helyett                     | Élesre alkalmas, több worker, exec formájú `CMD` a szép leálláshoz                                                                                  |
| `buildx --platform linux/amd64`                                  | ARM gépen buildelt image nem futna x86 node-on                                                                                                      |

## Ha valami nem működik

| Tünet                                                      | Valószínű ok                                                                                       | Ellenőrzés                                                                       |
| ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| App podok `ImagePullBackOff`                               | Rossz ECR cím vagy tag, nincs `render.sh`, vagy a node szerepnek nincs ECR joga                    | `kubectl describe pod`, `kubectl kustomize k8s/ \| grep image`                   |
| App pod `CrashLoopBackOff`, `exec format error`            | ARM image x86 node-on                                                                              | Buildeld újra `--platform linux/amd64`-gyel                                      |
| nginx pod `CrashLoopBackOff`, „host not found in upstream” | A Service-ek még nem léteztek az nginx indulásakor                                                 | `kubectl get svc -n demo`, majd `kubectl rollout restart ds/nginx-proxy -n demo` |
| `EXTERNAL-IP` sokáig `<pending>`                           | A controller nem fut, vagy nincs joga, vagy hiányzik a subnet tag                                  | `kubectl logs -n kube-system deploy/aws-load-balancer-controller`                |
| Az NLB létrejött, de nem válaszol                          | Belső NLB lett (hiányzó `scheme`), vagy security group szabály hiányzik, vagy a targetek unhealthy | EC2 konzol → Target Groups → Health, és a Service annotációi                     |
| `/api/sa` 404-et ad                                        | `proxy_pass` perjellel a végén levágja az útvonalat                                                | `kubectl get cm nginx-proxy-conf -n demo -o yaml`                                |
| `/api/sa` 502                                              | A Service mögött nincs ready pod, vagy rossz a `targetPort`                                        | `kubectl get endpointslices -n demo`, `kubectl logs -n demo ds/nginx-proxy`      |
| ConfigMap módosítás után nincs változás                    | Az nginx nem tölti újra magától                                                                    | `kubectl rollout restart ds/nginx-proxy -n demo`                                 |

## Továbbfejlesztési ötletek

- `target-type: ip`: az NLB közvetlenül az nginx podokra küld (a NodePort ugrás kimarad).
- HTTPS: ACM tanúsítvány az NLB-n (TLS listener), vagy TLS az nginx-ben.
- `preStop` hook és `terminationGracePeriodSeconds` az nginx-re, a frissítés közbeni 502-k ellen.
- Az nginx ConfigMap helyett Ingress Controller vagy Gateway API (ez a „miért nem Ingress?” interjúkérdés gyakorlati válasza).
- GitHub Actions pipeline a build-push és a telepítés automatizálására, vagy Argo CD GitOps-hoz.
- Remote Terraform state (S3 + `use_lockfile`).
