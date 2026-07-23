#!/usr/bin/env python3
import json

def load_config(f="consortium.json"):
    with open(f, 'r') as file: return json.load(file)

def generate_crypto(config):
    d = config['domain']
    c = "OrdererOrgs:\n  - Name: Orderer\n    Domain: " + d + "\n    Specs:\n      - Hostname: orderer\n        SANS:\n          - localhost\nPeerOrgs:\n"
    for org in config['organizations']:
        c += f"  - Name: {org['name']}\n    Domain: {org['name'].lower()}.{d}\n    EnableNodeOUs: true\n    Template:\n      Count: 1\n      SANS:\n        - localhost\n    Users:\n      Count: 1\n"
    return c

def generate_configtx(config):
    d = config['domain']
    orgs_yaml = ""
    for org in config['organizations']:
        orgs_yaml += f"""  - &{org['name']}Org
    Name: {org['name']}Org
    ID: {org['msp_id']}
    MSPDir: organizations/peerOrganizations/{org['name'].lower()}.{d}/msp
    Policies:
      Readers:
        Type: Signature
        Rule: "OR('{org['msp_id']}.admin', '{org['msp_id']}.peer', '{org['msp_id']}.client')"
      Writers:
        Type: Signature
        Rule: "OR('{org['msp_id']}.admin', '{org['msp_id']}.client')"
      Admins:
        Type: Signature
        Rule: "OR('{org['msp_id']}.admin')"
      Endorsement:
        Type: Signature
        Rule: "OR('{org['msp_id']}.peer')"
    AnchorPeers:
      - Host: {org['peer']['name']}.{org['name'].lower()}.{d}
        Port: {org['peer']['port']}
"""
    gc_orgs = "".join([f"        - *{org}Org\n" for org in ["CGN", "IB", "HU"]])
    pc_orgs = "".join([f"        - *{org}Org\n" for org in ["CGN", "IB"]])

    return f"""Organizations:
  - &OrdererOrg
    Name: OrdererOrg
    ID: OrdererMSP
    MSPDir: organizations/ordererOrganizations/{d}/msp
    Policies:
      Readers:
        Type: Signature
        Rule: "OR('OrdererMSP.member')"
      Writers:
        Type: Signature
        Rule: "OR('OrdererMSP.member')"
      Admins:
        Type: Signature
        Rule: "OR('OrdererMSP.admin')"
    OrdererEndpoints:
      - orderer.{d}:7050
{orgs_yaml}
Capabilities:
  Channel: &ChannelCapabilities
    V2_0: true
  Orderer: &OrdererCapabilities
    V2_0: true
  Application: &ApplicationCapabilities
    V2_0: true

Application: &ApplicationDefaults
  Organizations:
  Policies:
    Readers:
      Type: ImplicitMeta
      Rule: "ANY Readers"
    Writers:
      Type: ImplicitMeta
      Rule: "ANY Writers"
    Admins:
      Type: ImplicitMeta
      Rule: "MAJORITY Admins"
    LifecycleEndorsement:
      Type: ImplicitMeta
      Rule: "MAJORITY Endorsement"
    Endorsement:
      Type: ImplicitMeta
      Rule: "MAJORITY Endorsement"
  Capabilities:
    <<: *ApplicationCapabilities

Orderer: &OrdererDefaults
  OrdererType: etcdraft
  Addresses:
    - orderer.{d}:7050
  EtcdRaft:
    Consenters:
    - Host: orderer.{d}
      Port: 7050
      ClientTLSCert: organizations/ordererOrganizations/{d}/orderers/orderer.{d}/tls/server.crt
      ServerTLSCert: organizations/ordererOrganizations/{d}/orderers/orderer.{d}/tls/server.crt
  BatchTimeout: 2s
  BatchSize:
    MaxMessageCount: 10
    AbsoluteMaxBytes: 99 MB
    PreferredMaxBytes: 512 KB
  Organizations:
  Policies:
    Readers:
      Type: ImplicitMeta
      Rule: "ANY Readers"
    Writers:
      Type: ImplicitMeta
      Rule: "ANY Writers"
    Admins:
      Type: ImplicitMeta
      Rule: "MAJORITY Admins"
    BlockValidation:
      Type: ImplicitMeta
      Rule: "ANY Writers"
  Capabilities:
    <<: *OrdererCapabilities

Channel: &ChannelDefaults
  Policies:
    Readers:
      Type: ImplicitMeta
      Rule: "ANY Readers"
    Writers:
      Type: ImplicitMeta
      Rule: "ANY Writers"
    Admins:
      Type: ImplicitMeta
      Rule: "MAJORITY Admins"
  Capabilities:
    <<: *ChannelCapabilities

Profiles:
  GlobalChannel:
    <<: *ChannelDefaults
    Orderer:
      <<: *OrdererDefaults
      Organizations:
        - *OrdererOrg
    Application:
      <<: *ApplicationDefaults
      Organizations:
{gc_orgs}
  ProjectChannel:
    <<: *ChannelDefaults
    Orderer:
      <<: *OrdererDefaults
      Organizations:
        - *OrdererOrg
    Application:
      <<: *ApplicationDefaults
      Organizations:
{pc_orgs}
"""

