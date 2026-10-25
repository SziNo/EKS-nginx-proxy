# Jegyzetek: fogalmak, hibakeresési napló, felkészülés az 1on1-re

## 1. Fogalmak

### A kérés teljes útja

1. A kliens az NLB DNS nevére küld egy HTTP kérést.
2. Az **NLB** (4. réteg) csak a TCP kapcsolatot továbbítja, a HTTP-be nem néz bele. `target-type: instance` miatt egy node IP-jére és a Service **NodePortjára** küldi.
3. A node-on a kernel a **kube-proxy** által írt szabályok alapján DNAT-tal átírja a célt a **helyi nginx pod** IP-jére (`externalTrafficPolicy: Local`).
4. Az **nginx** (7. réteg) lezárja a kliens kapcsolatát, kiolvassa a HTTP útvonalat, és egy **új TCP kapcsolatot** nyit a `service-a.demo.svc.cluster.local` felé. Két külön kapcsolat van: kliens → nginx és nginx → Service.
5. A nevet a CoreDNS a Service **ClusterIP**-jére oldja fel; a kernel ezt átírja **bármelyik** ready Service A pod IP-jére, ami lehet egy másik node-on is. A node-ok közötti utat a VPC CNI adja (a podok valódi VPC IP-t kapnak).

### NodePort

- A NodePort a **Service** tulajdonsága, nem egy node-é. Az API server osztja ki a 30000–32767 tartományból, és **minden node-on** ugyanaz a port.
- A porton nem egy folyamat „hallgat”: iptables módban ezek kernel (netfilter) szabályok.

### Service → EndpointSlice → kube-proxy

1. A Service `selector`-a (sima label map) dönti el, mely **podok** tartoznak hozzá. A `matchLabels` a Deployment és a DaemonSet `spec.selector`-ában van.
2. Az **EndpointSlice controller** beírja a megfelelő podokat az EndpointSlice-okba: IP, port, ready-e, és melyik node-on fut (`nodeName`).
3. A **kube-proxy** minden node-on ebből írja a szabályokat.

Élőben: `kubectl get endpointslices -n demo -o yaml`.

### `externalTrafficPolicy`: `Local` vs `Cluster`

A Service mezője, nem node-onkénti beállítás.

- **`Local`:** a node csak a saját helyi podjaira küld; ha nincs ilyen, eldobja a forgalmat. A Service kap egy `healthCheckNodePort`-ot, amin az NLB megkérdezi, van-e a node-on ready endpoint. Nincs extra ugrás, nincs SNAT, megmarad a kliens IP. Hátránya: egyenetlen elosztás, ha a podok egyenetlenül vannak a node-okon.
- **`Cluster`:** az összes endpoint közül véletlenszerűen választ (3 node-nál kb. 2/3 átmegy egy másik node-ra), és a kívülről, NodePorton érkező forgalmat **mindig** SNAT-olja, akkor is, ha helyben marad. A kliens IP **mindig** elveszik, nem „néha”.
- DaemonSet mellett a `Cluster` nem ad jobb elosztást (minden node-on egy nginx van, és az NLB eleve egyenletesen oszt), csak a hátrányait hozná.
- Ha csak egy node-on futna nginx: `Local` mellett az NLB csak arra az egy node-ra küldene (működik, de egyetlen hibapont), és akkor a DaemonSet értelme is elveszne.

### Kliens IP

Az eredeti forráscím az IP fejlécben (otthonról a router nyilvános címe, cégnél a kimenő cím). Ami útközben SNAT-ol, eltünteti.

Mire kell: naplózás és hibakeresés, rate limiting, IP tiltás és engedélyezés, csalásfelderítés, földrajzi helymeghatározás. Ha elveszik, minden kérés a node IP-jéről jön: a rate limit mindenkit blokkolna, a log használhatatlan.

Nálunk: az NLB `instance` targetnél megtartja, a `Local` miatt a node sem írja át; az nginx az `X-Real-IP` és `X-Forwarded-For` fejlécbe teszi. Ha mégis elveszne: **Proxy Protocol v2**.

### Ingress és Gateway API

- Az **AWS Load Balancer Controller** Helmmel telepített controller (nem EKS managed addon): a `LoadBalancer` Service-ből NLB-t, az Ingressből ALB-t csinál.
- A **Gateway API** az Ingress utódja. Szabványos mezők a fejléc alapú routingra, súlyozott forgalomra stb. (annotációk helyett), TCP/UDP/gRPC is, és szerepek szerint szétválasztott resource-ok: **GatewayClass** (melyik controller), **Gateway** (a belépési pont, listenerek, TLS), **HTTPRoute** (útvonalak, `parentRefs`-szel csatolva).
- EKS-en: a CRD-ket külön kell telepíteni, és kell egy controller: az AWS LBC újabb verziói, egy clusteren belüli proxy (Envoy Gateway, Istio, Cilium, NGINX Gateway Fabric), vagy a VPC Lattice controller (inkább szolgáltatások közötti forgalomra).
- Az ingress-nginx controllert a Kubernetes projekt 2025 végén kivezetésre jelölte.

### Multi-stage Docker build

