#!/bin/bash
set -e
cd ~/abac-genomic
export PATH=$HOME/fabric-samples/bin:$PATH
export FABRIC_CFG_PATH=$PWD

echo "=== 1. Nettoyage NUCLEAIRE de Docker ==="
docker compose -f docker-compose.yaml down --volumes --remove-orphans 2>/dev/null || true
docker rm -f orderer.example.com peer0.cgn.example.com peer0.ib.example.com peer0.hu.example.com cli couchdb.cgn couchdb.ib couchdb.hu 2>/dev/null || true
docker network rm abac-genomic_test 2>/dev/null || true
docker volume prune -f
rm -rf organizations channel-artifacts

echo "=== 2. Generation des fichiers de configuration ==="
python3 generate_network.py

echo "=== 3. Generation des certificats ==="
mkdir -p organizations
cryptogen generate --config=./crypto-config.yaml --output="organizations"

echo "=== 4. Generation des artefacts de canal ==="
mkdir -p channel-artifacts
configtxgen -profile GlobalChannel -outputBlock ./channel-artifacts/global-channel.block -channelID global-channel
configtxgen -profile ProjectChannel -outputBlock ./channel-artifacts/project-channel.block -channelID project-channel

echo "=== 5. Demarrage du reseau ==="
docker compose -f docker-compose.yaml up -d
echo "Attente de 15 secondes pour le demarrage des conteneurs..."
sleep 15

echo "=== 6. Verification de l'etat de l'Orderer ==="
if ! docker ps --format '{{.Names}}' | grep -q "^orderer.example.com$"; then
    echo "ERREUR CRITIQUE : L'Orderer a plante au demarrage !"
    docker logs --tail 50 orderer.example.com
    exit 1
fi
echo "L'Orderer est en cours d'execution (Up)."

echo "=== 7. Contournement du bug DNS de Docker (Injection /etc/hosts) ==="
ORDERER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' orderer.example.com)
PEER_CGN_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' peer0.cgn.example.com)

docker exec cli sh -c "echo '$ORDERER_IP orderer.example.com' >> /etc/hosts"
docker exec cli sh -c "echo '$PEER_CGN_IP peer0.cgn.example.com' >> /etc/hosts"
echo "DNS contourne avec succes."

echo "=== 8. Creation et jointure des canaux (via osnadmin sur le port 9443) ==="
exec_peer() {
    docker exec -e CORE_PEER_LOCALMSPID=$3 \
                -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${1}.example.com/users/Admin@${1}.example.com/msp \
                -e CORE_PEER_ADDRESS=peer0.${1}.example.com:$2 \
                -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/${1}.example.com/peers/peer0.${1}.example.com/tls/ca.crt \
                cli $4
}

# Copie des blocs dans le conteneur CLI
docker cp ./channel-artifacts/global-channel.block cli:/opt/gopath/src/github.com/hyperledger/fabric/peer/global-channel.block
docker cp ./channel-artifacts/project-channel.block cli:/opt/gopath/src/github.com/hyperledger/fabric/peer/project-channel.block

# CORRECTION FINALE : Utilisation du port d'administration 9443 pour l'API REST osnadmin
echo "-> Creation de global-channel sur l'Orderer (port 9443)..."
docker exec cli osnadmin channel join \
    --channelID global-channel \
    --config-block ./global-channel.block \
    -o orderer.example.com:9443 \
    --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/ca.crt \
    --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/server.crt \
    --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/server.key

echo "-> Jointure de global-channel par les peers (CGN, IB, HU)..."
exec_peer "cgn" "7051" "CGNMSP" "peer channel join -b global-channel.block"
exec_peer "ib" "9051" "IBMSP" "peer channel join -b global-channel.block"
exec_peer "hu" "11051" "HUMSP" "peer channel join -b global-channel.block"

echo "-> Creation de project-channel sur l'Orderer (port 9443)..."
docker exec cli osnadmin channel join \
    --channelID project-channel \
    --config-block ./project-channel.block \
    -o orderer.example.com:9443 \
    --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/ca.crt \
    --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/server.crt \
    --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/server.key

echo "-> Jointure de project-channel par les peers (CGN, IB)..."
exec_peer "cgn" "7051" "CGNMSP" "peer channel join -b project-channel.block"
exec_peer "ib" "9051" "IBMSP" "peer channel join -b project-channel.block"

echo "========================================================="
echo "=== 9. SUCCES ! Reseau initialise avec succes. ==="
echo "========================================================="
docker ps --format "table {{.Names}}\t{{.Status}}"
