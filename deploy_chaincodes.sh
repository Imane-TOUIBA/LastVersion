#!/bin/bash

# Script de déploiement automatisé des chaincodes en mode CCAAS
# Usage: ./deploy_chaincodes.sh

set -e

echo "=== Démarrage du déploiement des chaincodes ==="

# Configuration des variables d'environnement
export FABRIC_CFG_PATH=$PWD/config
export PATH=$PWD/bin:$PATH

# Variables communes
ORDERER_CA=$PWD/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
CHANNEL_GLOBAL="global-channel"
CHANNEL_PROJECT="project-channel"

# Fonction utilitaire pour attendre que Docker soit prêt
wait_for_docker() {
    sleep 3
}

# ==============================================================================
# 1. DÉPLOIEMENT DE CONSENTCC (global-channel : CGN, IB, HU)
# ==============================================================================
echo "--- Déploiement de consentcc ---"
cd $PWD/chaincodes/consentcc

# 1.1 Construction de l'image Docker
docker build -t consentcc_ccaas_image:latest .

# 1.2 Packaging
echo '{"address":"consentcc_ccaas:9999","dial_timeout":"10s","tls_required":false}' > connection.json
echo '{"type":"ccaas","label":"consentcc_1.0"}' > metadata.json
tar -czf code.tar.gz connection.json
tar -czvf $PWD/../../consentcc_ccaas.tar.gz metadata.json code.tar.gz

# 1.3 Installation et Approbation pour les 3 organisations
for org in "CGNMSP localhost:7051 cgn" "IBMSP localhost:9051 ib" "HUMSP localhost:11051 hu"; do
  set -- $org
  export CORE_PEER_LOCALMSPID=$1
  export CORE_PEER_ADDRESS=$2
  export CORE_PEER_TLS_ROOTCERT_FILE=$PWD/../../organizations/peerOrganizations/$3.example.com/peers/peer0.$3.example.com/tls/ca.crt
  export CORE_PEER_MSPCONFIGPATH=$PWD/../../organizations/peerOrganizations/$3.example.com/users/Admin@$3.example.com/msp
  
  peer lifecycle chaincode install ../../consentcc_ccaas.tar.gz
  CC_PACKAGE_ID=$(peer lifecycle chaincode calculatepackageid ../../consentcc_ccaas.tar.gz)
  
  peer lifecycle chaincode approveformyorg -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
    --channelID $CHANNEL_GLOBAL --name consentcc --version 1.0 --package-id $CC_PACKAGE_ID --sequence 1 --tls --cafile $ORDERER_CA
done

# 1.4 Commit
export CORE_PEER_LOCALMSPID=CGNMSP
export CORE_PEER_ADDRESS=localhost:7051
export CORE_PEER_TLS_ROOTCERT_FILE=$PWD/../../organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=$PWD/../../organizations/peerOrganizations/cgn.example.com/users/Admin@cgn.example.com/msp

peer lifecycle chaincode commit -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
  --channelID $CHANNEL_GLOBAL --name consentcc --version 1.0 --sequence 1 --tls --cafile $ORDERER_CA \
  --peerAddresses localhost:7051 --tlsRootCertFiles $PWD/../../organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt \
  --peerAddresses localhost:9051 --tlsRootCertFiles $PWD/../../organizations/peerOrganizations/ib.example.com/peers/peer0.ib.example.com/tls/ca.crt \
  --peerAddresses localhost:11051 --tlsRootCertFiles $PWD/../../organizations/peerOrganizations/hu.example.com/peers/peer0.hu.example.com/tls/ca.crt

# 1.5 Lancement du conteneur CCAAS
CC_PACKAGE_ID=$(peer lifecycle chaincode calculatepackageid ../../consentcc_ccaas.tar.gz)
docker rm -f consentcc_ccaas 2>/dev/null || true
docker run --rm -d --name consentcc_ccaas --network abac-genomic_test \
  -e CHAINCODE_SERVER_ADDRESS=0.0.0.0:9999 \
  -e CORE_CHAINCODE_ID_NAME="$CC_PACKAGE_ID" \
  consentcc_ccaas_image:latest
wait_for_docker


# ==============================================================================
# 2. DÉPLOIEMENT DE GOUVERNANCECC (global-channel : CGN, IB, HU)
# ==============================================================================
echo "--- Déploiement de gouvernancecc ---"
cd $PWD/../gouvernancecc

docker build -t gouvernancecc_ccaas_image:latest .
echo '{"address":"gouvernancecc_ccaas:9999","dial_timeout":"10s","tls_required":false}' > connection.json
echo '{"type":"ccaas","label":"gouvernancecc_1.0"}' > metadata.json
tar -czf code.tar.gz connection.json
tar -czvf $PWD/../../gouvernancecc_ccaas.tar.gz metadata.json code.tar.gz

