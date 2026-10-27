# EKS + NGINX DaemonSet reverse proxy

Két konténeres alkalmazás EKS-en, előttük minden node-on egy nginx reverse proxy (DaemonSet), amely útvonal alapján osztja szét a kéréseket. Kívülről egy publikus NLB érhető el. A teljes infrastruktúra Terraformmal, saját modulokból (registry modulok nélkül) épül, az image-ek az ECR-ben vannak.

## A felépítés

```
Internet
   │
   ▼
AWS NLB (publikus subnet, saját security group, 80-as port)
   │  target-type: instance, externalTrafficPolicy: Local
   ▼
node:NodePort  → kernel DNAT (a kube-proxy szabályai alapján) → a helyi nginx pod (8080)
   │
   ▼
nginx (DaemonSet, konfiguráció a ConfigMap-ből, path alapú routing)
   ├── /api/sa → service-a.demo.svc.cluster.local (ClusterIP :80) → service-a podok (:8080)
   └── /api/sb → service-b.demo.svc.cluster.local (ClusterIP :80) → service-b podok (:8080)
```

- Az **NLB** 4. rétegű: csak a TCP kapcsolatot továbbítja a node-ok **NodePortjára**, a HTTP-be nem néz bele.
- A node-on a kernel a kube-proxy szabályai alapján a **helyi** nginx podra irányít (`Local` policy: nincs extra ugrás, megmarad a kliens IP).
- Az **nginx** 7. rétegű: lezárja a kliens kapcsolatát, kiolvassa az útvonalat, és egy **új** kapcsolatot nyit a megfelelő Service felé. A nevet a **CoreDNS** a Service ClusterIP-jére fordítja, a ClusterIP-t a kube-proxy egy ready pod IP-jére, ami bármelyik node-on lehet.
- A feladat ábráján a „Service A → Service B” nyíl nem hívási lánc: az nginx a kéréseket útvonal szerint **párhuzamosan** osztja szét.

## Mappaszerkezet

```
terraform/                       root module
  versions.tf                    Terraform és provider verziók (+ kikommentelt S3 backend)
  providers.tf                   aws és helm provider konfiguráció
  variables.tf                   a root változói (környezeti értékek alapérték nélkül)
  data.tf                        lekérdezések (ki futtatja a Terraformot)
  locals.tf                      közös értékek (a szolgáltatások nevei)
  main.tf                        a négy modul meghívása
  outputs.tf                     a scriptek által használt kimenetek
  terraform.tfvars.example       a környezeti beállítások mintája (a terraform.tfvars nincs a gitben)
  modules/vpc/                   VPC, subnetek (AZ-nként a tfvars térképéből), IGW, NAT gateway, route táblák
  modules/eks/                   IAM szerepek, security groupok (az NLB-é is), cluster, addonok,
                                 launch template, managed node group, OIDC provider, access entry
  modules/ecr/                   ECR repók
  modules/lb-controller/         IRSA szerep + hivatalos IAM policy (iam_policy.json) + Helm release
apps/service-a/                  Flask app + multi-stage Dockerfile + .dockerignore + requirements.txt
apps/service-b/                  ugyanez a B szolgáltatásnak
k8s/base/                        Namespace, Deploymentek, ClusterIP Service-ek, nginx ConfigMap,
                                 DaemonSet, NLB Service, kustomization (környezetfüggő érték nélkül)
k8s/overlays/local/              a render.sh generálja (image cím, tag, NLB SG ID); nincs a gitben
scripts/build-push.sh            mindkét image buildelése (linux/amd64) és feltöltése az ECR-be
scripts/render.sh                a helyi overlay generálása a Terraform kimenetéből
scripts/teardown.sh              lebontás a helyes sorrendben, maradékellenőrzéssel
docs/notes.md                    a projekt döntései, hibái és az 1on1 kérdések válaszai
```

## Előfeltételek

