# Jegyzetek a projekthez

Ez a fájl a projekt és a feladat jegyzete: hogyan teljesíti a feladatot, milyen hibákba futottunk és hogyan javítottuk őket, és válaszok az 1on1 kérdéseire. A telepítés lépései, a teljes döntési táblázat és a hibaelhárítás a `README.md`-ben vannak.

## 1. A feladat kritériumai és a megoldás

| #   | Kritérium                                               | Hol teljesül                                                 |
| --- | ------------------------------------------------------- | ------------------------------------------------------------ |
| 1.1 | A VPC és az EKS cluster Terraformmal készül             | `terraform/modules/vpc`, `terraform/modules/eks`             |
| 1.2 | ECR repók mindkét image-nek                             | `terraform/modules/ecr` (`for_each` a szolgáltatások nevén)  |
| 1.3 | Az image-ek buildelve és feltöltve az ECR-be            | `scripts/build-push.sh`                                      |
| 1.4 | Deployment és ClusterIP Service mindkét szolgáltatásnak | `k8s/base/service-a.yaml`, `k8s/base/service-b.yaml`         |
| 1.5 | nginx ConfigMap path alapú routinggal                   | `k8s/base/nginx-configmap.yaml`                              |
| 1.6 | nginx DaemonSet minden node-on                          | `k8s/base/nginx-daemonset.yaml`                              |
| 1.7 | Az nginx publikus NLB-n keresztül érhető el             | `k8s/base/nginx-service.yaml` + AWS Load Balancer Controller |
| 1.8 | `/api/sa` a Service A-tól válaszol                      | `curl http://<NLB>/api/sa`                                   |
| 1.9 | `/api/sb` a Service B-től válaszol                      | `curl http://<NLB>/api/sb`                                   |

A feladat táblázatának további pontjai: **security groupok** a clusternek és az NLB-nek (`modules/eks/security-groups.tf`), **IAM szerepek** a clusternek és a node-oknak (`modules/eks/iam.tf`), **managed node group** (`modules/eks/node-group.tf`).

## 2. Ahol tudatosan eltértünk a referencia megoldástól

- **Saját modulok** a registry modulok (`terraform-aws-modules/vpc`, `eks`, `iam`) helyett, hogy az IAM szerepek és a security groupok láthatók és elmagyarázhatók legyenek.
- **Régió:** `eu-west-1` az `eu-central-1` helyett.
- **`for_each`** mindenhol, `count` nélkül.
- **Környezeti értékek a tfvars-ból**, alapértékek nélkül, a modulokban is.
- **AZ-k kézzel** a tfvars `subnets` térképében, nem `data "aws_availability_zones"` + `cidrsubnet()`-tel (a mentor javaslata): kiszámítható, nem függ egy lista sorrendjétől.
- **Kustomize base + generált overlay** a `sed`-del kitöltött helyőrzők helyett.
- **Bottlerocket** OS az Amazon Linux 2023 helyett.
- **IMDS hop limit 1**, hogy a podok ne érjék el a node szerepet.
- **Kubernetes 1.37** (a referencia 1.33-at használt, ami már extended supportban volt).
- **Helm provider 3.x** szintaxis, **LB Controller 3.6.2**.
- **nginx DaemonSet:** liveness probe, `runAsNonRoot`, `maxSurge`.
- **Frissített függőségek:** Flask 3.1.3, gunicorn 26.2.0.

## 3. Hibák és javításuk