for org in "CGNMSP localhost:7051 cgn" "IBMSP localhost:9051 ib" "HUMSP localhost:11051 hu"; do
  set -- $org
  export CORE_PEER_LOCALMSPID=$1
  export CORE_PEER_ADDRESS=$2
  export CORE_PEER_TLS_ROOTCERT_FILE=$PWD/../../organizations/peerOrganizations/$3.example.com/peers/peer0.$3.example.com/tls/ca.crt
  export CORE_PEER_MSPCONFIGPATH=$PWD/../../organizations/peerOrganizations/$3.example.com/users/Admin@$3.example.com/msp
  
  peer lifecycle chaincode install ../../gouvernancecc_ccaas.tar.gz
  CC_PACKAGE_ID=$(peer lifecycle chaincode calculatepackageid ../../gouvernancecc_ccaas.tar.gz)
  
  peer lifecycle chaincode approveformyorg -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
    --channelID $CHANNEL_GLOBAL --name gouvernancecc --version 1.0 --package-id $CC_PACKAGE_ID --sequence 1 --tls --cafile $ORDERER_CA
done

export CORE_PEER_LOCALMSPID=CGNMSP
export CORE_PEER_ADDRESS=localhost:7051
export CORE_PEER_TLS_ROOTCERT_FILE=$PWD/../../organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=$PWD/../../organizations/peerOrganizations/cgn.example.com/users/Admin@cgn.example.com/msp

peer lifecycle chaincode commit -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
  --channelID $CHANNEL_GLOBAL --name gouvernancecc --version 1.0 --sequence 1 --tls --cafile $ORDERER_CA \
  --peerAddresses localhost:7051 --tlsRootCertFiles $PWD/../../organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt \
  --peerAddresses localhost:9051 --tlsRootCertFiles $PWD/../../organizations/peerOrganizations/ib.example.com/peers/peer0.ib.example.com/tls/ca.crt \
  --peerAddresses localhost:11051 --tlsRootCertFiles $PWD/../../organizations/peerOrganizations/hu.example.com/peers/peer0.hu.example.com/tls/ca.crt

CC_PACKAGE_ID=$(peer lifecycle chaincode calculatepackageid ../../gouvernancecc_ccaas.tar.gz)
docker rm -f gouvernancecc_ccaas 2>/dev/null || true
docker run --rm -d --name gouvernancecc_ccaas --network abac-genomic_test \
  -e CHAINCODE_SERVER_ADDRESS=0.0.0.0:9999 \
  -e CORE_CHAINCODE_ID_NAME="$CC_PACKAGE_ID" \
  gouvernancecc_ccaas_image:latest
wait_for_docker


# ==============================================================================
# 3. DÉPLOIEMENT DE POLICYCC (project-channel : CGN, IB uniquement)
# ==============================================================================
echo "--- Déploiement de policycc ---"
cd $PWD/../policycc

docker build -t policycc_ccaas_image:latest .
echo '{"address":"policycc_ccaas:9999","dial_timeout":"10s","tls_required":false}' > connection.json
echo '{"type":"ccaas","label":"policycc_1.0"}' > metadata.json
tar -czf code.tar.gz connection.json
tar -czvf $PWD/../../policycc_ccaas.tar.gz metadata.json code.tar.gz

for org in "CGNMSP localhost:7051 cgn" "IBMSP localhost:9051 ib"; do
  set -- $org
  export CORE_PEER_LOCALMSPID=$1
  export CORE_PEER_ADDRESS=$2
  export CORE_PEER_TLS_ROOTCERT_FILE=$PWD/../../organizations/peerOrganizations/$3.example.com/peers/peer0.$3.example.com/tls/ca.crt
  export CORE_PEER_MSPCONFIGPATH=$PWD/../../organizations/peerOrganizations/$3.example.com/users/Admin@$3.example.com/msp
  
  peer lifecycle chaincode install ../../policycc_ccaas.tar.gz
  CC_PACKAGE_ID=$(peer lifecycle chaincode calculatepackageid ../../policycc_ccaas.tar.gz)
  
  peer lifecycle chaincode approveformyorg -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
    --channelID $CHANNEL_PROJECT --name policycc --version 1.0 --package-id $CC_PACKAGE_ID --sequence 1 --tls --cafile $ORDERER_CA
done

export CORE_PEER_LOCALMSPID=CGNMSP
export CORE_PEER_ADDRESS=localhost:7051
export CORE_PEER_TLS_ROOTCERT_FILE=$PWD/../../organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=$PWD/../../organizations/peerOrganizations/cgn.example.com/users/Admin@cgn.example.com/msp

peer lifecycle chaincode commit -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
  --channelID $CHANNEL_PROJECT --name policycc --version 1.0 --sequence 1 --tls --cafile $ORDERER_CA \
  --peerAddresses localhost:7051 --tlsRootCertFiles $PWD/../../organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt \
  --peerAddresses localhost:9051 --tlsRootCertFiles $PWD/../../organizations/peerOrganizations/ib.example.com/peers/peer0.ib.example.com/tls/ca.crt

CC_PACKAGE_ID=$(peer lifecycle chaincode calculatepackageid ../../policycc_ccaas.tar.gz)
docker rm -f policycc_ccaas 2>/dev/null || true
docker run --rm -d --name policycc_ccaas --network abac-genomic_test \
  -e CHAINCODE_SERVER_ADDRESS=0.0.0.0:9999 \
  -e CORE_CHAINCODE_ID_NAME="$CC_PACKAGE_ID" \
  policycc_ccaas_image:latest
wait_for_docker

echo "=== Déploiement des chaincodes terminé avec succès ==="
