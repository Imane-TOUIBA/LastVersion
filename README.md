# ABAC Genomic - Système de contrôle d'accès basé sur les attributs

Ce projet implémente un système de contrôle d'accès basé sur les attributs (ABAC) pour des données génomiques, en utilisant Hyperledger Fabric. Il démontre un flux d'autorisation multi-organisations et multi-canaux, respectant les principes de séparation des privilèges et de traçabilité.

## Architecture du réseau

Le réseau est composé de 3 organisations et 2 canaux distincts :

### Organisations

- `CGNMSP` (Centre de Génétique) : gère les consentements des patients
- `IBMSP` (Institut de Biologie) : propriétaire des ressources de recherche
- `HUMSP` (Hôpital Universitaire) : portail de gestion des consentements

### Canaux

- `global-channel` : canal partagé contenant les conventions inter-organisations (`gouvernancecc`) et les consentements des patients (`consentcc`)
- `project-channel` : canal privé contenant les politiques d'accès spécifiques aux ressources (`policycc`), isolé des organisations non impliquées

### Chaincodes déployés

- `consentcc` : enregistrement et vérification des consentements patients (global-channel)
- `gouvernancecc` : orchestration de l'évaluation de la confiance (Ptrust) et émission des événements d'attestation (global-channel)
- `policycc` : évaluation des politiques du propriétaire (Powner) sur le canal privé (project-channel)

### Services applicatifs (Node.js)

- `pep-service` : Policy Enforcement Point, évalue les pré-requis locaux avant soumission à la blockchain
- `relay-service` : écoute les événements `AttestationValidated` sur `global-channel` et les retransmet sur `project-channel`
- `consent-portal` : API REST de gestion des consentements pour l'organisation propriétaire

## Prérequis

- Docker et Docker Compose (v2.0+)
- Go (v1.22 ou supérieur)
- Node.js (v18.x ou v20.x) et npm
- Binaires Hyperledger Fabric : `peer`, `cryptogen`, `configtxgen` accessibles dans le `$PATH`

## Installation et démarrage du réseau

1. Cloner le dépôt :
   ```bash
   git clone <URL_DU_REPO>
   cd abac-genomic


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

## Tests validés via le CLI Fabric

Les tests suivants ont été exécutés avec succès et démontrent le fonctionnement du système au niveau de la blockchain.

### Test 1 : Enregistrement d'une ressource

```bash
export CORE_PEER_LOCALMSPID=IBMSP
export CORE_PEER_ADDRESS=localhost:9051
export CORE_PEER_TLS_ROOTCERT_FILE=$PWD/organizations/peerOrganizations/ib.example.com/peers/peer0.ib.example.com/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=$PWD/organizations/peerOrganizations/ib.example.com/users/Admin@ib.example.com/msp
export ORDERER_CA=$PWD/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA \
  -C global-channel -n gouvernancecc \
  --peerAddresses localhost:9051 --tlsRootCertFiles $PWD/organizations/peerOrganizations/ib.example.com/peers/peer0.ib.example.com/tls/ca.crt \
  -c '{"function":"AttestationContract:RegisterResource","Args":["o2b", "IBMSP", "true", "Oncologie"]}'
```

Résultat attendu : `Chaincode invoke successful. result: status:200`

### Test 2 : Enregistrement d'une convention inter-organisations

```bash
peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA \
  -C global-channel -n gouvernancecc \
  --peerAddresses localhost:9051 --tlsRootCertFiles $PWD/organizations/peerOrganizations/ib.example.com/peers/peer0.ib.example.com/tls/ca.crt \
  -c '{"function":"TrustContract:RegisterConvention","Args":["IBMSP", "CGNMSP", "Oncologie", "2030-12-31T23:59:59Z"]}'
```

Résultat attendu : `Chaincode invoke successful. result: status:200`

### Test 3 : Enregistrement d'un consentement patient

```bash
export CORE_PEER_LOCALMSPID=CGNMSP
export CORE_PEER_ADDRESS=localhost:7051
export CORE_PEER_TLS_ROOTCERT_FILE=$PWD/organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=$PWD/organizations/peerOrganizations/cgn.example.com/users/Admin@cgn.example.com/msp

peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA \
  -C global-channel -n consentcc \
  --peerAddresses localhost:7051 --tlsRootCertFiles $PWD/organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt \
  -c '{"function":"RegisterConsent","Args":["alpha", "CGNMSP", "o2b", "Oncologie", "2030-12-31"]}'