| #   | Mi történt                                                                                | Ok                                                                                                                                                                                       | Megoldás, tanulság                                                                                                |
| --- | ----------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| 1   | `Unexpected block: Blocks of type "set"` és `"kubernetes"` a Helm providernél             | A Helm provider 3.x-ben ezek attribútumok, nem blokkok                                                                                                                                   | `kubernetes = { exec = { ... } }`, `set = [ { ... } ]`; `terraform init -upgrade`. Verziót mindig rögzíteni kell. |
| 2   | `kubernetes_version = "1.33"` a referenciában                                             | Időközben extended supportba került (kb. hatszoros óradíj), és a kubectl 1.37 csak ±1 alverziót támogat                                                                                  | `aws eks describe-cluster-versions` → 1.37                                                                        |
| 3   | Az LB Controller chart `1.13.0` és a „chart 1.N = controller 2.N” szabály                 | Elavult tudás; a 3.x óta a chart és a controller verziója egyezik                                                                                                                        | `helm search repo ... --versions` → 3.6.2; `helm show values` a kulcsokra; `curl -f` a policy JSON-ra             |
| 4   | `No declaration found for "var.node_desired_size"` és `Unexpected attribute` a tfvars-ban | A root `variables.tf`-ből hiányzott a deklaráció                                                                                                                                         | A `variable` blokk deklarál, a tfvars értéket ad, a modulhívás felhasznál                                         |
| 5   | `USER appuser` a Dockerfile-ban + `runAsNonRoot: true` a Deploymentben                    | A kubelet névből nem tudja ellenőrizni, hogy a felhasználó nem root, a pod `CreateContainerConfigError`-ral el sem indult volna                                                          | `USER 10001`. A két fájl külön-külön helyes volt, csak együtt nem működött.                                       |
| 6   | A `render.sh` `sed`-del a git által követett fájlokat írta át                             | A második futtatásnál nem talált helyőrzőt; az NLB SG ID minden `apply` után új, így a régi, törölt SG ID maradt volna az 1on1 előtti telepítésnél; a valódi értékek a gitbe kerülhettek | Kustomize base + a `render.sh` által generált, gitignore-olt overlay (`images` + patch)                           |
| 7   | A `teardown.sh` először a `k8s/overlays/local`-t törölte                                  | Ha az overlay nem létezik (friss klón), a `set -e` miatt az egész lebontás leállt volna                                                                                                  | Törléshez a `k8s/base` elég (a `delete` csak a neveket nézi)                                                      |
| 8   | A `.gitignore`-ban összeolvadt két sor (`.envk8s/overlays/`)                              | Az `echo >>` a sortörés nélküli utolsó sorhoz fűzött                                                                                                                                     | Kézi javítás; `>>` előtt ellenőrizni a fájl végét                                                                 |
| 9   | A `terraform.tfvars` bekerült a gitbe                                                     | A `.gitignore`-ból hiányzott a `*.tfvars` sor                                                                                                                                            | `git rm --cached`; a `.gitignore`-t az első commit előtt kell rendbe tenni (az előzményekben megmarad)            |
| 10  | A `plan` 55 erőforrást mutatott a várt 54 helyett                                         | Egy ottfelejtett régi `security.tf` egy második, senki által nem használt NLB security groupot hozott létre                                                                              | Törlés; a `plan` erőforrásszámát mindig össze kell vetni a várttal                                                |
| 11  | `git rm`: „the following files have local modifications”                                  | A fájlok tartalmát előbb kitöröltem, mint a `git rm`-et futtattam                                                                                                                        | `git rm -f`, mert a tartalom máshol megvolt                                                                       |
| 12  | A fájlok `777` joggal, a gitben futtathatóként                                            | A zip-ből kibontott referencia megoldás                                                                                                                                                  | Mappák `755`, fájlok `644`, scriptek `755` (a `.terraform/` kihagyásával)                                         |
| 13  | `map_public_ip_on_launch = true` a publikus subneteken                                    | A régi projektben a bastion miatt kellett, itt semmi nem igényli                                                                                                                         | `false`                                                                                                           |
| 14  | A modulokban környezeti alapértékek (pl. `nlb_ingress_cidrs = ["0.0.0.0/0"]`)             | Az NLB nyitottsága csendben, a tfvars-ban nem látszóan érvényesült                                                                                                                       | Az alapértékek kikerültek, minden a tfvars-ból jön                                                                |
| 15  | IMDS hop limit 2                                                                          | A podok elérték volna a node szerep kulcsait                                                                                                                                             | Hop limit 1; az LB Controller IRSA-t használ, a régiót és a VPC-t a Helm értékekben kapja                         |
| 16  | AZ-k data source-ból, a CIDR-ek a lista sorszámából                                       | Ha a lista sorrendje változik, a subnetek lecserélődnének                                                                                                                                | Kézi `subnets` térkép a tfvars-ban                                                                                |
| 17  | A szerkesztő hibát jelzett (`Required attribute "azs"`), a `validate` nem                 | A Terraform kiegészítő elavult állapotot látott                                                                                                                                          | „Reload Window”; a parancssor a mérvadó                                                                           |
| 18  | A kubectl egy régi, nem létező clusterre mutatott                                         | Egy korábbi gyakorlás kontextusa maradt a kubeconfigban                                                                                                                                  | `kubectl config get-contexts`, `unset current-context`                                                            |
| 19  | Egy összecsúszott terminál log alapján hibásnak tűnt az `oidc.tf`                         | A log olvashatatlan volt, a fájl helyes                                                                                                                                                  | Mindig a tényleges fájlt nézni (`cat`, `git diff`)                                                                |
| 20  | Elavult kommentek (`k8s/nginx-service.yaml`, „a render.sh tölti ki”)                      | A `k8s/` átszervezése előttről maradtak                                                                                                                                                  | Javítva; átszervezés után a kommenteket is át kell nézni                                                          |

