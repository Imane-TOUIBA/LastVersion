#!/bin/bash
set -e
cd ~/abac-genomic
export PATH=$HOME/fabric-samples/bin:$PATH
export FABRIC_CFG_PATH=$PWD

ORDERER="orderer.example.com:7050"
ORDERER_CA="/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"

# Configuration des organisations (Dictionnaires Bash)
declare -A ORG_MSP ORG_ADDR ORG_CERT ORG_MSP_PATH
ORG_MSP[CGN]="CGNMSP"; ORG_ADDR[CGN]="peer0.cgn.example.com:7051"; ORG_CERT[CGN]="/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt"; ORG_MSP_PATH[CGN]="/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/cgn.example.com/users/Admin@cgn.example.com/msp"
ORG_MSP[IB]="IBMSP";  ORG_ADDR[IB]="peer0.ib.example.com:9051";  ORG_CERT[IB]="/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/ib.example.com/peers/peer0.ib.example.com/tls/ca.crt";  ORG_MSP_PATH[IB]="/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/ib.example.com/users/Admin@ib.example.com/msp"
ORG_MSP[HU]="HUMSP";  ORG_ADDR[HU]="peer0.hu.example.com:11051"; ORG_CERT[HU]="/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/hu.example.com/peers/peer0.hu.example.com/tls/ca.crt"; ORG_MSP_PATH[HU]="/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/hu.example.com/users/Admin@hu.example.com/msp"

# Fonction helper pour exécuter une commande dans le conteneur CLI avec le contexte d'une org
exec_cli() {
    local msp=$1 addr=$2 cert=$3 msppath=$4
    shift 4
    docker exec -e CORE_PEER_LOCALMSPID="$msp" \
                -e CORE_PEER_ADDRESS="$addr" \
                -e CORE_PEER_TLS_ROOTCERT_FILE="$cert" \
                -e CORE_PEER_MSPCONFIGPATH="$msppath" \
                cli "$@"
}

# ==============================================================================
# FONCTION PRINCIPALE DE DÉPLOIEMENT PARAMÉTRABLE
# Usage: deploy_cc <nom> <version> <sequence> <canal> <chemin_dans_cli> <org1> <org2> ...
# ==============================================================================
deploy_cc() {
    local cc_name=$1
    local cc_version=$2
    local cc_sequence=$3
    local channel=$4
    local cc_path=$5
    shift 5
    local orgs=("$@") # Le reste des arguments sont les noms des orgs (ex: "CGN" "IB")

    echo "========================================================="
    echo "=== Déploiement de $cc_name (v$cc_version, seq $cc_sequence) sur $channel ==="
    echo "=== Organisations ciblées : ${orgs[*]} ==="
    echo "========================================================="

    # 1. Package
    echo "-> 1. Packaging..."
    docker exec cli sh -c "cd $cc_path && peer lifecycle chaincode package ${cc_name}_${cc_version}.tar.gz --path . --lang golang --label ${cc_name}_${cc_version}"

    # 2. Install (uniquement sur les orgs spécifiées)
    echo "-> 2. Installation sur les organisations..."
    for org in "${orgs[@]}"; do
        echo "   Installation sur $org..."
        exec_cli "${ORG_MSP[$org]}" "${ORG_ADDR[$org]}" "${ORG_CERT[$org]}" "${ORG_MSP_PATH[$org]}" \
            peer lifecycle chaincode install "${cc_path}/${cc_name}_${cc_version}.tar.gz"
    done

    # 3. Query Installed (récupération du PACKAGE_ID via la première org)
    echo "-> 3. Récupération du PACKAGE_ID..."
    local first_org="${orgs[0]}"
    export PACKAGE_ID=$(exec_cli "${ORG_MSP[$first_org]}" "${ORG_ADDR[$first_org]}" "${ORG_CERT[$first_org]}" "${ORG_MSP_PATH[$first_org]}" \
        peer lifecycle chaincode queryinstalled | grep "${cc_name}_${cc_version}" | sed -n 's/.*Package ID: \([^,]*\),.*/\1/p')
    echo "   PACKAGE_ID trouvé : $PACKAGE_ID"

    # 4. Approve (uniquement sur les orgs spécifiées)
    echo "-> 4. Approbation par les organisations..."
    for org in "${orgs[@]}"; do
        echo "   Approbation par $org..."
        exec_cli "${ORG_MSP[$org]}" "${ORG_ADDR[$org]}" "${ORG_CERT[$org]}" "${ORG_MSP_PATH[$org]}" \
            peer lifecycle chaincode approveformyorg -o $ORDERER --ordererTLSHostnameOverride orderer.example.com \
            --channelID $channel --name $cc_name --version $cc_version --package-id $PACKAGE_ID --sequence $cc_sequence \
            --tls --cafile $ORDERER_CA
    done

    # 5. Check Commit Readiness
    echo "-> 5. Vérification de la commit readiness..."
    exec_cli "${ORG_MSP[$first_org]}" "${ORG_ADDR[$first_org]}" "${ORG_CERT[$first_org]}" "${ORG_MSP_PATH[$first_org]}" \
        peer lifecycle chaincode checkcommitreadiness --channelID $channel --name $cc_name --version $cc_version --sequence $cc_sequence --output json

    # 6. Commit (construction dynamique des peerAddresses pour les orgs spécifiées)
    echo "-> 6. Commit du chaincode..."
    local commit_cmd="peer lifecycle chaincode commit -o $ORDERER --ordererTLSHostnameOverride orderer.example.com --channelID $channel --name $cc_name --version $cc_version --sequence $cc_sequence --tls --cafile $ORDERER_CA"
    
    for org in "${orgs[@]}"; do
        commit_cmd="$commit_cmd --peerAddresses ${ORG_ADDR[$org]} --tlsRootCertFiles ${ORG_CERT[$org]}"
    done

    # Exécution du commit depuis la première org
    exec_cli "${ORG_MSP[$first_org]}" "${ORG_ADDR[$first_org]}" "${ORG_CERT[$first_org]}" "${ORG_MSP_PATH[$first_org]}" $commit_cmd

    echo "-> 7. SUCCES du déploiement de $cc_name !"
    echo ""
}

