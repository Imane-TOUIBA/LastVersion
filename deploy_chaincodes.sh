#!/bin/bash
set -e
cd ~/abac-genomic
export PATH=$HOME/fabric-samples/bin:$PATH
export FABRIC_CFG_PATH=$PWD

ORDERER_CA="/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"
ORDERER="orderer.example.com:7050"

# Fonction pour définir l'environnement d'un peer dans le conteneur CLI
set_peer() {
    export ORG_NAME=$1
    export PEER_PORT=$2
    export MSP_ID=$3
}

exec_cli() {
    docker exec -e CORE_PEER_LOCALMSPID=$MSP_ID \
                -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${ORG_NAME}.example.com/users/Admin@${ORG_NAME}.example.com/msp \
                -e CORE_PEER_ADDRESS=peer0.${ORG_NAME}.example.com:$PEER_PORT \
                -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${ORG_NAME}.example.com/peers/peer0.${ORG_NAME}.example.com/tls/ca.crt \
                cli "$@"
}

echo "=== 1. Déploiement de consentcc (global-channel) ==="
exec_cli peer lifecycle chaincode package consentcc.tar.gz --path /opt/gopath/src/github.com/chaincodes/consentcc --lang golang --label consentcc_1.0

for org in "cgn 7051 CGNMSP" "ib 9051 IBMSP" "hu 11051 HUMSP"; do
    set_peer $org
    exec_cli peer lifecycle chaincode install consentcc.tar.gz
done

PACKAGE_ID=$(exec_cli peer lifecycle chaincode queryinstalled | grep "consentcc_1.0" | sed -n 's/.*Package ID: \([^,]*\),.*/\1/p')
echo "Package ID consentcc: $PACKAGE_ID"

for org in "cgn 7051 CGNMSP" "ib 9051 IBMSP" "hu 11051 HUMSP"; do
    set_peer $org
    exec_cli peer lifecycle chaincode approveformyorg -o $ORDERER --ordererTLSHostnameOverride orderer.example.com --channelID global-channel --name consentcc --version 1.0 --package-id $PACKAGE_ID --sequence 1 --tls --cafile $ORDERER_CA
done

exec_cli peer lifecycle chaincode commit -o $ORDERER --ordererTLSHostnameOverride orderer.example.com --channelID global-channel --name consentcc --version 1.0 --sequence 1 --tls --cafile $ORDERER_CA --peerAddresses peer0.cgn.example.com:7051 --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt --peerAddresses peer0.ib.example.com:9051 --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/ib.example.com/peers/peer0.ib.example.com/tls/ca.crt --peerAddresses peer0.hu.example.com:11051 --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/hu.example.com/peers/peer0.hu.example.com/tls/ca.crt

echo "=== 2. Déploiement de gouvernancecc (global-channel) ==="
exec_cli peer lifecycle chaincode package gouvernancecc.tar.gz --path /opt/gopath/src/github.com/chaincodes/gouvernancecc --lang golang --label gouvernancecc_1.0

for org in "cgn 7051 CGNMSP" "ib 9051 IBMSP" "hu 11051 HUMSP"; do
    set_peer $org
    exec_cli peer lifecycle chaincode install gouvernancecc.tar.gz
done

PACKAGE_ID=$(exec_cli peer lifecycle chaincode queryinstalled | grep "gouvernancecc_1.0" | sed -n 's/.*Package ID: \([^,]*\),.*/\1/p')
echo "Package ID gouvernancecc: $PACKAGE_ID"

for org in "cgn 7051 CGNMSP" "ib 9051 IBMSP" "hu 11051 HUMSP"; do
    set_peer $org
    exec_cli peer lifecycle chaincode approveformyorg -o $ORDERER --ordererTLSHostnameOverride orderer.example.com --channelID global-channel --name gouvernancecc --version 1.0 --package-id $PACKAGE_ID --sequence 1 --tls --cafile $ORDERER_CA
done

exec_cli peer lifecycle chaincode commit -o $ORDERER --ordererTLSHostnameOverride orderer.example.com --channelID global-channel --name gouvernancecc --version 1.0 --sequence 1 --tls --cafile $ORDERER_CA --peerAddresses peer0.cgn.example.com:7051 --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt --peerAddresses peer0.ib.example.com:9051 --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/ib.example.com/peers/peer0.ib.example.com/tls/ca.crt --peerAddresses peer0.hu.example.com:11051 --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/hu.example.com/peers/peer0.hu.example.com/tls/ca.crt

echo "=== 3. Déploiement de policycc (project-channel) ==="
exec_cli peer lifecycle chaincode package policycc.tar.gz --path /opt/gopath/src/github.com/chaincodes/policycc --lang golang --label policycc_1.0

for org in "cgn 7051 CGNMSP" "ib 9051 IBMSP"; do
    set_peer $org
    exec_cli peer lifecycle chaincode install policycc.tar.gz
done

PACKAGE_ID=$(exec_cli peer lifecycle chaincode queryinstalled | grep "policycc_1.0" | sed -n 's/.*Package ID: \([^,]*\),.*/\1/p')
echo "Package ID policycc: $PACKAGE_ID"

for org in "cgn 7051 CGNMSP" "ib 9051 IBMSP"; do
    set_peer $org
    exec_cli peer lifecycle chaincode approveformyorg -o $ORDERER --ordererTLSHostnameOverride orderer.example.com --channelID project-channel --name policycc --version 1.0 --package-id $PACKAGE_ID --sequence 1 --tls --cafile $ORDERER_CA
done

exec_cli peer lifecycle chaincode commit -o $ORDERER --ordererTLSHostnameOverride orderer.example.com --channelID project-channel --name policycc --version 1.0 --sequence 1 --tls --cafile $ORDERER_CA --peerAddresses peer0.cgn.example.com:7051 --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt --peerAddresses peer0.ib.example.com:9051 --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/ib.example.com/peers/peer0.ib.example.com/tls/ca.crt

echo "=== 4. Initialisation des chaincodes (Données du Flux 2) ==="
exec_cli peer chaincode invoke -o $ORDERER --ordererTLSHostnameOverride orderer.example.com -C global-channel -n consentcc -c '{"function":"InitLedger","Args":[]}' --tls --cafile $ORDERER_CA --peerAddresses peer0.cgn.example.com:7051 --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt
exec_cli peer chaincode invoke -o $ORDERER --ordererTLSHostnameOverride orderer.example.com -C global-channel -n gouvernancecc -c '{"function":"InitLedger","Args":[]}' --tls --cafile $ORDERER_CA --peerAddresses peer0.cgn.example.com:7051 --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt
exec_cli peer chaincode invoke -o $ORDERER --ordererTLSHostnameOverride orderer.example.com -C project-channel -n policycc -c '{"function":"InitLedger","Args":[]}' --tls --cafile $ORDERER_CA --peerAddresses peer0.cgn.example.com:7051 --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt

echo "=== 5. SUCCES ! Tous les chaincodes sont déployés et initialisés. ==="