- **Eszközök:** AWS CLI (bejelentkezve: `aws sts get-caller-identity`), Terraform ≥ 1.6, kubectl, Docker buildx. A Helm CLI opcionális (a Terraform a Helm providerrel telepít), hibakereséshez hasznos. Más eszköz (pl. `jq`) nem kell.
- **Identitás:** aki a Terraformot futtatja, az lesz a cluster adminja (access entry). Ha később más AWS identitással futtatnád, az lecserélné az admint.
- **Verziók:** a kubectl legfeljebb egy alverzióval térhet el a clustertől (a cluster 1.37).
- **Régió:** `eu-west-1`.
- **Megosztott AWS fióknál:** a `cluster_name` legyen egyedi (pl. a monogramoddal), mert az IAM szerepek és policyk neve **fiókszinten** egyedi, régiótól függetlenül. A `teardown.sh` végső ellenőrzése a régió **összes** load balancerét, NAT gatewayét és clusterét listázza, így ott mások erőforrásai is megjelenhetnek.
- **Költség:** kb. 0,33 $/óra, amíg fut (részletek lent).

## Mit hoz létre a Terraform

A `plan` **54** erőforrást mutat (`54 to add, 0 to change, 0 to destroy`). Ha más szám jön ki, érdemes utánajárni (pl. egy ottfelejtett `.tf` fájl miatt).

**`vpc` modul:** VPC (`10.0.0.0/16`, DNS támogatással), AZ-nként egy publikus `/24` és egy privát `/20` subnet a tfvars `subnets` térképéből, internet gateway, egy NAT gateway (az ábécésorrend szerinti első AZ-ban) EIP-vel, egy publikus és egy privát route tábla a társításokkal. A subnetek tagjei (`kubernetes.io/role/elb`, `internal-elb`) alapján választ subnetet az LB Controller.

**`eks` modul:**

- **IAM:** cluster szerep (`AmazonEKSClusterPolicy`, az `eks.amazonaws.com` veheti fel) és node szerep (`AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`, az `ec2.amazonaws.com` veheti fel).
- **Security groupok:** a control plane kiegészítő SG-je, a node SG és az NLB SG, különálló szabály erőforrásokkal (lásd a döntéseknél).
- **Cluster:** privát és publikus API endpoint, `API` hitelesítési mód (csak access entry, `aws-auth` ConfigMap nélkül).
- **Addonok** (EKS managed, az 1.37-hez elérhető legújabb verzióval):
  - `vpc-cni`: a pod hálózat; a podok valódi VPC IP-t kapnak. A node-ok **előtt** települ, különben nem lennének Ready-k.
  - `kube-proxy`: a node-okon a Service-ek (ClusterIP, NodePort) kernel szabályait írja. A node-ok előtt települ.
  - `coredns`: a cluster DNS-e; ezzel oldja fel az nginx a `service-a.demo.svc.cluster.local` neveket. A node-ok **után** települ, mert a podjainak node kell.
- **Node group:** 3 node (min 2, max 4), `t3.medium`, **Bottlerocket** OS, a privát subnetekben, launch template-tel (saját node SG, IMDSv2, hop limit 1).
- **OIDC provider:** az IRSA alapja. A `tls` provider csak ahhoz kell, hogy az OIDC kibocsátó tanúsítványának ujjlenyomatát kiolvassa; **a forgalomhoz nincs köze**, a projektben nincs TLS/HTTPS.
- **Access entry:** a Terraformot futtató IAM identitás `AmazonEKSClusterAdminPolicy`-t kap az egész clusterre.

**`ecr` modul:** a `<cluster_name>/service-a` és `<cluster_name>/service-b` repó (pl. `szino-nginx-proxy-demo/service-a`), feltöltéskori szkenneléssel.

**`lb-controller` modul:** az AWS Load Balancer Controller IAM szerepe IRSA-val (csak a `kube-system/aws-load-balancer-controller` ServiceAccount veheti fel), a hivatalos IAM policy, és a controller telepítése **Helm**-mel (chart 3.6.2). Ez a controller hozza létre az NLB-t a Kubernetes Service alapján.

**Helm:** a Terraform Helm providere a cluster címét és tanúsítványát az `eks` modul kimenetéből kapja, a tokent pedig az `aws eks get-token` adja (`exec`), így egy hosszú `apply` közben sem jár le.

### Remote state S3-ban (opcionális, előkészítve)

A state most helyben van (`terraform/terraform.tfstate`). A `versions.tf`-ben egy kikommentelt `backend "s3"` blokk van. Bekapcsolás:

```bash
# 1. A bucketet előre, kézzel kell létrehozni (az init már keresi):
aws s3 mb s3://<egyedi-bucket-név> --region eu-west-1
aws s3api put-bucket-versioning --bucket <egyedi-bucket-név> --versioning-configuration Status=Enabled

# 2. A versions.tf-ben a backend blokk elől a komment törlése (a bucket nevét átírva),
#    majd a helyi state átköltöztetése:
terraform -chdir=terraform init -migrate-state
```