# ==============================================================================
# EXÉCUTION DU SCRIPT
# ==============================================================================

echo "=== 0. Préparation des modules Go (go mod tidy) ==="
for cc in consentcc policycc gouvernancecc; do
    cd ~/abac-genomic/chaincodes/$cc
    if [ ! -f go.mod ]; then
        echo "Initialisation de go.mod pour $cc..."
        go mod init $cc
        go get github.com/hyperledger/fabric-contract-api-go/contractapi
        go mod tidy
    else
        echo "Mise à jour des dépendances pour $cc..."
        go mod tidy
    fi
done
cd ~/abac-genomic

# 1. consentcc : global-channel (CGN, IB, HU)
deploy_cc "consentcc" "1.0" "1" "global-channel" "/opt/gopath/src/github.com/chaincodes/consentcc" "CGN" "IB" "HU"

# 2. gouvernancecc : global-channel (CGN, IB, HU)
deploy_cc "gouvernancecc" "1.0" "1" "global-channel" "/opt/gopath/src/github.com/chaincodes/gouvernancecc" "CGN" "IB" "HU"

# 3. policycc : project-channel (CGN, IB UNIQUEMENT - HU est exclu)
deploy_cc "policycc" "1.0" "1" "project-channel" "/opt/gopath/src/github.com/chaincodes/policycc" "CGN" "IB"

echo "=== Initialisation des chaincodes (InitLedger - Flux 2) ==="
# Consentcc Init
exec_cli "${ORG_MSP[CGN]}" "${ORG_ADDR[CGN]}" "${ORG_CERT[CGN]}" "${ORG_MSP_PATH[CGN]}" \
    peer chaincode invoke -o $ORDERER --ordererTLSHostnameOverride orderer.example.com -C global-channel -n consentcc -c '{"function":"InitLedger","Args":[]}' --tls --cafile $ORDERER_CA \
    --peerAddresses "${ORG_ADDR[CGN]}" --tlsRootCertFiles "${ORG_CERT[CGN]}" \
    --peerAddresses "${ORG_ADDR[IB]}" --tlsRootCertFiles "${ORG_CERT[IB]}"

# Gouvernancecc Init
exec_cli "${ORG_MSP[CGN]}" "${ORG_ADDR[CGN]}" "${ORG_CERT[CGN]}" "${ORG_MSP_PATH[CGN]}" \
    peer chaincode invoke -o $ORDERER --ordererTLSHostnameOverride orderer.example.com -C global-channel -n gouvernancecc -c '{"function":"InitLedger","Args":[]}' --tls --cafile $ORDERER_CA \
    --peerAddresses "${ORG_ADDR[CGN]}" --tlsRootCertFiles "${ORG_CERT[CGN]}" \
    --peerAddresses "${ORG_ADDR[IB]}" --tlsRootCertFiles "${ORG_CERT[IB]}"

# Policycc Init
exec_cli "${ORG_MSP[CGN]}" "${ORG_ADDR[CGN]}" "${ORG_CERT[CGN]}" "${ORG_MSP_PATH[CGN]}" \
    peer chaincode invoke -o $ORDERER --ordererTLSHostnameOverride orderer.example.com -C project-channel -n policycc -c '{"function":"InitLedger","Args":[]}' --tls --cafile $ORDERER_CA \
    --peerAddresses "${ORG_ADDR[CGN]}" --tlsRootCertFiles "${ORG_CERT[CGN]}" \
    --peerAddresses "${ORG_ADDR[IB]}" --tlsRootCertFiles "${ORG_CERT[IB]}"

echo "========================================================="
echo "=== SUCCES ! Tous les chaincodes sont déployés et initialisés. ==="
echo "========================================================="