```

Résultat attendu : `Chaincode invoke successful. result: status:200`

### Test 4 : Initialisation du chaincode de gouvernance

```bash
peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA \
  -C global-channel -n gouvernancecc \
  --peerAddresses localhost:7051 --tlsRootCertFiles $PWD/organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt \
  --peerAddresses localhost:9051 --tlsRootCertFiles $PWD/organizations/peerOrganizations/ib.example.com/peers/peer0.ib.example.com/tls/ca.crt \
  --peerAddresses localhost:11051 --tlsRootCertFiles $PWD/organizations/peerOrganizations/hu.example.com/peers/peer0.hu.example.com/tls/ca.crt \
  -c '{"function":"InitLedger","Args":[]}'
```

### Test 5 : Initialisation du chaincode de politiques

```bash
peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA \
  -C project-channel -n policycc \
  --peerAddresses localhost:7051 --tlsRootCertFiles $PWD/organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt \
  --peerAddresses localhost:9051 --tlsRootCertFiles $PWD/organizations/peerOrganizations/ib.example.com/peers/peer0.ib.example.com/tls/ca.crt \
  -c '{"function":"InitLedger","Args":[]}'
```

### Test 6 : Évaluation d'accès (Flux 2)

```bash
peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA \
  -C global-channel -n gouvernancecc \
  --peerAddresses localhost:7051 --tlsRootCertFiles $PWD/organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt \
  --peerAddresses localhost:9051 --tlsRootCertFiles $PWD/organizations/peerOrganizations/ib.example.com/peers/peer0.ib.example.com/tls/ca.crt \
  -c '{"function":"EvaluateAccess","Args":["o2b","IBMSP","Oncologie","Executer","2026-07-23","[\"alpha\",\"beta\"]"]}'
```

Résultat attendu : `Chaincode invoke successful. result: status:200`

## Tests validés via les services Node.js

### Évaluation locale Prequester (fail-fast)

Le service PEP évalue localement l'utilisateur avant toute soumission à la blockchain. Ce mécanisme a été validé avec les cas suivants :

- Cas positif : `node submit_access_request.js DrEinstein o2b Executer Oncologie alpha`
  - Résultat : Prequester validé, habilitation `elevee` détectée, soumission à la blockchain effectuée
- Cas négatif (compte inactif) : `node submit_access_request.js DrInactive o2b Executer Oncologie alpha`
  - Résultat : REJET LOCAL (Prequester) : Compte utilisateur inactif
- Cas négatif (utilisateur non autorisé) : `node submit_access_request.js DrUnauthorized o2b Executer Oncologie alpha`
  - Résultat : REJET LOCAL (Prequester) : Non autorisé sur le projet Oncologie

### Connexion au réseau Fabric depuis Node.js

La connexion via le SDK moderne `@hyperledger/fabric-gateway` a été validée. Le service PEP se connecte avec succès au pair de CGN en utilisant les certificats générés par `cryptogen`, et soumet des transactions à `gouvernancecc` qui sont correctement endossées et retournent un résultat structuré.

## Structure du projet

```text
abac-genomic/
├── chaincodes/
│   ├── consentcc/         # Chaincode de gestion des consentements
│   ├── gouvernancecc/     # Chaincode d'orchestration et de confiance
│   └── policycc/          # Chaincode des politiques d'accès (Powner)
├── services/
│   ├── pep-service/       # Policy Enforcement Point (Node.js)
│   ├── relay-service/     # Service de relais inter-canaux (Node.js)
│   └── consent-portal/    # API de gestion des consentements (Node.js)
├── organizations/         # Artefacts cryptographiques (générés)
├── channel-artifacts/     # Blocs de genèse et configurations (générés)
├── setup_all.sh           # Génération et démarrage du réseau
├── deploy_chaincodes.sh   # Déploiement des chaincodes (CCAAS)
└── init_network.sh        # Initialisation des ledgers
```

## Notes techniques

- **Mode CCAAS** : les chaincodes sont déployés en mode "Chaincode as a Service". Les conteneurs sont construits localement via Docker et se connectent aux pairs Fabric via le réseau Docker `abac-genomic_test`.
- **Sécurité** : les identités utilisées par les services Node.js sont extraites directement des dossiers MSP générés par `cryptogen`.
- **Isolation des canaux** : `policycc` n'est déployé que sur `project-channel`, assurant que les politiques d'accès détaillées ne sont pas visibles sur le canal public `global-channel`.
- **Syntaxe multi-contrats** : `gouvernancecc` contient deux contrats (`AttestationContract` et `TrustContract`). Les appels CLI doivent utiliser la syntaxe `NomContrat:NomFonction` (ex: `AttestationContract:RegisterResource`).
```

### Contenu du `init_network.sh`