A próbakör (telepítés és teszt) hibái ide kerülnek.

## 4. Válaszok az 1on1 témáira

Az 1on1 beszélgetés: a megoldásnak futnia kell AWS-en, és meg kell tudni mutatni, hogy a `/api/sa` és a `/api/sb` jó választ ad. Minden fájlt soronként el kell tudni magyarázni, és a döntéseknél az alternatívákat is.

### A futó telepítés

_Mutasd meg, hogy a megoldás telepítve van és elérhető; hogy a `/api/sa` és a `/api/sb` a várt választ adja._

```bash
kubectl get nodes -o wide
kubectl get pods -n demo -o wide          # nginx mind a 3 node-on, A és B 2-2 pod
kubectl get svc nginx-proxy -n demo       # EXTERNAL-IP = az NLB DNS neve
curl http://$NLB/api/sa                   # Hello from Service A!
curl http://$NLB/api/sb                   # Hello from Service B!
curl http://$NLB/                         # 404
```

A telepítés: `terraform apply` → `build-push.sh` → `render.sh` → `kubectl apply -k k8s/overlays/local`. A lebontás: `teardown.sh`.

### Architektúra döntések

_Miért éppen ezt a felépítést választottad? Milyen alternatívákat mérlegeltél?_

A kérés útja: NLB (L4) → a node NodePortja → a kernel a helyi nginx podra irányítja → az nginx (L7) útvonal alapján a Service A vagy B ClusterIP-jére küld → egy ready podra bármelyik node-on.

- **DaemonSet + `externalTrafficPolicy: Local` + `target-type: instance`:** minden node-on van nginx, ezért minden node egészséges target, nincs extra ugrás node-ok között, nincs SNAT, megmarad a kliens IP, és egy node kiesése nem érinti a többit. Alternatíva: **Deployment** (a replikák száma a terheléshez igazítható HPA-val, de `Local` policy mellett egyenetlen az elosztás, `Cluster` policy mellett pedig extra ugrás és SNAT jön), vagy **`target-type: ip`** (az NLB közvetlenül a podokra küld).
- **Ingress controller vagy Gateway API** a kézzel írt nginx helyett: élesben ezt választanám, mert a konfigurációt a controller generálja; a feladat viszont kifejezetten DaemonSetet és ConfigMapet kért. Az ingress-nginx-et kivezették, ma a Gateway API az irány.
- **Saját Terraform modulok** a registry modulok helyett, hogy az IAM és a security groupok láthatók legyenek.
- **Managed node group:** a feladat ezt kérte. A **Fargate** nem működne, mert nem támogatja a DaemonSetet. Az **EKS Auto Mode** sok mindent automatizálna (LB Controller, addonok, node-ok), de kevesebb rálátást adna.
- **Egy NAT gateway** gyakorláshoz; élesben AZ-nként egy.

### A Terraform felépítése

_Hogyan hoztad létre a VPC-t, az EKS clustert és az ECR repókat? Milyen IAM szerepeket és security groupokat állítottál be?_

