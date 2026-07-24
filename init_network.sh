#!/bin/bash
# Script d'initialisation des ledgers avec les données de démonstration
# Usage: ./init_network.sh (à exécuter APRÈS ./setup_all.sh et ./deploy_chaincodes.sh)

set -e

echo "=== Initialisation des données du réseau ==="

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

# 1. Initialisation de consentcc
echo "--- Initialisation de consentcc ---"
export CORE_PEER_LOCALMSPID=CGNMSP
export CORE_PEER_ADDRESS=$PEER_CGN
export CORE_PEER_TLS_ROOTCERT_FILE=$TLS_CGN
export CORE_PEER_MSPCONFIGPATH=$PWD/organizations/peerOrganizations/cgn.example.com/users/Admin@cgn.example.com/msp

peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA \
  -C global-channel -n consentcc \
  --peerAddresses $PEER_CGN --tlsRootCertFiles $TLS_CGN \
  --peerAddresses $PEER_IBM --tlsRootCertFiles $TLS_IBM \
  --peerAddresses $PEER_HU --tlsRootCertFiles $TLS_HU \
  --waitForEvent \
  -c '{"function":"InitLedger","Args":[]}'

# 2. Initialisation de gouvernancecc
echo "--- Initialisation de gouvernancecc ---"
peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA \
  -C global-channel -n gouvernancecc \
  --peerAddresses $PEER_CGN --tlsRootCertFiles $TLS_CGN \
  --peerAddresses $PEER_IBM --tlsRootCertFiles $TLS_IBM \
  --peerAddresses $PEER_HU --tlsRootCertFiles $TLS_HU \
  --waitForEvent \
  -c '{"function":"InitLedger","Args":[]}'

# 3. Initialisation de policycc
echo "--- Initialisation de policycc ---"
peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA \
  -C project-channel -n policycc \
  --peerAddresses $PEER_CGN --tlsRootCertFiles $TLS_CGN \
  --peerAddresses $PEER_IBM --tlsRootCertFiles $TLS_IBM \
  --waitForEvent \
  -c '{"function":"InitLedger","Args":[]}'

# 4. Enregistrement de la ressource "o2b"
echo "--- Enregistrement de la ressource o2b ---"
export CORE_PEER_LOCALMSPID=IBMSP
export CORE_PEER_ADDRESS=$PEER_IBM
export CORE_PEER_TLS_ROOTCERT_FILE=$TLS_IBM
export CORE_PEER_MSPCONFIGPATH=$PWD/organizations/peerOrganizations/ib.example.com/users/Admin@ib.example.com/msp

peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA \
  -C global-channel -n gouvernancecc \
  --peerAddresses $PEER_CGN --tlsRootCertFiles $TLS_CGN \
  --peerAddresses $PEER_IBM --tlsRootCertFiles $TLS_IBM \
  --peerAddresses $PEER_HU --tlsRootCertFiles $TLS_HU \
  --waitForEvent \
  -c '{"function":"AttestationContract:RegisterResource","Args":["o2b", "IBMSP", "true", "Oncologie"]}'

# 5. Enregistrement de la convention IBMSP -> CGNMSP
echo "--- Enregistrement de la convention IBMSP -> CGNMSP ---"
peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA \
  -C global-channel -n gouvernancecc \
  --peerAddresses $PEER_CGN --tlsRootCertFiles $TLS_CGN \
  --peerAddresses $PEER_IBM --tlsRootCertFiles $TLS_IBM \
  --peerAddresses $PEER_HU --tlsRootCertFiles $TLS_HU \
  --waitForEvent \
  -c '{"function":"TrustContract:RegisterConvention","Args":["IBMSP", "CGNMSP", "Oncologie", "2030-12-31T23:59:59Z"]}'

# 6. Enregistrement du consentement du patient alpha
echo "--- Enregistrement du consentement du patient alpha ---"
export CORE_PEER_LOCALMSPID=CGNMSP
export CORE_PEER_ADDRESS=$PEER_CGN
export CORE_PEER_TLS_ROOTCERT_FILE=$TLS_CGN
export CORE_PEER_MSPCONFIGPATH=$PWD/organizations/peerOrganizations/cgn.example.com/users/Admin@cgn.example.com/msp

peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA \
  -C global-channel -n consentcc \
  --peerAddresses $PEER_CGN --tlsRootCertFiles $TLS_CGN \
  --peerAddresses $PEER_IBM --tlsRootCertFiles $TLS_IBM \
  --peerAddresses $PEER_HU --tlsRootCertFiles $TLS_HU \
  --waitForEvent \
  -c '{"function":"RegisterConsent","Args":["alpha", "CGNMSP", "o2b", "Oncologie", "2030-12-31"]}'

# 7. Enregistrement de la politique d'accès pour "o2b"
echo "--- Enregistrement de la politique d'accès pour o2b ---"
export CORE_PEER_LOCALMSPID=IBMSP
export CORE_PEER_ADDRESS=$PEER_IBM
export CORE_PEER_TLS_ROOTCERT_FILE=$TLS_IBM
export CORE_PEER_MSPCONFIGPATH=$PWD/organizations/peerOrganizations/ib.example.com/users/Admin@ib.example.com/msp

peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA \
  -C project-channel -n policycc \
  --peerAddresses $PEER_CGN --tlsRootCertFiles $TLS_CGN \
  --peerAddresses $PEER_IBM --tlsRootCertFiles $TLS_IBM \
  --waitForEvent \
  -c '{"function":"RegisterResourcePolicy","Args":["o2b", "IBMSP", "[\"IBMSP\",\"CGNMSP\"]", "[\"Executer\",\"Lire\"]", "elevee", "00:00", "23:59"]}'

echo "=== Initialisation terminée avec succès ==="
