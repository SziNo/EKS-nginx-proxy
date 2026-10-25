# EKS + NGINX DaemonSet reverse proxy

Két konténeres alkalmazás EKS-en, előttük minden node-on egy nginx reverse proxy (DaemonSet), amely útvonal alapján osztja szét a kéréseket. Kívülről egy publikus NLB érhető el. A teljes infrastruktúra Terraformmal, saját modulokból épül, az image-ek az ECR-ben vannak.

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

Az NLB 4. rétegű (csak TCP-t továbbít), az nginx 7. rétegű: lezárja a kliens kapcsolatát, kiolvassa a HTTP útvonalat, és egy új kapcsolatot nyit a megfelelő Service felé. A háttérpod bármelyik node-on lehet.

## Mappaszerkezet

```
terraform/                    root module: modulhívások, providerek, változók, outputok
  terraform.tfvars.example    a környezeti beállítások mintája (a terraform.tfvars nincs a gitben)
  modules/vpc/                VPC, subnetek (3 AZ), IGW, NAT gateway, route táblák
  modules/eks/                IAM szerepek, security groupok (az NLB-é is), cluster, addonok,
                              launch template, managed node group, OIDC provider, access entry
  modules/ecr/                a két ECR repó
  modules/lb-controller/      IRSA szerep + hivatalos IAM policy (iam_policy.json) + Helm release
apps/service-a/               Flask app + multi-stage Dockerfile + .dockerignore
apps/service-b/               ugyanez a B szolgáltatásnak
k8s/base/                     Namespace, Deploymentek, ClusterIP Service-ek, nginx ConfigMap,
                              DaemonSet, NLB Service, kustomization (környezetfüggő érték nélkül)
k8s/overlays/local/           a render.sh generálja (image cím, tag, NLB SG ID); nincs a gitben
scripts/                      build-push.sh (ECR), render.sh (overlay generálása), teardown.sh (lebontás)
docs/notes.md                 fogalmak, hibakeresési napló, nyitott pontok
```

## Előfeltételek

- AWS CLI bejelentkezve (`aws sts get-caller-identity`). Aki a Terraformot futtatja, az lesz a cluster adminja.
- Terraform ≥ 1.6, kubectl, Docker buildx. A Helm CLI opcionális (a Terraform a Helm providerrel telepít), hibakereséshez hasznos.
- A kubectl legfeljebb egy alverzióval térhet el a clustertől (a cluster most 1.37).
- Régió: `eu-west-1`.
- **Költség:** kb. 0,33 $/óra, amíg fut (részletek lent). Érdemes AWS Budget riasztást beállítani.

## Lépések