- **Szerkezet:** root module (változók a tfvars-ból, a négy modul hívása a `main.tf`-ben) + `vpc`, `eks`, `ecr`, `lb-controller` modul. A root rögzíti a provider verziókat (`~>`), a modulok a minimumot (`>=`). 54 erőforrás.
- **VPC:** 3 AZ, AZ-nként egy privát `/20` (node-ok és podok, a VPC CNI miatt nagy) és egy publikus `/24` (NLB, NAT), kézzel megadva a tfvars-ban; internet gateway, egy NAT gateway, route táblák. A subnetek tagjeiből tudja az LB Controller, hová tegye az NLB-t.
- **EKS:** 1.37, privát és publikus endpoint, `API` hitelesítés access entryvel; addonok: vpc-cni és kube-proxy a node-ok előtt, coredns utánuk; managed node group (3 × `t3.medium`, Bottlerocket) launch template-tel.
- **ECR:** két repó `for_each`-csel, feltöltéskori szkenneléssel.
- **IAM szerepek:** mindegyiknek van egy **trust policyja** (ki veheti fel) és **jogosultság policyjai** (mit tehet):
  - **cluster szerep:** az `eks.amazonaws.com` veheti fel, `AmazonEKSClusterPolicy` (ENI-k kezelése a VPC-ben);
  - **node szerep:** az `ec2.amazonaws.com` veheti fel, `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly` (ez utóbbi az ECR-ből való letöltéshez);
  - **LB Controller szerep (IRSA):** csak a `kube-system/aws-load-balancer-controller` ServiceAccount veheti fel, egy OIDC tokennel; a hivatalos policy tag alapú feltételekkel csak a saját erőforrásait engedi módosítani;
  - **access entry:** a Terraformot futtató IAM user `AmazonEKSClusterAdminPolicy`-t kap a clusterre.
- **Security groupok** (különálló szabályokkal, egymásra hivatkozva, nem CIDR-rel):
  - **cluster SG:** a node-ok elérhetik a 443-as API portot;
  - **node SG:** önmagától mindent (node-node, pod-pod), a control plane-től 443, 10250 (kubelet), 9443 (LB Controller webhook), az NLB SG-től a NodePort tartományt;
  - **NLB SG:** be a 80-as port a tfvars tartományaiból, ki csak a node SG NodePort tartománya felé.

### ECR és konténer image-ek

_Hogyan buildelted és töltötted fel az image-eket az ECR-be? Milyen problémákba ütköztél?_

- **Dockerfile:** multi-stage (a builder szakasz egy venv-be telepíti a függőségeket, a runtime csak a kész venv-et és az `app.py`-t kapja), nem root felhasználó (`USER 10001`), gunicorn exec formában.
- **`build-push.sh`:** a régiót a Terraform kimenetéből, a fiókszámot az `aws sts`-ből veszi; az `aws ecr get-login-password | docker login --password-stdin` egy 12 órás tokennel jelentkezik be (a jelszó nem kerül az előzményekbe); a `docker buildx build --platform linux/amd64 --push` buildel és feltölt. Előtte helyben teszteltük az image-eket (`docker run` + `curl`).
- **Problémák:** a `USER appuser` + `runAsNonRoot` (a pod el sem indult volna, javítva `USER 10001`-re); a függőségek elavultak voltak (frissítve, és helyben tesztelve); a `MUTABLE` tag miatt ugyanaz a tag felülírható, élesben `IMMUTABLE` és git commit alapú tag kellene.

### Kubernetes manifestek

_Magyarázd el a Deploymenteket, a Service-eket, a ConfigMapet, a DaemonSetet és a LoadBalancer Service-t. Miért így építetted fel őket?_

- **Deploymentek** (A és B): 2-2 replika, `runAsNonRoot`, readiness és liveness probe a `/healthz`-en, memória request és limit, CPU request (CPU limit nélkül). A három label szint: a Deployment saját labelje, a `selector.matchLabels`, és a pod template labelje (ez utóbbival párosul a Service).
- **ClusterIP Service-ek:** `port: 80` → `targetPort: 8080`. A nevük adja a DNS nevet, amit az nginx használ; a `selector` a pod labelekre illik; az EndpointSlice-ok tartják nyilván a ready pod IP-ket.
- **ConfigMap:** a `default.conf` kulcsból fájl lesz a `/etc/nginx/conf.d`-ben.
- **DaemonSet:** node-onként egy nginx (`nginx-unprivileged`, 8080), readiness és liveness, `runAsNonRoot`, `maxSurge: 1` / `maxUnavailable: 0` frissítéskor.
- **LoadBalancer Service:** az LB Controller ebből hoz létre NLB-t; `externalTrafficPolicy: Local`; az API server automatikusan NodePortot és `healthCheckNodePort`-ot oszt neki.
- **Kustomize:** a `k8s/base` környezetfüggetlen; a `render.sh` által generált overlay adja az ECR címet, a taget és az NLB SG ID-t, mert az SG ID minden `apply` után új.