```bash
#!/bin/bash

# Script d'initialisation des ledgers avec les données de démonstration
# Usage: ./init_network.sh

set -e

echo "=== Initialisation des données du réseau ==="

export FABRIC_CFG_PATH=$PWD/config
export PATH=$PWD/bin:$PATH
ORDERER_CA=$PWD/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

# ==============================================================================
# 1. INITIALISATION DE CONSENTCC (global-channel)
# ==============================================================================
echo "--- Initialisation de consentcc ---"
export CORE_PEER_LOCALMSPID=CGNMSP
export CORE_PEER_ADDRESS=localhost:7051
export CORE_PEER_TLS_ROOTCERT_FILE=$PWD/organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=$PWD/organizations/peerOrganizations/cgn.example.com/users/Admin@cgn.example.com/msp

peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA \
  -C global-channel -n consentcc \
  --peerAddresses localhost:7051 --tlsRootCertFiles $PWD/organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt \
  --peerAddresses localhost:9051 --tlsRootCertFiles $PWD/organizations/peerOrganizations/ib.example.com/peers/peer0.ib.example.com/tls/ca.crt \
  --peerAddresses localhost:11051 --tlsRootCertFiles $PWD/organizations/peerOrganizations/hu.example.com/peers/peer0.hu.example.com/tls/ca.crt \
  -c '{"function":"InitLedger","Args":[]}'

# ==============================================================================
# 2. INITIALISATION DE GOUVERNANCECC (global-channel)
# ==============================================================================
echo "--- Initialisation de gouvernancecc ---"
peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA \
  -C global-channel -n gouvernancecc \
  --peerAddresses localhost:7051 --tlsRootCertFiles $PWD/organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt \
  --peerAddresses localhost:9051 --tlsRootCertFiles $PWD/organizations/peerOrganizations/ib.example.com/peers/peer0.ib.example.com/tls/ca.crt \
  --peerAddresses localhost:11051 --tlsRootCertFiles $PWD/organizations/peerOrganizations/hu.example.com/peers/peer0.hu.example.com/tls/ca.crt \
  -c '{"function":"InitLedger","Args":[]}'

# ==============================================================================
# 3. INITIALISATION DE POLICYCC (project-channel)
# ==============================================================================
echo "--- Initialisation de policycc ---"
peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA \
  -C project-channel -n policycc \
  --peerAddresses localhost:7051 --tlsRootCertFiles $PWD/organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt \
  --peerAddresses localhost:9051 --tlsRootCertFiles $PWD/organizations/peerOrganizations/ib.example.com/peers/peer0.ib.example.com/tls/ca.crt \
  -c '{"function":"InitLedger","Args":[]}'

# ==============================================================================
# 4. ENREGISTREMENT DE LA RESSOURCE "o2b" (par IBMSP, propriétaire)
# ==============================================================================
echo "--- Enregistrement de la ressource o2b ---"
export CORE_PEER_LOCALMSPID=IBMSP
export CORE_PEER_ADDRESS=localhost:9051
export CORE_PEER_TLS_ROOTCERT_FILE=$PWD/organizations/peerOrganizations/ib.example.com/peers/peer0.ib.example.com/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=$PWD/organizations/peerOrganizations/ib.example.com/users/Admin@ib.example.com/msp

peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA \
  -C global-channel -n gouvernancecc \
  --peerAddresses localhost:9051 --tlsRootCertFiles $PWD/organizations/peerOrganizations/ib.example.com/peers/peer0.ib.example.com/tls/ca.crt \
  -c '{"function":"AttestationContract:RegisterResource","Args":["o2b", "IBMSP", "true", "Oncologie"]}'

# ==============================================================================
# 5. ENREGISTREMENT DE LA CONVENTION IBMSP -> CGNMSP
# ==============================================================================
echo "--- Enregistrement de la convention IBMSP -> CGNMSP ---"
peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA \
  -C global-channel -n gouvernancecc \
  --peerAddresses localhost:9051 --tlsRootCertFiles $PWD/organizations/peerOrganizations/ib.example.com/peers/peer0.ib.example.com/tls/ca.crt \
  -c '{"function":"TrustContract:RegisterConvention","Args":["IBMSP", "CGNMSP", "Oncologie", "2030-12-31T23:59:59Z"]}'

# ==============================================================================
# 6. ENREGISTREMENT DU CONSENTEMENT DU PATIENT ALPHA (par CGNMSP)
# ==============================================================================
echo "--- Enregistrement du consentement du patient alpha ---"
export CORE_PEER_LOCALMSPID=CGNMSP
export CORE_PEER_ADDRESS=localhost:7051
export CORE_PEER_TLS_ROOTCERT_FILE=$PWD/organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=$PWD/organizations/peerOrganizations/cgn.example.com/users/Admin@cgn.example.com/msp

peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA \
  -C global-channel -n consentcc \
  --peerAddresses localhost:7051 --tlsRootCertFiles $PWD/organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt \
  -c '{"function":"RegisterConsent","Args":["alpha", "CGNMSP", "o2b", "Oncologie", "2030-12-31"]}'

echo "=== Initialisation terminée ==="
```