A backend blokkban nem használhatók változók. A `use_lockfile = true` az S3-ban zárol (DynamoDB már nem kell). A state bucketet a környezet lebontásakor ne töröld, csak ha a `destroy` biztosan maradéktalanul lefutott.

## Lépések

### 0. Környezeti beállítások

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars   # szükség esetén szerkeszd (cluster_name!)
```

### 1. Az image-ek helyi tesztje (ingyenes, AWS nélkül)

```bash
docker build -t service-a:local apps/service-a
docker run -d --rm --name sa-test -p 8080:8080 service-a:local
curl http://localhost:8080/api/sa       # Hello from Service A!
curl http://localhost:8080/healthz      # ok
docker logs sa-test
docker stop sa-test                     # a --rm miatt a konténer törlődik is
# ugyanígy a service-b-vel (/api/sb)
```

### 2. Infrastruktúra

```bash
cd terraform
terraform init
terraform plan -out=tfplan     # 54 to add, 0 to change, 0 to destroy
terraform apply tfplan         # ~15-20 perc, főleg az EKS
cd ..
$(terraform -chdir=terraform output -raw kubeconfig_command)
kubectl get nodes -o wide                                  # 3 node, Ready, OS-IMAGE: Bottlerocket
kubectl get deploy -n kube-system aws-load-balancer-controller
```

### 3. Image-ek az ECR-be

```bash
./scripts/build-push.sh 1.0.0
```

### 4. Overlay generálása és telepítés

```bash
./scripts/render.sh 1.0.0                # generálja a k8s/overlays/local overlay-t (ECR cím, tag, NLB SG ID)
kubectl kustomize k8s/overlays/local     # ellenőrzés: mit fog létrehozni
kubectl apply -k k8s/overlays/local
```

A `k8s/base/` a git által követett manifesteket tartalmazza, környezetfüggő érték nélkül. A `render.sh` minden futtatáskor újraírja a `k8s/overlays/local/kustomization.yaml`-t a Terraform aktuális kimenetéből, így akárhányszor futtatható (pl. egy új `apply` után új SG ID-vel). A `build-push.sh`-nak és a `render.sh`-nak ugyanazt a taget kell megadni.

### 5. Ellenőrzés és tesztelés

**Alap ellenőrzés:**

```bash
kubectl get nodes -o wide                 # 3 node, Ready, OS-IMAGE: Bottlerocket
kubectl get pods -n demo -o wide          # nginx minden node-on, A és B 2-2 replika
kubectl get svc -n demo                   # a ClusterIP-k, és az nginx-proxy NodePortja (pl. 80:31234/TCP)
kubectl get endpointslices -n demo        # a Service-ek mögött ott vannak a pod IP-k
kubectl describe svc nginx-proxy -n demo  # az Events részben a controller üzenetei (NLB létrehozása)