### Az nginx konfiguráció

_Hogyan működik a ConfigMap? Hogyan irányítja az nginx a forgalmat a megfelelő Service-hez?_

- A ConfigMap a DaemonSetben volume-ként a `/etc/nginx/conf.d` mappára van csatolva; a `default.conf` kulcsból fájl lesz, amit az nginx fő konfigurációja automatikusan betölt (és lecseréli az image gyári `default.conf`-ját). Mappa csatolásnál a kubelet a ConfigMap változását átviszi a fájlba (a `subPath`-nál nem), de az nginx-et újra kell indítani (`kubectl rollout restart`).
- A `location` blokkok az útvonalak: `= /healthz` pontos egyezés, saját `200 ok` válasszal (probe-ok és NLB health check); `/api/sa` és `/api/sb` előtag egyezés (a leghosszabb illeszkedő nyer); `/` a 404.
- A `proxy_pass http://service-a.demo.svc.cluster.local;` perjel nélkül a teljes útvonalat továbbadja (perjellel a `/api/sa` levágódna, és a Flask 404-et adna); port nélkül a 80-ra megy, ezért hallgat a Service a 80-on.
- **Service discovery:** a nevet a CoreDNS a Service ClusterIP-jére fordítja (a név: `<service>.<namespace>.svc.cluster.local`), a ClusterIP-t a kube-proxy egy ready pod IP-jére. Az nginx a neveket induláskor oldja fel, ezért a Service-eknek előbb kell létezniük.
- A `Host`, `X-Real-IP` és `X-Forwarded-For` fejlécek az eredeti kérés adatait adják át, mert az nginx és az app közötti kapcsolatban már az nginx a feladó.

### Elérés az internetről

_Hogyan juttatja el az NLB a forgalmat az nginx DaemonSethez? Milyen annotációkat használtál?_

Az NLB a node-ok NodePortjára küld (`instance` target); a node security groupja a NodePort tartományt az NLB SG-ből engedi (a DNAT előtt a célport még a NodePort); a kernel a `Local` policy miatt a helyi nginx podra irányít. Az NLB health checkje a `healthCheckNodePort`-on azt kérdezi, van-e a node-on ready nginx; ha nincs, kiveszi a node-ot.

Annotációk:

- `service.beta.kubernetes.io/aws-load-balancer-type: "external"`: az AWS Load Balancer Controller kezelje (a Service-ből mindig NLB lesz; ALB Ingressből vagy Gateway API-ból jönne).
- `service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"`: publikus legyen (alapból belső).
- `service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "instance"`: a node-ok NodePortjára küldjön.
- `service.beta.kubernetes.io/aws-load-balancer-security-groups: <SG ID>`: a saját NLB security group (az overlay patch-e írja be).
- `service.beta.kubernetes.io/aws-load-balancer-manage-backend-security-group-rules: "true"`: a controller a node SG-be is vegye fel a szükséges szabályt.

### Hibakeresés

_Milyen problémákba ütköztél a telepítés során? Hogyan oldottad meg őket?_

A teljes lista a 3. fejezetben van. A legfontosabbak: a Helm provider 3.x szintaxisa, a `USER appuser` és a `runAsNonRoot` ütközése, a `render.sh` megismételhetetlensége (és ezzel a régi SG ID problémája), az ottfelejtett `security.tf` (55 helyett 54 erőforrás), a modulok csendes alapértékei és az IMDS hop limit.

A módszer: `kubectl get` / `describe` / `logs`, az EndpointSlice-ok, a controller logja, a `plan` erőforrásszámának ellenőrzése, és mindig a tényleges fájl, nem egy log vagy összefoglaló.

## 5. Válaszok a példakérdésekre

**Vezess végig az architektúrádon.**
Egy publikus NLB a 80-as porton fogad, és a három node NodePortjára küld (`instance` target). A node-on a kernel a helyi nginx podra irányít (`externalTrafficPolicy: Local`). Az nginx DaemonSet minden node-on fut, a konfigurációja ConfigMapből jön, és útvonal alapján a `service-a` vagy `service-b` ClusterIP Service-re küld, amit a CoreDNS old fel; onnan egy ready podra kerül, bármelyik node-on. Az egészet Terraform hozza létre saját modulokból (VPC, EKS, ECR, LB Controller Helmmel és IRSA-val), az image-ek az ECR-ben vannak, a manifesteket Kustomize állítja össze.