- Több `FROM` = több szakasz, mindegyik saját, üres fájlrendszerrel. A végső image csak az utolsó szakasz; a korábbiakból csak az kerül át, amit a `COPY --from=` átmásol.
- `COPY --from=builder /opt/venv /opt/venv`: ugyanaz a név, de az első a builder fájlrendszerében, a második a runtime-éban van.
- Azért kell ugyanaz az útvonal, mert a venv szkriptjeinek shebangje abszolút: `#!/opt/venv/bin/python`.
- A `requirements.txt` az app kód előtt kerül be: így a `pip install` réteg cache-ből jön, ha csak az `app.py` változik.
- Őszintén: itt a nyereség kicsi, mert a builderbe nem kell fordító (a Flask és a gunicorn kész wheel). Akkor igazán értékes, ha egy csomag C kiterjesztést fordít (`gcc`, `build-essential` csak a builderben).

### Terraform

- **Egy mappa = egy egész:** a Terraform az összes `.tf` fájlt egyben olvassa, a fájlok neve és száma neki mindegy.
- **`required_providers`:** a root rögzít (`~> 6.0`, plusz a lock fájl), a modul minimumot jelez (`>= 6.0`). Az `init` összefésüli; ha nincs közös verzió, hibát ad. HashiCorp providernél a modulban elhagyható (a név alapján kitalálja), nem HashiCorp providernél (pl. `gavinbunney/kubectl`) kötelező.
- **Provider konfiguráció** (`provider "aws" { ... }`) csak a rootban; a modulok öröklik.
- **State:** egy root modulhoz egy state, benne minden modul erőforrása (`module.vpc.aws_vpc.this`). Nézd: `terraform state list`. A `plan` nem ír state-et.
- **State szétbontása:** nem modulonként, hanem több root modulra (rétegekre). Előny: kisebb blast radius, gyorsabb plan, külön jogosultság, nincs zárolási ütközés. Hátrány: adatátadás (`terraform_remote_state` vagy data source), sorrend. Itt az egy state a jó; élesben a clustert és a clusterbe telepített dolgokat (Helm) választanám szét.
- **tfvars:** a `variable` blokk **deklarál**, a tfvars **értéket ad**, a modulhívás **felhasznál**. A `terraform.tfvars` automatikusan betöltődik.
- **Verziórögzítés:** ugyanaz a kód máshol azért romolhat el, mert más provider vagy modul verzió jön le (Helm 2.x → 3.x, EKS modul 20 → 21 változónév-változás). Ezért kell a `versions.tf` és a `.terraform.lock.hcl` a gitbe.

### Node méret és pod limit

A VPC CNI miatt minden pod VPC IP-t kap, így egy node-on annyi pod lehet, ahány IP-t a típus ENI-i adni tudnak: `t2.micro`/`t3.micro` 4, `t3.small` 11, `t3.medium` 17. Node-onként 3 hely már foglalt (`aws-node`, `kube-proxy`, nginx). Interjúkérdés: „miért `Pending` a pod, ha van szabad CPU és memória?”

## 2. Hibakeresési napló

| #   | Mi történt                                                                                | Ok                                                                                                 | Megoldás / tanulság                                                                                   |
| --- | ----------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| 1   | `sudo snap install helm` nem megbízható WSL alatt                                         | A snaphez systemd kell, ami WSL-ben nem mindig fut                                                 | Hivatalos telepítő szkript (`get-helm-3`)                                                             |
| 2   | A referencia registry EKS modult használt                                                 | Szabályos, de a feladat IAM szerepeket és SG-ket kér, és azokat el kell tudni magyarázni           | Saját `eks` modul                                                                                     |
| 3   | `Unexpected block: Blocks of type "set"` és `"kubernetes"`                                | A Helm provider 3.x-ben ezek attribútumok                                                          | `kubernetes = { exec = { ... } }`, `set = [ { ... } ]`; `terraform init -upgrade`                     |
| 4   | `kubernetes_version = "1.33"`                                                             | Extended supportban lett volna (kb. hatszoros óradíj), és a kubectl 1.37 csak ±1 alverziót támogat | `aws eks describe-cluster-versions` → 1.37                                                            |
| 5   | A Claude Code `1.13.0` chartot és „chart 1.N = controller 2.N” szabályt javasolt          | Régi ismeret; a 3.x óta a chart és a controller verziója egyezik                                   | `helm search repo ... --versions` → 3.6.2; `helm show values` a kulcsokra; `curl -f` a policy JSON-ra |
| 6   | Egy terminálból másolt log alapján hibásnak tűnt az `oidc.tf`                             | A log összecsúszott; a fájl helyes volt                                                            | Mindig a tényleges fájlt nézd (`cat`, `git diff`), ne logot vagy összefoglalót                        |
| 7   | `No declaration found for "var.node_desired_size"` és `Unexpected attribute` a tfvars-ban | A root `variables.tf`-ből hiányzott a deklaráció                                                   | `variable` blokk a rootban                                                                            |
| 8   | Free tier: csak `t2.micro`                                                                | 4 pod/node, 1 GB: nem férnek el a podok; az EKS, a NAT és az NLB amúgy sem ingyenes                | `t3.medium` marad (kb. 0,33 $/óra összesen)                                                           |

Az `apply` és a telepítés hibáit ide érdemes tovább vezetni.

## 3. Nyitott pontok

- **`render.sh`:** a `sed -i` közvetlenül a git által követett fájlokba írja az értékeket, így a második futtatásnál nincs mit cserélni (csak a tag frissül), és a kitöltött értékek (account ID, SG ID) a gitbe kerülhetnek. A `k8s/` átnézésénél döntjük el, hogyan javítsuk.
- **A `build-push.sh` elmagyarázása** saját szavakkal.
- **A Service annotációk** működnek-e változatlanul az LB Controller 3.x-szel (v3.0.0 kiadási jegyzet).