def generate_compose(config):
    d = config['domain']
    c = "networks:\n  test:\n    name: abac-genomic_test\n\nservices:\n"
    vols = ["  orderer." + d + ":"]
    
    c += f"""  orderer:
    container_name: orderer.{d}
    image: hyperledger/fabric-orderer:2.5.4
    environment:
      - FABRIC_LOGGING_SPEC=INFO
      - ORDERER_GENERAL_LISTENADDRESS=0.0.0.0
      - ORDERER_GENERAL_LISTENPORT=7050
      - ORDERER_GENERAL_LOCALMSPID=OrdererMSP
      - ORDERER_GENERAL_LOCALMSPDIR=/var/hyperledger/orderer/msp
      - ORDERER_GENERAL_TLS_ENABLED=true
      - ORDERER_GENERAL_TLS_PRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_GENERAL_TLS_CERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_GENERAL_TLS_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
      - ORDERER_GENERAL_CLUSTER_CLIENTCERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_GENERAL_CLUSTER_CLIENTPRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_GENERAL_CLUSTER_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
      - ORDERER_CHANNELPARTICIPATION_ENABLED=true
      - ORDERER_ADMIN_LISTENADDRESS=0.0.0.0:9443
      - ORDERER_ADMIN_TLS_ENABLED=true
      - ORDERER_ADMIN_TLS_CERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_ADMIN_TLS_PRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_ADMIN_TLS_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
      - ORDERER_ADMIN_TLS_CLIENTAUTHREQUIRED=true
      - ORDERER_ADMIN_TLS_CLIENTROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
      - ORDERER_GENERAL_BOOTSTRAPMETHOD=none
    command: orderer
    ports:
      - "7050:7050"
      - "9443:9443"
    volumes:
      - ./organizations/ordererOrganizations/{d}/orderers/orderer.{d}/msp:/var/hyperledger/orderer/msp
      - ./organizations/ordererOrganizations/{d}/orderers/orderer.{d}/tls:/var/hyperledger/orderer/tls
      - orderer.{d}:/var/hyperledger/production/orderer
    networks:
      test:
        aliases:
          - orderer.{d}

"""
    for org in config['organizations']:
        on = org['name'].lower()
        od = on + "." + d
        pn = org['peer']['name'] + "." + od
        cn = "couchdb." + on
        pp, cp, dp = str(org['peer']['port']), str(org['peer']['chaincode_port']), str(org['peer']['couchdb_port'])
        
        c += f"""  peer-{on}:
    container_name: {pn}
    image: hyperledger/fabric-peer:2.5.4
    environment:
      - CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock
      - CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE=abac-genomic_test
      - FABRIC_LOGGING_SPEC=INFO
      - CORE_PEER_TLS_ENABLED=true
      - CORE_PEER_PROFILE_ENABLED=false
      - CORE_PEER_TLS_CERT_FILE=/etc/hyperledger/fabric/tls/server.crt
      - CORE_PEER_TLS_KEY_FILE=/etc/hyperledger/fabric/tls/server.key
      - CORE_PEER_TLS_ROOTCERT_FILE=/etc/hyperledger/fabric/tls/ca.crt
      - CORE_PEER_ID={pn}
      - CORE_PEER_ADDRESS={pn}:{pp}
      - CORE_PEER_LISTENADDRESS=0.0.0.0:{pp}
      - CORE_PEER_CHAINCODEADDRESS={pn}:{cp}
      - CORE_PEER_CHAINCODELISTENADDRESS=0.0.0.0:{cp}
      - CORE_PEER_GOSSIP_BOOTSTRAP={pn}:{pp}
      - CORE_PEER_GOSSIP_EXTERNALENDPOINT={pn}:{pp}
      - CORE_PEER_LOCALMSPID={org['msp_id']}
      - CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/fabric/msp
      - CORE_LEDGER_STATE_STATEDATABASE=CouchDB
      - CORE_LEDGER_STATE_COUCHDBCONFIG_COUCHDBADDRESS={cn}:5984
      - CORE_LEDGER_STATE_COUCHDBCONFIG_USERNAME=admin
      - CORE_LEDGER_STATE_COUCHDBCONFIG_PASSWORD=password
    command: peer node start
    ports:
      - "{pp}:{pp}"
      - "{cp}:{cp}"
    volumes:
      - /var/run/docker.sock:/host/var/run/docker.sock
      - ./organizations/peerOrganizations/{od}/peers/{pn}/msp:/etc/hyperledger/fabric/msp
      - ./organizations/peerOrganizations/{od}/peers/{pn}/tls:/etc/hyperledger/fabric/tls
      - {pn}:/var/hyperledger/production
    networks:
      test:
        aliases:
          - {pn}
    depends_on:
      - couchdb-{on}
      - orderer

  couchdb-{on}:
    container_name: {cn}
    image: couchdb:3.3.2
    environment:
      - COUCHDB_USER=admin
      - COUCHDB_PASSWORD=password
    ports:
      - "{dp}:5984"
    networks:
      - test

"""
        vols.append(f"  {pn}:")

    c += """  cli:
    container_name: cli
    image: hyperledger/fabric-tools:2.5.4
    tty: true
    stdin_open: true
    environment:
      - GOPATH=/opt/gopath
      - CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock
      - FABRIC_LOGGING_SPEC=INFO
      - CORE_PEER_ID=cli
      - CORE_PEER_ADDRESS=peer0.cgn.example.com:7051
      - CORE_PEER_LOCALMSPID=CGNMSP
      - CORE_PEER_TLS_ENABLED=true
      - CORE_PEER_TLS_CERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/server.crt
      - CORE_PEER_TLS_KEY_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/server.key
      - CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/cgn.example.com/peers/peer0.cgn.example.com/tls/ca.crt
      - CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/cgn.example.com/users/Admin@cgn.example.com/msp
    working_dir: /opt/gopath/src/github.com/hyperledger/fabric/peer
    command: /bin/bash
    volumes:
      - /var/run/docker.sock:/host/var/run/docker.sock
      - ./chaincodes:/opt/gopath/src/github.com/chaincodes
      - ./organizations:/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations
      - ./scripts:/opt/gopath/src/github.com/hyperledger/fabric/peer/scripts/
    networks:
      test:
        aliases:
          - cli

volumes:
""" + "\n".join(vols) + "\n"
    return c

if __name__ == "__main__":
    cfg = load_config()
    with open('crypto-config.yaml', 'w') as f: f.write(generate_crypto(cfg))
    with open('configtx.yaml', 'w') as f: f.write(generate_configtx(cfg))
    with open('docker-compose.yaml', 'w') as f: f.write(generate_compose(cfg))
    print("Generation terminee avec succes !")
