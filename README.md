# ABAC Genomic

Système de contrôle d'accès basé sur les attributs (ABAC) pour des données génomiques, implémenté sur Hyperledger Fabric. Ce projet démontre un flux d'autorisation multi-organisations et multi-canaux, respectant les principes de séparation des privilèges (Prequester, Ptrust, Consentement, Powner) et de traçabilité immuable.

## Architecture du réseau

Le réseau est composé de 3 organisations et 2 canaux distincts.

### Organisations

- `CGNMSP` (Centre de Génomique)
- `IBMSP` (Institut BioInformatique)
- `HUMSP` (Hôpital Universitaire)

### Canaux

- `global-channel` : canal partagé contenant principalement les conventions inter-organisations et les consentements des patients.
- `project-channel` : canal privé contenant les politiques d'accès spécifiques aux ressources, isolé des organisations non impliquées.

### Chaincodes

- `consentcc` : enregistrement, vérification et révocation des consentements patients (global-channel).
- `gouvernancecc` : orchestration de l'évaluation de la confiance (Ptrust) et émission des événements d'attestation (global-channel). Contient les contrats `AttestationContract` et `TrustContract`.
- `policycc` : évaluation des politiques du propriétaire (Powner) sur le canal privé (project-channel).

### Services applicatifs (Node.js)

- `pep-service` : Policy Enforcement Point. Évalue les pré-requis locaux (Prequester) avant toute soumission à la blockchain.
- `relay-service` : écoute les événements `AttestationValidated` sur `global-channel` et les retransmet vers `policycc` sur `project-channel`.
- `consent-portal` : API REST de gestion des consentements pour l'organisation propriétaire.

## Prérequis

- Docker et Docker Compose (v2.0+)
- Go (v1.22 ou supérieur)
- Node.js (v18.x ou v20.x) et npm
- Binaires Hyperledger Fabric : `peer`, `cryptogen`, `configtxgen` accessibles dans le `$PATH`.

1. Mise à jour du système et installation des outils de base

- sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y curl git make jq python3-pip

2. Installation de Docker et Docker Compose
Le projet nécessite Docker et Docker Compose v2.0+
.
# Installation de Docker
sudo apt-get install -y docker.io
# Ajout de l'utilisateur au groupe docker (déconnexion/reconnexion nécessaire ensuite)
sudo usermod -aG docker $USER
# Installation du plugin Docker Compose
sudo apt-get install -y docker-compose-v2

3. Installation de Go (Version 1.22.2 recommandée)
Le projet utilise Go pour les Smart Contracts

wget https://go.dev/dl/go1.22.2.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.22.2.linux-amd64.tar.gz

# Configuration du PATH pour Go

echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc

4. Installation de Node.js (Version 20.x)
Nécessaire pour les services pep-service et relay-service

curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

5. Installation des binaires Hyperledger Fabric (2.5.4) et Samples

# Téléchargement du script officiel et installation des binaires/images
# On installe la version 2.5.4 et l'orderer CA 1.5.7
curl -sSL https://bit.ly/2ysbOFE | bash -s -- 2.5.4 1.5.7

6. Configuration finale de l'environnement
Pour que les commandes peer soient reconnues, vous devez configurer les variables d'environnement dans votre session (ou les ajouter à votre .bashrc) :

export PATH=$HOME/bin:$PATH
export FABRIC_CFG_PATH=$HOME/config
export CORE_PEER_TLS_ENABLED=true

7. Installation de la bibliothèque Python PyYAML
Comme Ubuntu 24.04 gère strictement les environnements Python (PEP 668), il est recommandé d'utiliser le gestionnaire de paquets système pour installer PyYAML, nécessaire au script generate_network.py:

sudo apt install -y python3-yaml

## Installation et déploiement

1. Cloner le dépôt et se placer dans le répertoire :
    
    ```bash
    git clone <URL_DU_REPO>
    cd abac-genomic
    ```
    
2. Générer les artefacts cryptographiques et démarrer le réseau Docker :
    
    ```bash
    ./setup_all.sh
    ```
    
3. Déployer les chaincodes en mode CCAAS (Chaincode as a Service) :
    
    ```bash
    ./deploy_chaincodes.sh
    ```
    
4. Initialiser les ledgers avec les données de démonstration :
    
    ```bash
    ./init_network.sh
    ```
    

## Procédures de test et de démonstration

Les sections suivantes détaillent les commandes pour valider le fonctionnement du système.

### 1. Configuration de l'environnement CLI

Avant d'exécuter toute commande Fabric, les variables d'environnement suivantes doivent être définies :

```bash
export PATH=$HOME/bin:$PATH
export FABRIC_CFG_PATH=$HOME/config
export CORE_PEER_TLS_ENABLED=true
export ORDERER_CA=$PWD/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

PEER_CGN="localhost:7051"
TLS_CGN="$PWD/organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt"
PEER_IBM="localhost:9051"
TLS_IBM="$PWD/organizations/peerOrganizations/ib.example.com/peers/peer0.ib.example.com/tls/ca.crt"
PEER_HU="localhost:11051"
TLS_HU="$PWD/organizations/peerOrganizations/hu.example.com/peers/peer0.hu.example.com/tls/ca.crt"
```

### 2. Cycle de vie du consentement (via CLI)

Ce test valide l'enregistrement, la vérification et la révocation d'un consentement.