**Miért DaemonSetet használtál az nginx-hez Deployment helyett?**
A feladat kérte, és ezzel minden node-on van proxy: a `Local` policyval minden node egészséges target, nincs extra ugrás és SNAT, megmarad a kliens IP, és ha egy node kiesik, a többi végig kiszolgál; új node-on automatikusan elindul. A hátránya, hogy a podok száma a node-okhoz kötött, nem a terheléshez. Egy nagy clusterben Deploymentet használnék HPA-val és `topologySpreadConstraints`-szel, vagy ingress controllert / Gateway API-t.

**Honnan tudja az nginx, hová irányítsa a forgalmat?**
A ConfigMapből, ami a `/etc/nginx/conf.d/default.conf` fájlként kerül a podba. A `location /api/sa` és `/api/sb` blokkok az útvonalak, a `proxy_pass` a Service DNS nevére küld (`service-a.demo.svc.cluster.local`). A nevet a CoreDNS a Service ClusterIP-jére fordítja, a ClusterIP-t a kube-proxy egy ready pod IP-jére, amit a Service `selector`-a és az EndpointSlice-ok határoznak meg.

**Hogyan tetted elérhetővé az nginx proxyt az internetről?**
Egy `LoadBalancer` típusú Service-szel, amiből az AWS Load Balancer Controller publikus NLB-t hoz létre (`external`, `internet-facing`, `instance` annotációk, saját security grouppal). Az NLB a publikus subnetekben van, a node-ok NodePortjára küld, a node SG ezt az NLB SG-ből engedi. A controller IRSA-val kap jogot az NLB létrehozására.

**Mi történne, ha egy node kiesne?**
Az NLB health checkje (a `healthCheckNodePort`-on) elbukik, és az NLB kiveszi azt a node-ot, a másik kettő tovább szolgál ki. Az azon a node-on futó Service A és B podokat a Deploymentek más node-on újraindítják, és amíg nem ready-k, a Service-ek a megmaradt podokra küldenek (2 replika, ezért valószínűleg marad egy). A managed node group új node-ot indít, és arra a DaemonSet automatikusan tesz egy nginx-et. A NAT gateway egy AZ-ban van: ha az az AZ esne ki, a többi AZ node-jai sem jutnának ki az internetre (élesben AZ-nként egy NAT).

**Hogyan skáláznád a Service A-t függetlenül?**
A Service A külön Deployment, ezért a `replicas` értékét önállóan lehet állítani (`kubectl scale deployment service-a --replicas=5 -n demo`, vagy a manifestben). Automatikusan egy **HPA**-val (Horizontal Pod Autoscaler), ami a metrics-server CPU/memória adatai alapján méretez. Ha a node-okon elfogy a hely, egy **Cluster Autoscaler** vagy **Karpenter** indít új node-ot. Ugyanarra a Deploymentre a HPA és a VPA ne ugyanazon a metrikán méretezzen, mert egymás ellen dolgoznának.

**Mit csinálnál másképp, ha újra kellene csinálnod?**

- **Pod Identity** az IRSA helyett (nem kell OIDC provider).
- **Gateway API** a kézzel írt nginx helyett; az ingress-nginx kivezetése miatt is ez az irány.
- **A state kettébontása** (`infra` és `platform`), hogy a Helm provider ne egy ugyanabban a futásban létrejövő clusterhez csatlakozzon; **remote state** S3-ban.
- **AZ-nként egy NAT gateway**, **HTTPS** (ACM tanúsítvány az NLB-n, saját domain).
- **CI/CD** (build, push, telepítés), `IMMUTABLE` ECR tagek git commit azonosítóval.
- **Karpenter** és **HPA** a skálázáshoz.
- **Tanulságként:** a `.gitignore`-t az első commit előtt rendbe tenni, a `plan` erőforrásszámát mindig ellenőrizni, és az AI vagy más által írt kódot ugyanúgy átnézni, mint egy kollégáét, mert a hibák jellemzően elavult verziók és fájlok közötti összefüggések voltak.