### 1. Infrastruktúra

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars   # szükség esetén szerkeszd
cd terraform
terraform init
terraform plan -out=tfplan     # 55 to add, 0 to change, 0 to destroy
terraform apply tfplan         # ~15-20 perc, főleg az EKS
cd ..
$(terraform -chdir=terraform output -raw kubeconfig_command)
kubectl get nodes                                          # 3 node, Ready
kubectl get deploy -n kube-system aws-load-balancer-controller
```

### 2. Image-ek az ECR-be

```bash
./scripts/build-push.sh 1.0.0
```

### 3. Overlay generálása és telepítés

```bash
./scripts/render.sh 1.0.0                # generálja a k8s/overlays/local overlay-t (ECR cím, tag, NLB SG ID)
kubectl kustomize k8s/overlays/local     # ellenőrzés: mit fog létrehozni
kubectl apply -k k8s/overlays/local
```

A `k8s/base/` a git által követett manifesteket tartalmazza, környezetfüggő érték nélkül. A `render.sh` minden futtatáskor újraírja a `k8s/overlays/local/kustomization.yaml`-t a Terraform aktuális kimenetéből, így akárhányszor futtatható (pl. egy új `apply` után új SG ID-vel). Az overlay nincs a gitben. A `build-push.sh`-nak és a `render.sh`-nak ugyanazt a taget kell megadni.

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

### 5. Lebontás

```bash
./scripts/teardown.sh
```

A szkript a helyes sorrendben bont: **először** a Kubernetes erőforrásokat (`kubectl delete -k k8s/base`; így a controller törli az NLB-t, amit nem a Terraform hozott létre), megvárja, amíg az NLB eltűnik, utána `terraform destroy` (jóváhagyást kér), végül ellenőrzi, hogy nem maradt-e load balancer, futó NAT gateway vagy EKS cluster. Ha fordítva bontanál, a `destroy` elakadna a VPC-n, mert az NLB még használja a subneteket és a security groupot. Törléshez a base elég, mert a `delete` csak a neveket nézi, és a base mindig megvan.

## Döntések és indoklásuk

### Infrastruktúra (Terraform)

| Döntés                                                             | Miért                                                                                                                                                                  |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Saját modulok, registry modul nélkül                               | A feladat IAM szerepeket és security groupokat kér; így mind látható és elmagyarázható a kódban. Gyakorlás is volt a cél.                                              |
| `for_each`, `count` nélkül                                         | Stabil, név szerinti kulcsok (AZ, repó név); egy elem törlése nem tolja el a többit.                                                                                   |
| Környezeti értékek a `terraform.tfvars`-ból, nem alapértékként     | A kód és a környezet beállításai külön vannak. A `lb_controller_chart_version` kivétel: az `iam_policy.json`-hoz kötődik, vagyis a kód része, ezért marad alapértéke.  |
| Provider verziók: rootban `~>`, modulokban `>=`                    | A root rögzíti, mit használ a projekt (és a lock fájl befagyasztja), a modul csak a minimumot jelzi. Az `init` a kettőt összefésüli.                                   |
| Node-ok privát subnetben, NLB publikusban                          | Az internet csak az NLB-t éri el; kifelé NAT gateway.                                                                                                                  |
| `/20`-as privát subnetek                                           | A VPC CNI miatt a podok is a subnetből kapnak IP-t.                                                                                                                    |
| Egy NAT gateway                                                    | Gyakorláshoz olcsóbb; élesben AZ-nként egy kell a magas rendelkezésre álláshoz.                                                                                        |
| Subnet tagek (`kubernetes.io/role/elb`, `internal-elb`)            | Ezekből tudja a controller, hová tegye a load balancert.                                                                                                               |
| Launch template a node groupnál                                    | Enélkül az EKS a saját cluster SG-jét tenné a node-okra, és a node SG szabályai nem érvényesülnének.                                                                   |
| Különálló SG szabály erőforrások, inline helyett                   | A Terraform így nem törli ki a controller által felvett szabályokat.                                                                                                   |
| Node SG: 9443 a cluster SG-ből                                     | Az LB Controller webhookja; nélküle a LoadBalancer Service létrehozása hibára fut.                                                                                     |
| Node SG: NodePort tartomány (30000–32767) az NLB SG-ből            | Ide érkezik az NLB forgalma és a health check (`healthCheckNodePort` is ebből a tartományból van).                                                                     |
| Addon sorrend: vpc-cni és kube-proxy a node-ok előtt, coredns után | A node-ok CNI nélkül nem lesznek Ready; a CoreDNS podjainak node kell, különben az addon DEGRADED marad.                                                               |
| Access entry, `API` hitelesítési mód                               | Explicit admin hozzáférés a Terraformot futtató IAM usernek, aws-auth ConfigMap nélkül.                                                                                |
| IMDSv2 (`http_tokens = required`), hop limit 2                     | Biztonságosabb metadata hozzáférés; a 2 kell ahhoz, hogy konténerből is elérhető legyen.                                                                               |
| AWS Load Balancer Controller IRSA-val                              | Csak a controller ServiceAccountja kap ELB jogokat, nem az egész node.                                                                                                 |
| LB Controller 3.6.2, a hivatalos `iam_policy.json` a repóban       | A 3.x óta a chart és a controller verziója egyezik; a policy JSON-nak a controller verziójához kell illeszkednie.                                                      |
| Helm provider 3.x                                                  | A `kubernetes`, `exec` és `set` itt attribútum (`= { }`, `= [ ]`), nem blokk.                                                                                          |
| Kubernetes 1.37                                                    | Standard támogatásban van (az extended support óradíja hatszoros), és illik a kubectl verziójához.                                                                     |
| `t3.medium`                                                        | A VPC CNI miatt a pod limit az ENI-k számától függ: `t3.micro`/`t2.micro` 4, `t3.small` 11, `t3.medium` 17 pod/node. A free tier `t2.micro`-n nem férnének el a podok. |
| ECR: `MUTABLE` tag, `force_delete`                                 | Gyakorlás közben felülírható tag; a `destroy` akkor is lefut, ha van image a repóban. Élesben `IMMUTABLE` ajánlott.                                                    |
| Egy state                                                          | Kicsi projekt, egy kezelő, egyszerre jön létre és bomlik le minden.                                                                                                    |

### Kubernetes és alkalmazások

| Döntés                                                           | Miért                                                                                                                                                                                                                                                                                                      |
| ---------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| nginx DaemonSet                                                  | Minden node-on fut egy proxy; bármelyik node kieshet, és az NLB a többire küld.                                                                                                                                                                                                                            |
| Kustomize base + generált overlay                                | A base-ben nincs környezetfüggő érték, a git által követett fájlokat semmi nem írja át. Az image címet, a taget és az NLB SG ID-t (ami minden `apply` után új) a `render.sh` írja egy gitignore-olt overlay-be. Csapatban környezetenkénti, commitolt overlayek lennének, és a CI állítaná az image taget. |
| A Service neve, `selector`-a és `targetPort`-ja                  | Mindhárom egy másik fájlhoz köt: a név az nginx ConfigMap DNS nevéhez (`service-a.demo.svc.cluster.local`), a selector a pod labeljeihez, a `targetPort` a konténer portjához.                                                                                                                             |
| `aws-load-balancer-type: external` + `scheme: internet-facing`   | Különben belső NLB jönne létre.                                                                                                                                                                                                                                                                            |
| `target-type: instance` + `externalTrafficPolicy: Local`         | Nincs extra ugrás node-ok között, nincs SNAT, megmarad a kliens IP, és csak az egészséges nginx-et futtató node-ok kapnak forgalmat. DaemonSet mellett az elosztás így is egyenletes.                                                                                                                      |
| Saját NLB security group + `manage-backend-security-group-rules` | A feladat kéri; a controller a node SG-be felveszi a szükséges bejövő szabályt.                                                                                                                                                                                                                            |
| `nginx-unprivileged`, 8080-as port                               | Nem rootként fut.                                                                                                                                                                                                                                                                                          |
| `runAsNonRoot: true`, a Dockerfile-ban `USER 10001`              | A kubelet nem indítja el a konténert, ha rootként futna. Számmal (UID) kell megadni, mert névből (`USER appuser`) nem tudja ellenőrizni.                                                                                                                                                                   |
| Memória limit, CPU limit nélkül                                  | A memória limit átlépésekor OOMKill (a node és a többi pod védelme); CPU limit nélkül nincs felesleges throttling, a request az ütemezéshez kell.                                                                                                                                                          |
| readiness és liveness probe a `/healthz`-en                      | A readiness dönti el, kap-e forgalmat a pod (EndpointSlice), a liveness újraindítja, ha leállt. Startup probe nem kell, mert a Flask gyorsan indul.                                                                                                                                                        |
| `proxy_pass` perjel nélkül                                       | A teljes útvonal (`/api/sa`) továbbmegy, a Flask pont erre figyel.                                                                                                                                                                                                                                         |
| Service DNS név, nem IP                                          | A ClusterIP állandó; a pod IP-k változnak.                                                                                                                                                                                                                                                                 |
| `X-Forwarded-For`, `X-Real-IP`                                   | Az nginx és az app közötti kapcsolatban már az nginx a feladó; az eredeti kliens IP ezekből derül ki.                                                                                                                                                                                                      |
| `/healthz` minden komponensen                                    | Readiness probe-ok és az NLB health check.                                                                                                                                                                                                                                                                 |
| gunicorn a Flask fejlesztői szervere helyett                     | Élesre alkalmas, több worker; exec formájú `CMD`, így PID 1-ként megkapja a `SIGTERM`-et.                                                                                                                                                                                                                  |
| Multi-stage Dockerfile, venv a `/opt/venv`-ben                   | A futtatott image-be csak a kész függőségek kerülnek; az útvonal mindkét szakaszban azonos, mert a venv szkriptjei abszolút útvonalra hivatkoznak.                                                                                                                                                         |
| `buildx --platform linux/amd64`                                  | ARM gépen buildelt image nem futna x86 node-on.                                                                                                                                                                                                                                                            |

## Ha valami nem működik

| Tünet                                                                    | Valószínű ok                                                                                            | Ellenőrzés / megoldás                                                                                  |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `Unexpected block: Blocks of type "set"/"kubernetes"`                    | Helm provider 3.x, régi blokk szintaxis                                                                 | `kubernetes = { ... }`, `set = [ ... ]`; `terraform init -upgrade`                                     |
| `No declaration found for "var.X"` / `Unexpected attribute` a tfvars-ban | Hiányzik a `variable "X"` blokk a root `variables.tf`-ben                                               | Deklaráld a változót                                                                                   |
| `no addon version found` a plan-nél                                      | Az addon még nem érhető el a választott Kubernetes verzióhoz                                            | Válassz eggyel régebbi verziót (`aws eks describe-cluster-versions`)                                   |
| `kubectl`: `Unauthorized`                                                | Más AWS identitással vagy, mint aki a clustert létrehozta                                               | `aws sts get-caller-identity`                                                                          |
| Podok `Pending`, pedig van szabad CPU és memória                         | Elfogyott a node pod limitje (ENI alapú)                                                                | `kubectl describe pod`, nagyobb instance típus                                                         |
| Pod `CreateContainerConfigError`: „image has non-numeric user”           | `runAsNonRoot: true`, de a Dockerfile-ban név szerepel a `USER` sorban                                  | `USER 10001` a Dockerfile-ban, újrabuildelés és push                                                   |
| App podok `ImagePullBackOff`                                             | Rossz ECR cím vagy tag, nem futott a `render.sh`, vagy a node szerepnek nincs ECR joga                  | `kubectl describe pod`, `kubectl kustomize k8s/overlays/local \| grep image`                           |
| App pod `CrashLoopBackOff`, `exec format error`                          | ARM image x86 node-on                                                                                   | Buildeld újra `--platform linux/amd64`-gyel                                                            |
| nginx pod `CrashLoopBackOff`, „host not found in upstream”               | A Service-ek még nem léteztek az nginx indulásakor, vagy eltér a Service neve                           | `kubectl get svc -n demo`, majd `kubectl rollout restart ds/nginx-proxy -n demo`                       |
| `EXTERNAL-IP` sokáig `<pending>`                                         | A controller nem fut, nincs joga, hiányzik a subnet tag, vagy régi (már törölt) SG ID van az overlayben | `kubectl logs -n kube-system deploy/aws-load-balancer-controller`; `./scripts/render.sh` újrafuttatása |
| Az NLB létrejött, de nem válaszol                                        | Belső NLB lett, hiányzik egy SG szabály, vagy a targetek unhealthy                                      | EC2 konzol → Target Groups → Health, és a Service annotációi                                           |
| `/api/sa` 404                                                            | `proxy_pass` perjellel a végén levágja az útvonalat                                                     | `kubectl get cm nginx-proxy-conf -n demo -o yaml`                                                      |
| `/api/sa` 502                                                            | A Service mögött nincs ready pod, nem egyezik a `selector`, vagy rossz a `targetPort`                   | `kubectl get endpointslices -n demo`, `kubectl logs -n demo ds/nginx-proxy`                            |
| ConfigMap módosítás után nincs változás                                  | Az nginx nem tölti újra magától                                                                         | `kubectl rollout restart ds/nginx-proxy -n demo`                                                       |
| `terraform destroy` elakad a VPC-n                                       | Az NLB még létezik (nem a Terraform hozta létre)                                                        | `./scripts/teardown.sh`, vagy előbb `kubectl delete -k k8s/base`                                       |

## Költség

| Tétel               | Kb. óradíj (eu-west-1) |
| ------------------- | ---------------------- |
| EKS control plane   | 0,10 $                 |
| 3 × t3.medium       | 0,14 $                 |
| NAT gateway         | 0,05 $ + adatforgalom  |
| NLB                 | 0,02–0,03 $            |
| Publikus IPv4 címek | 0,01–0,02 $            |
| **Összesen**        | **kb. 0,33 $/óra**     |

Egy próbakör a létrehozással és a lebontással együtt kb. 1,5–2 óra futásidő. A legnagyobb kockázat a lebontás után bent maradt erőforrás, ezért a `teardown.sh` a végén ellenőriz.

## Továbbfejlesztési ötletek

- **A state kettébontása** egy `infra` (VPC, EKS, ECR) és egy `platform` (LB Controller, Helm) root modulra. A Helm provider most egy ugyanabban a futásban létrejövő clusterhez csatlakozik; külön rétegben egy már létező cluster adataiból (`data "aws_eks_cluster"`) konfigurálódna. Futtatás: előbb `infra`, utána `platform`; lebontás fordítva.
- **Remote state S3-ban.** A bucketet előre, külön (CLI-vel vagy egy külön bootstrap konfigurációval) kell létrehozni, mert az `init` már keresi. Utána a root `versions.tf` `terraform` blokkjába kerül egy `backend "s3" { bucket, key, region, use_lockfile = true }`, és `terraform init -migrate-state` átköltözteti a helyi state-et. Zároláshoz DynamoDB már nem kell. A state bucketet a környezet lebontásakor sem törölnénk: csak akkor, ha a `destroy` biztosan maradéktalanul lefutott, verziózott bucketnél az összes objektumverzió törlése után.
- **Image tag a git commitból** (`git rev-parse --short HEAD`) a rögzített `1.0.0` helyett, és `IMMUTABLE` ECR repók: így egy tag mögött soha nem cserélődhet ki az image.
- **CI/CD:** GitHub Actions pipeline a build-push és a telepítés automatizálására, környezetenkénti, commitolt overlayekkel, vagy Argo CD GitOps-hoz.
- **Pod Security Admission** labelek a `demo` namespace-en (`pod-security.kubernetes.io/enforce: restricted`).
- `target-type: ip`: az NLB közvetlenül az nginx podokra küld (a NodePort ugrás kimarad).
- Ha `externalTrafficPolicy: Cluster` kellene, a kliens IP a **Proxy Protocol v2**-vel őrizhető meg (NLB annotáció + `listen ... proxy_protocol` az nginx-ben).
- HTTPS: ACM tanúsítvány az NLB-n (TLS listener), vagy TLS az nginx-ben.
- `preStop` hook és `terminationGracePeriodSeconds` az nginx-re, a frissítés közbeni 502-k ellen.
- Az nginx ConfigMap helyett **Gateway API** (GatewayClass, Gateway, HTTPRoute), az Ingress utódja.
