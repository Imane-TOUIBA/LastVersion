'use strict';
const grpc = require('@grpc/grpc-js');
const { signers } = require('@hyperledger/fabric-gateway');
const crypto = require('crypto');
const fs = require('fs').promises;
const path = require('path');

const MSP_ID = 'HUMSP';
const CRYPTO_PATH = '/home/itouiba/abac-genomic/organizations/peerOrganizations/hu.example.com';
const KEY_DIRECTORY_PATH = path.join(CRYPTO_PATH, 'users', 'Admin@hu.example.com', 'msp', 'keystore');
const CERT_DIRECTORY_PATH = path.join(CRYPTO_PATH, 'users', 'Admin@hu.example.com', 'msp', 'signcerts');
const TLS_CERT_PATH = path.join(CRYPTO_PATH, 'peers', 'peer0.hu.example.com', 'tls', 'ca.crt');
const PEER_ENDPOINT = 'localhost:11051';
const PEER_HOST_ALIAS = 'peer0.hu.example.com';

async function newGrpcConnection() {
    const tlsRootCert = await fs.readFile(TLS_CERT_PATH);
    const tlsCredentials = grpc.credentials.createSsl(tlsRootCert);
    return new grpc.Client(PEER_ENDPOINT, tlsCredentials, { 'grpc.ssl_target_name_override': PEER_HOST_ALIAS });
}
async function newIdentity() {
    const files = await fs.readdir(CERT_DIRECTORY_PATH);
    const certFile = files.find(f => f.endsWith('.pem')) || files[0];
    return { mspId: MSP_ID, credentials: await fs.readFile(path.join(CERT_DIRECTORY_PATH, certFile)) };
}
async function newSigner() {
    const files = await fs.readdir(KEY_DIRECTORY_PATH);
    const keyFile = files.find(f => f.endsWith('_sk')) || files[0];
    return signers.newPrivateKeySigner(crypto.createPrivateKey(await fs.readFile(path.join(KEY_DIRECTORY_PATH, keyFile))));
}
module.exports = { newGrpcConnection, newIdentity, newSigner, MSP_ID };