NLB=$(kubectl get svc nginx-proxy -n demo -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo $NLB
curl http://$NLB/api/sa     # Hello from Service A!
curl http://$NLB/api/sb     # Hello from Service B!
curl http://$NLB/           # 404, ahogy kell
```

Az NLB DNS neve és a targetek egészségessé válása 2–5 percig is eltarthat. Az `NLB` (és lent a `TG`) egy shell változó: csak abban a terminálban létezik, ahol beállítottad, egy új terminálban újra le kell futtatni.

**Az NLB targetek állapota** (minden node `healthy` legyen):

```bash
TG=$(aws elbv2 describe-target-groups --region eu-west-1 \
  --query "TargetGroups[?starts_with(TargetGroupName, 'k8s-demo')].TargetGroupArn" --output text)
aws elbv2 describe-target-health --region eu-west-1 --target-group-arn $TG \
  --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' --output table
```

**Az nginx élő konfigurációja** (amit a ConfigMapből kapott):

```bash
kubectl exec -n demo ds/nginx-proxy -- nginx -T
```

**A kliens IP megmarad** (`externalTrafficPolicy: Local`): az nginx access logjában a saját nyilvános IP-d látszik, nem egy node IP-je.

```bash
curl -s https://checkip.amazonaws.com     # a saját nyilvános IP-d
curl -s http://$NLB/api/sa > /dev/null
kubectl logs -n demo -l app=nginx-proxy --tail=5 --prefix
```

**IRSA:** az LB Controller ServiceAccountján ott a szerep ARN-je; a két controller pod közül a vezetőt a lease mutatja.

```bash
kubectl get sa aws-load-balancer-controller -n kube-system -o jsonpath='{.metadata.annotations}'
kubectl get lease -n kube-system aws-load-balancer-controller-leader
```

**A Service A független skálázása:**

```bash
kubectl scale deployment service-a --replicas=4 -n demo
kubectl get pods -n demo -l app=service-a -o wide
kubectl get endpointslices -n demo -l kubernetes.io/service-name=service-a
kubectl scale deployment service-a --replicas=2 -n demo   # vissza
```

**Egy node kiesése:** egy második terminálban folyamatosan küldj kéréseket, és közben állíts le egy node-ot. A szolgáltatás elérhető marad; néhány másodpercig előfordulhat egy-egy hiba, amíg az NLB health check kiveszi a node-ot. A managed node group új node-ot indít, és arra a DaemonSet automatikusan tesz nginx-et.

```bash
# 1. terminál: folyamatos kérések
# (egy új terminálban az NLB változó üres, ezért előbb újra be kell állítani)
NLB=$(kubectl get svc nginx-proxy -n demo -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
while true; do curl -s -o /dev/null -w "%{http_code}\n" http://$NLB/api/sa; sleep 1; done

# 2. terminál: egy node EC2 azonosítója, majd leállítása
kubectl get nodes -o jsonpath='{.items[0].spec.providerID}'      # aws:///eu-west-1a/i-0abc...
aws ec2 terminate-instances --region eu-west-1 --instance-ids <i-0abc...>
kubectl get nodes -w                                              # a node eltűnik, később új jön
kubectl get pods -n demo -o wide -w                               # a podok átkerülnek, az új node-on nginx indul
```

(Egy `kubectl drain` erre nem jó bemutató: a DaemonSet podokat nem telepíti át, így az nginx a kiürített node-on is tovább fut.)

### 6. Lebontás

```bash
./scripts/teardown.sh
```

A szkript a helyes sorrendben bont: **először** a Kubernetes erőforrásokat (`kubectl delete -k k8s/base`; így a controller törli az NLB-t, amit nem a Terraform hozott létre), megvárja, amíg az NLB eltűnik, utána `terraform destroy` (jóváhagyást kér, `yes`-t kell beírni), végül listázza a régió load balancereit, futó NAT gatewayeit és EKS clustereit. Törléshez a base elég, mert a `delete` csak a neveket nézi. Az ECR repók az image-ekkel együtt törlődnek (`force_delete`).

A helyben maradt Docker image-ek takarítása (az ECR-t nem érinti):

```bash
docker rmi service-a:local service-b:local
docker rmi $(docker images --format '{{.Repository}}:{{.Tag}}' | grep dkr.ecr)   # a buildx --push helyi példányai
docker image prune -f
docker builder prune -f
```

A kubeconfig bejegyzés a már nem létező clusterre (nem kerül pénzbe, csak rendrakás):

```bash
kubectl config get-contexts
kubectl config delete-context <a cluster kontextusának neve>
```

Ha a `terraform destroy` a VPC-nél vagy a subneteknél elakad, a szkript újra futtatható. Ha akkor sem megy, nézd meg, maradt-e hálózati interfész a VPC-ben (pl. egy load balancertől vagy a VPC CNI-től). Ehhez előbb a VPC azonosítója kell, ami a neve alapján megkereshető (a név a `cluster_name`-ből képződik):

```bash
aws ec2 describe-vpcs --region eu-west-1 \
  --filters Name=tag:Name,Values=<cluster_name>-vpc \
  --query 'Vpcs[].VpcId' --output text
```

Utána a VPC-ben maradt hálózati interfészek:

```bash
aws ec2 describe-network-interfaces --region eu-west-1 \
  --filters Name=vpc-id,Values=<vpc-id> \
  --query 'NetworkInterfaces[].[NetworkInterfaceId,Description,Status]' --output table
```

## Döntések és indoklásuk

### Infrastruktúra (Terraform)

| Döntés                                                                           | Miért                                                                                                                                                                                                    |
| -------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Saját modulok, registry modul nélkül                                             | A feladat IAM szerepeket és security groupokat kér; így mind látható és elmagyarázható.                                                                                                                  |
| Modulhívások egy `main.tf`-ben, `data.tf` és `locals.tf` külön                   | Egy helyen látszik a projekt szerkezete. A sorrend csak olvashatóság, a létrehozás sorrendjét a függőségek döntik el.                                                                                    |
| `for_each`, `count` nélkül                                                       | Stabil, név szerinti kulcsok (AZ név, repó név, policy név); egy elem törlése nem tolja el a többit.                                                                                                     |
| Környezeti értékek a tfvars-ból, modulokban sincs környezeti alapérték           | A kód és a környezet beállításai külön vannak, és semmi nem érvényesül csendben (pl. az NLB nyitottsága). Kivétel a `lb_controller_chart_version`: az `iam_policy.json`-hoz kötődik, vagyis a kód része. |
| Provider verziók: rootban `~>`, modulokban `>=`                                  | A root rögzít (és a lock fájl befagyaszt), a modul csak a minimumot jelzi; az `init` összefésüli.                                                                                                        |
| AZ-k és subnet CIDR-ek kézzel, a tfvars térképéből                               | Kiszámítható: nem függ egy AWS lista sorrendjétől (data source + index), így nem cserélődhetnek a subnetek váratlanul. Régióváltáskor a tfvars-ban kell átírni.                                          |
| Privát `/20`, publikus `/24` subnetek                                            | A VPC CNI miatt a podok is a privát subnetből kapnak IP-t; a publikusban csak az NLB és a NAT van.                                                                                                       |
| `map_public_ip_on_launch = false`                                                | A publikus subnetekben nincs olyan gép, aminek automatikus publikus IP kellene.                                                                                                                          |
| Egy NAT gateway                                                                  | Gyakorláshoz olcsóbb; élesben AZ-nként egy kellene (a modulban kommentben leírva, `for_each`-csel).                                                                                                      |
| Különálló SG szabály erőforrások                                                 | Inline szabályoknál a Terraform törölné a controller által felvett szabályokat.                                                                                                                          |
| SG szabályok security group hivatkozással (nem CIDR-rel)                         | Identitás alapú: bárki, akin az adott SG van, IP-től függetlenül; szűkebb és rugalmasabb.                                                                                                                |
| Node SG: önmagára hivatkozó szabály                                              | Node-node és pod-pod forgalom (a podok a node ENI-jein kapnak IP-t).                                                                                                                                     |
| Node SG: 443, 10250, 9443 a control plane-ből                                    | Webhookok, kubelet API (`kubectl logs/exec`), az LB Controller webhookja.                                                                                                                                |
| Node SG: NodePort tartomány az NLB SG-ből                                        | Az NLB forgalma és a health check is a NodePortra érkezik (az SG a DNAT előtt vizsgál).                                                                                                                  |
| Launch template a node groupnál                                                  | Enélkül az EKS a saját cluster SG-jét tenné a node-okra. AMI-t nem adunk meg, azt az EKS választja és frissíti az `ami_type` alapján.                                                                    |
| IMDSv2, hop limit 1                                                              | A normál podok nem érik el a node szerep kulcsait; minden pod saját szerepet kap (IRSA) vagy semmit.                                                                                                     |
| Bottlerocket                                                                     | Minimális, csak olvasható rendszerfájlokkal futó OS, kisebb támadási felület. AL2023-ra a tfvars egy sorával vissza lehet állni.                                                                         |
| Node group `max_unavailable = 1`                                                 | Frissítéskor egyszerre egy régi node ürül ki; az EKS előbb új node-okat indít.                                                                                                                           |
| Addon sorrend, `OVERWRITE`                                                       | A CNI a node-ok előtt, a CoreDNS utánuk; az `OVERWRITE` miatt a managed addon átveszi az EKS által induláskor telepített változatot.                                                                     |
| Access entry `API` módban, `bootstrap_cluster_creator_admin_permissions = false` | A hozzáférés kizárólag a kódban van leírva (az automatikus admin bejegyzés ütközne a miénkkel, és nem lenne a state-ben).                                                                                |
| `depends_on` a policy csatolásokra (cluster, node group, controller)             | A szerepre hivatkozás nem garantálja, hogy a policy már rajta van; törléskor pedig a policyk csak az erőforrás után kerüljenek le.                                                                       |
| IRSA az LB Controllernek                                                         | Csak a controller ServiceAccountja kap ELB jogokat. A hivatalos policy tag alapú feltételekkel csak a saját erőforrásait engedi módosítani.                                                              |
| Helm provider 3.x, `exec` alapú token                                            | A `kubernetes`, `exec`, `set` attribútum; az `exec` szükség szerint új tokent kér.                                                                                                                       |
| LB Controller 3.6.2                                                              | A 3.x óta a chart és a controller verziója egyezik; a policy JSON ehhez a verzióhoz tartozik.                                                                                                            |
| Kubernetes 1.37                                                                  | Standard támogatásban van (az extended support óradíja hatszoros), és illik a kubectl verziójához.                                                                                                       |
| `t3.medium`                                                                      | A pod limit az ENI-k számától függ: `t2.micro`/`t3.micro` 4, `t3.small` 11, `t3.medium` 17 pod/node.                                                                                                     |
| ECR: `MUTABLE`, `force_delete` a tfvars-ból; a modul alapértéke `false`          | Gyakorláshoz felülírható tag és törölhető repó; élesben `IMMUTABLE` és `false`. A modul biztonságos alapértelmezésű.                                                                                     |
| ECR repó nevek `<cluster_name>/<szolgáltatás>` formában                          | Az ECR nevek fiókon belül régiónként egyediek; az előtag miatt több projekt vagy ember sem ütközik, és a konzolban egy „mappába” kerülnek.                                                               |
| Egy state                                                                        | Kicsi projekt, egy kezelő, egyszerre jön létre és bomlik le minden.                                                                                                                                      |

### Kubernetes és alkalmazások

| Döntés                                                                   | Miért                                                                                                                                                      |
| ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| nginx DaemonSet                                                          | A feladat kéri; minden node-on fut egy proxy, bármelyik node kieshet, és a `Local` policyval egyenletes az elosztás.                                       |
| Kustomize base + generált overlay                                        | A base-ben nincs környezetfüggő érték; az image címet, a taget és az NLB SG ID-t (minden `apply` után új) a `render.sh` írja egy gitignore-olt overlay-be. |
| A Service neve, `selector`-a és `targetPort`-ja                          | A név az nginx konfiguráció DNS nevéhez, a selector a pod template labeljeihez, a `targetPort` a konténer portjához köt.                                   |
| `aws-load-balancer-type: external` + `scheme: internet-facing`           | Az LB Controller kezelje, és publikus NLB legyen (alapból belső lenne).                                                                                    |
| `target-type: instance` + `externalTrafficPolicy: Local`                 | Nincs extra ugrás és SNAT, megmarad a kliens IP, és csak az egészséges nginx-et futtató node-ok kapnak forgalmat.                                          |
| Saját NLB SG + `manage-backend-security-group-rules`                     | A feladat kéri; a controller a node SG-be is felveszi a szabályt (a Terraformos szabály mellett).                                                          |
| ConfigMap mappaként csatolva (`/etc/nginx/conf.d`)                       | A kubelet a ConfigMap változását a fájlba is átviszi (a `subPath` nem); az nginx-et így is újra kell indítani.                                             |
| `proxy_pass` perjel nélkül                                               | A teljes útvonal (`/api/sa`) továbbmegy, a Flask erre figyel.                                                                                              |
| `X-Forwarded-For`, `X-Real-IP`, `Host`                                   | Az nginx és az app közötti kapcsolatban már az nginx a feladó; az eredeti adatok ezekből derülnek ki.                                                      |
| nginx: `nginx-unprivileged`, 8080, `runAsNonRoot`, readiness + liveness  | Nem rootként fut; a readiness a forgalmat, a liveness az újraindítást szabályozza.                                                                         |
| nginx DaemonSet `maxSurge: 1`, `maxUnavailable: 0`                       | Frissítéskor az új pod a régi leállítása előtt indul, így nincs kiesés egyik node-on sem.                                                                  |
| Appok: `runAsNonRoot`, Dockerfile-ban `USER 10001`                       | Számmal kell megadni, mert névből a kubelet nem tudja ellenőrizni, hogy nem root.                                                                          |
| Memória limit, CPU limit nélkül                                          | A memória limit védi a node-ot (OOMKill); CPU limit nélkül nincs felesleges throttling.                                                                    |
| gunicorn, exec formájú `CMD`                                             | Élesre alkalmas szerver; PID 1-ként megkapja a `SIGTERM`-et.                                                                                               |
| Multi-stage Dockerfile, venv a `/opt/venv`-ben                           | A futtatott image-be csak a kész függőségek kerülnek; az útvonal mindkét szakaszban azonos (abszolút shebangek).                                           |
| Rögzített függőségek (`flask==3.1.3`, `gunicorn==26.2.0`)                | Minden build ugyanazokat a verziókat telepíti.                                                                                                             |
| `buildx --platform linux/amd64`                                          | ARM gépen buildelt image nem futna az x86 node-okon.                                                                                                       |
| A scriptek csak bash, AWS CLI, Terraform és Docker eszközöket használnak | Nincs plusz telepítendő függőség (pl. `jq`).                                                                                                               |

## Ha valami nem működik

| Tünet                                                                    | Valószínű ok                                                                                                                              | Ellenőrzés / megoldás                                                                                                                     |
| ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| A `plan` erőforrásszáma eltér az 54-től                                  | Egy ottfelejtett vagy duplikált `.tf` fájl                                                                                                | `ls terraform/`, `grep` a gyanús erőforrásnévre                                                                                           |
| A szerkesztő hibát jelez, a `validate` nem                               | A szerkesztő Terraform kiegészítője elavult állapotot lát                                                                                 | VS Code: „Developer: Reload Window”; a `validate` és a `plan` a mérvadó                                                                   |
| `Unexpected block: Blocks of type "set"/"kubernetes"`                    | Helm provider 3.x, régi blokk szintaxis                                                                                                   | `kubernetes = { ... }`, `set = [ ... ]`; `terraform init -upgrade`                                                                        |
| `No declaration found for "var.X"` / `Unexpected attribute` a tfvars-ban | Hiányzik a `variable "X"` blokk                                                                                                           | Deklaráld a változót a root `variables.tf`-ben                                                                                            |
| `no addon version found` a plan-nél                                      | Az addon nem érhető el a választott Kubernetes verzióhoz                                                                                  | Eggyel régebbi verzió (`aws eks describe-cluster-versions`)                                                                               |
| A node group létrehozása elhasal Bottlerocket mellett                    | A Bottlerocket nem érhető el a választott Kubernetes verzióhoz                                                                            | `node_ami_type = "AL2023_x86_64_STANDARD"` a tfvars-ban                                                                                   |
| `kubectl`: `Unauthorized` vagy ismeretlen kontextus                      | Más AWS identitás, vagy a kubectl egy régi clusterre mutat                                                                                | `aws sts get-caller-identity`, `kubectl config current-context`, a `kubeconfig_command` újrafuttatása                                     |
| Podok `Pending`, pedig van szabad CPU és memória                         | Elfogyott a node pod limitje (ENI alapú)                                                                                                  | `kubectl describe pod`, nagyobb instance típus                                                                                            |
| Pod `CreateContainerConfigError`: „non-numeric user”                     | `runAsNonRoot: true`, de az image névvel adja meg a felhasználót                                                                          | Számmal: `USER 10001` (vagy `runAsUser` a podon)                                                                                          |
| App podok `ImagePullBackOff`                                             | Rossz ECR cím vagy tag, nem futott a `render.sh`, vagy eltér a build-push és a render tagje                                               | `kubectl describe pod`, `kubectl kustomize k8s/overlays/local \| grep image`                                                              |
| App pod `CrashLoopBackOff`, `exec format error`                          | ARM image x86 node-on                                                                                                                     | Buildeld újra `--platform linux/amd64`-gyel                                                                                               |
| nginx pod: „host not found in upstream”                                  | A Service-ek még nem léteztek az nginx indulásakor, vagy eltér a Service neve                                                             | `kubectl get svc -n demo`, majd `kubectl rollout restart ds/nginx-proxy -n demo`                                                          |
| `EXTERNAL-IP` sokáig `<pending>`                                         | A controller nem fut vagy nincs joga, hiányzik a subnet tag, régi SG ID van az overlayben, vagy a 3.x controller nem ismer egy annotációt | `kubectl describe svc nginx-proxy -n demo`, `kubectl logs -n kube-system deploy/aws-load-balancer-controller`, `./scripts/render.sh` újra |
| Az NLB létrejött, de nem válaszol                                        | Belső NLB lett, hiányzik egy SG szabály, vagy a targetek unhealthy                                                                        | EC2 konzol → Target Groups → Health                                                                                                       |
| `/api/sa` 404                                                            | `proxy_pass` perjellel a végén levágja az útvonalat                                                                                       | `kubectl get cm nginx-proxy-conf -n demo -o yaml`                                                                                         |
| `/api/sa` 502                                                            | Nincs ready pod, nem egyezik a `selector`, vagy rossz a `targetPort`                                                                      | `kubectl get endpointslices -n demo`, `kubectl logs -n demo ds/nginx-proxy`                                                               |
| ConfigMap módosítás után nincs változás                                  | Az nginx nem tölti újra magától                                                                                                           | `kubectl rollout restart ds/nginx-proxy -n demo`                                                                                          |
| `terraform destroy` elakad a VPC-n                                       | Az NLB még létezik (a controller hozta létre)                                                                                             | `./scripts/teardown.sh`, vagy előbb `kubectl delete -k k8s/base`                                                                          |
| `git rm`: „local modifications”                                          | A fájl módosult a legutóbbi commit óta                                                                                                    | Ha a tartalma máshol megvan: `git rm -f`                                                                                                  |

## Költség

| Tétel               | Kb. óradíj (eu-west-1) |
| ------------------- | ---------------------- |
| EKS control plane   | 0,10 $                 |
| 3 × t3.medium       | 0,14 $                 |
| NAT gateway         | 0,05 $ + adatforgalom  |
| NLB                 | 0,02–0,03 $            |
| Publikus IPv4 címek | 0,01–0,02 $            |
| **Összesen**        | **kb. 0,33 $/óra**     |

Egy próbakör a létrehozással és a lebontással együtt kb. 1,5–2 óra futásidő, nagyjából 0,5–0,7 $. A legnagyobb kockázat egy bent maradt erőforrás (pl. az NLB vagy a NAT gateway), ezért a `teardown.sh` a végén ellenőriz.

## Továbbfejlesztési ötletek

- **EKS Pod Identity** az IRSA helyett: nem kell OIDC provider (és vele a `tls` provider), egyszerűbb trust policy, egy `eks-pod-identity-agent` addon és egy `aws_eks_pod_identity_association`.
- **Gateway API** az nginx ConfigMap és DaemonSet helyett (pl. NGINX Gateway Fabric vagy az LB Controller Gateway API támogatása): szabványos, szerep alapú (GatewayClass, Gateway, HTTPRoute). Az ingress-nginx controllert a Kubernetes projekt kivezette.
- **Karpenter** a node-ok dinamikus kezelésére; a lebontásnál a Karpenter által indított node-okat a `terraform destroy` előtt kell eltávolítani.
- **HPA és metrics-server** a Service A független, terhelés alapú skálázásához.
- **A state kettébontása** `infra` és `platform` rétegre: a Helm provider egy már létező cluster adataiból konfigurálódna.
- **Remote state S3-ban:** a `versions.tf`-ben előkészítve (lásd fent).
- **Architektúra ellenőrzés precondition-nel:** az `aws_ec2_instance_type` data source-szal ellenőrizni, hogy az AMI típus és az instance típus architektúrája egyezik.
- **HTTPS:** ACM tanúsítvány az NLB-n (TLS listener), ehhez saját domain kell.
- `target-type: ip`: az NLB közvetlenül az nginx podokra küld (a NodePort ugrás kimarad).
- Ha `externalTrafficPolicy: Cluster` kellene, a kliens IP **Proxy Protocol v2**-vel őrizhető meg.
- **ProxyFix** a Flaskben, ha az appnak kellene a valódi kliens IP.
- **ECR:** lifecycle policy a régi image-ek törlésére, regiszter szintű (Inspector) szkennelés, `IMMUTABLE` tagek a git commit azonosítójával.
- **`ecr_registry` output**, hogy a scriptek `jq` nélkül, a Terraformból kapják a regiszter címét.
- `preStop` hook és `terminationGracePeriodSeconds` az nginx-re, a frissítés közbeni 502-k ellen.
- **Pod Security Admission** labelek a `demo` namespace-en (`pod-security.kubernetes.io/enforce: restricted`).
- **CI/CD:** GitHub Actions a build-push és a telepítés automatizálására, környezetenkénti, commitolt overlayekkel, vagy Argo CD GitOps-hoz.