```bash
# Configuration en tant qu'administrateur CGNMSP
export CORE_PEER_LOCALMSPID=CGNMSP
export CORE_PEER_ADDRESS=$PEER_CGN
export CORE_PEER_TLS_ROOTCERT_FILE=$TLS_CGN
export CORE_PEER_MSPCONFIGPATH=$PWD/organizations/peerOrganizations/cgn.example.com/users/Admin@cgn.example.com/msp

# 1. Enregistrer un consentement
peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA \
  -C global-channel -n consentcc \
  --peerAddresses $PEER_CGN --tlsRootCertFiles $TLS_CGN \
  --peerAddresses $PEER_IBM --tlsRootCertFiles $TLS_IBM \
  --peerAddresses $PEER_HU --tlsRootCertFiles $TLS_HU \
  --waitForEvent \
  -c '{"function":"RegisterConsent","Args":["patient_test","CGNMSP","o2b","Oncologie","2030-12-31"]}'

# 2. Vérifier le consentement (résultat attendu : true)
peer chaincode query -C global-channel -n consentcc \
  -c '{"function":"CheckConsent","Args":["patient_test","CGNMSP","o2b","Oncologie"]}'

# 3. Révoquer le consentement
peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA \
  -C global-channel -n consentcc \
  --peerAddresses $PEER_CGN --tlsRootCertFiles $TLS_CGN \
  --peerAddresses $PEER_IBM --tlsRootCertFiles $TLS_IBM \
  --peerAddresses $PEER_HU --tlsRootCertFiles $TLS_HU \
  --waitForEvent \
  -c '{"function":"RevokeConsent","Args":["patient_test","CGNMSP","o2b","Oncologie"]}'

# 4. Vérifier à nouveau (résultat attendu : false)
peer chaincode query -C global-channel -n consentcc \
  -c '{"function":"CheckConsent","Args":["patient_test","CGNMSP","o2b","Oncologie"]}'
```

### 3. Flux de demande d'accès complet (via Node.js)

Ce test orchestre l'évaluation locale, la soumission blockchain et le relais inter-canaux.

**Terminal 1 : Lancer le service Relais**

```bash
cd ~/abac-genomic/services/relay-service
killall node 2>/dev/null || true
node relay.js
```

**Terminal 2 : Lancer la requête via le PEP**

```bash
cd ~/abac-genomic/services/pep-service

# Cas 1 : Accès autorisé (PERMIT)
node submit_access_request.js DrEinstein o2b Executer Oncologie alpha

# Cas 2 : Accès refusé pour habilitation insuffisante (DENY)
node submit_access_request.js DrSmith o2b Executer Oncologie alpha

# Cas 3 : Rejet local immédiat (Fail-fast, non autorisé sur le projet)
node submit_access_request.js DrUnauthorized o2b Executer Oncologie alpha
```

**Résultats attendus :**

- Pour les Cas 1 et 2, le terminal du Relais doit afficher `[relay] décision enregistrée : PERMIT` ou `DENY`.
- Pour le Cas 3, le terminal du PEP doit afficher `REJET LOCAL (Prequester)`, et aucune activité ne doit apparaître dans le Relais, démontrant l'optimisation du système.

### 4. Benchmark de performance

Un script de benchmark est inclus pour mesurer la latence et le débit du système sur un échantillon de requêtes variées.

**Exécution du benchmark (ex: 20 requêtes) :**

```bash
cd ~/abac-genomic/services/pep-service
node benchmark.js 20
```

**Métriques typiques observées sur ce prototype :**

| Indicateur | Valeur moyenne | Interprétation |
| --- | --- | --- |
| --- | ---: | --- |
| Débit | 0.73 req/s | Limité par le consensus multi-organisations et l'écriture immuable. |
| Latence (Blockchain) | ~2200 ms | Inclut l'endossement par 3 pairs, le tri par l'Orderer et le commit. |
| Latence (Fail-fast) | < 5 ms | Traitement local instantané pour les requêtes non conformes. |
| Taux de rejet local | ~40% | Économie significative de transactions blockchain inutiles. |
| Taux d'erreur | 0% | Stabilité du système lors des tests séquentiels. |

*Note : Un fichier CSV détaillé est généré dans `~/abac-genomic/benchmark_results/` après chaque exécution.*

## Structure du projet

```
abac-genomic/
├── chaincodes/
│   ├── consentcc/         # Chaincode de gestion des consentements (Go)
│   ├── gouvernancecc/     # Chaincode d'orchestration et de confiance (Go)
│   └── policycc/          # Chaincode des politiques d'accès Powner (Go)
├── services/
│   ├── pep-service/       # Policy Enforcement Point (Node.js)
│   ├── relay-service/     # Service de relais inter-canaux (Node.js)
│   └── consent-portal/    # API de gestion des consentements (Node.js)
├── organizations/         # Artefacts cryptographiques (générés)
├── channel-artifacts/     # Blocs de genèse et configurations (générés)
├── benchmark_results/     # Résultats des tests de performance (générés)
├── setup_all.sh           # Génération et démarrage du réseau
├── deploy_chaincodes.sh   # Déploiement des chaincodes (CCAAS)
└── init_network.sh        # Initialisation des ledgers avec des données de test
```

## Notes techniques

1. **Mode CCAAS** : Les chaincodes sont déployés en mode "Chaincode as a Service". Les conteneurs sont construits localement via Docker et se connectent aux pairs Fabric via le réseau Docker `abac-genomic_test`.
2. **Politique d'endossement** : Les invocations sur `global-channel` doivent inclure les 3 arguments `--peerAddresses` (CGN, IBM, HU) pour satisfaire la politique d'endossement par défaut du canal. L'omission de ce paramètre entraîne une erreur `ENDORSEMENT_POLICY_FAILURE`.
3. **Sécurité des transactions** : Le chaincode `gouvernancecc` implémente une vérification de nonce pour prévenir les attaques par rejeu. Chaque payload soumis doit contenir un champ `nonce` unique.
4. **Syntaxe multi-contrats** : Pour `gouvernancecc`, les appels CLI doivent utiliser la syntaxe `NomContrat:NomFonction` (ex: `AttestationContract:RegisterResource`).

