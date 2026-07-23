#!/bin/bash
set -e
export PATH=$HOME/fabric-samples/bin:$PATH
export FABRIC_CFG_PATH=$PWD

echo "=== 1. Nettoyage ==="
docker compose -f docker-compose.yaml down --volumes --remove-orphans 2>/dev/null || true
rm -rf organizations channel-artifacts

echo "=== 2. Certificats ==="
mkdir -p organizations
cryptogen generate --config=./crypto-config.yaml --output="organizations"

echo "=== 3. Artefacts de canal ==="
mkdir -p channel-artifacts
configtxgen -profile GlobalChannel -outputBlock ./channel-artifacts/global-channel.block -channelID global-channel
configtxgen -profile ProjectChannel -outputBlock ./channel-artifacts/project-channel.block -channelID project-channel

echo "=== 4. Demarrage ==="
docker compose -f docker-compose.yaml up -d
echo "Attente de 15 secondes..."
sleep 15

echo "=== 5. Contournement DNS (Injection /etc/hosts) ==="
# Récupérer les IP réelles des conteneurs
ORDERER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' orderer.example.com)
PEER_CGN_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' peer0.cgn.example.com)

echo "Injection de l'IP de l'Orderer ($ORDERER_IP) dans le conteneur cli..."
docker exec cli sh -c "echo '$ORDERER_IP orderer.example.com' >> /etc/hosts"
docker exec cli sh -c "echo '$PEER_CGN_IP peer0.cgn.example.com' >> /etc/hosts"

# Vérification que la résolution fonctionne maintenant
echo "Test de résolution depuis le conteneur cli :"
docker exec cli ping -c 1 orderer.example.com || true

echo "=== 6. Creation et jointure des canaux ==="
exec_peer() {
    docker exec -e CORE_PEER_LOCALMSPID=$3 \
                -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${1}.example.com/users/Admin@${1}.example.com/msp \
                -e CORE_PEER_ADDRESS=peer0.${1}.example.com:$2 \
                -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${1}.example.com/peers/peer0.${1}.example.com/tls/ca.crt \
                cli $4
}

CA_FILE="/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"
ORDERER="orderer.example.com:7050"

docker cp ./channel-artifacts/global-channel.block cli:/opt/gopath/src/github.com/hyperledger/fabric/peer/global-channel.block
docker cp ./channel-artifacts/project-channel.block cli:/opt/gopath/src/github.com/hyperledger/fabric/peer/project-channel.block

echo "-> Creation de global-channel par CGN..."
exec_peer "cgn" "7051" "CGNMSP" "peer channel create -c global-channel -o $ORDERER --outputBlock ./global-channel.block --tls --cafile $CA_FILE"

echo "-> CGN rejoint global-channel..."
exec_peer "cgn" "7051" "CGNMSP" "peer channel join -b global-channel.block"
echo "-> IB rejoint global-channel..."
exec_peer "ib" "9051" "IBMSP" "peer channel join -b global-channel.block"
echo "-> HU rejoint global-channel..."
exec_peer "hu" "11051" "HUMSP" "peer channel join -b global-channel.block"

echo "-> Creation de project-channel par CGN..."
exec_peer "cgn" "7051" "CGNMSP" "peer channel create -c project-channel -o $ORDERER --outputBlock ./project-channel.block --tls --cafile $CA_FILE"

echo "-> CGN rejoint project-channel..."
exec_peer "cgn" "7051" "CGNMSP" "peer channel join -b project-channel.block"
echo "-> IB rejoint project-channel..."
exec_peer "ib" "9051" "IBMSP" "peer channel join -b project-channel.block"

echo "=== 7. Reseau initialise avec succes ! ==="
docker ps --format "table {{.Names}}\t{{.Status}}"
