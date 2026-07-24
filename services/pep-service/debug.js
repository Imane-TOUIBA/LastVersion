'use strict';
const crypto = require('crypto');
const { connect, hash } = require('@hyperledger/fabric-gateway');
const { newGrpcConnection, newIdentity, newSigner } = require('./connect');

async function debug() {
    console.log('Connexion au reseau Fabric...');
    const client = await newGrpcConnection();
    const gateway = connect({
        client: client,
        identity: await newIdentity(),
        signer: await newSigner(),
        hash: hash.sha256,
    });

    const network = gateway.getNetwork('global-channel');
    const contract = network.getContract('gouvernancecc', 'AttestationContract');

    // Génération d'un NONCE unique pour chaque requête
    const uniqueNonce = 'nonce-' + Date.now() + '-' + Math.random().toString(36).substring(2, 10);
    const uniqueId = 'debug-' + Date.now();
    
    const payload = {
        attestation_id: uniqueId,
        requester_org: 'CGNMSP',
        user_id: 'DrEinstein',
        user_clearance: 'elevee',
        resource_id: 'o2b',
        owner_org: 'IBMSP',
        action: 'Executer',
        project_id: 'Oncologie',
        patient_id: 'alpha',
        prequester_ok: true,
        nonce: uniqueNonce, // <-- C'est la ligne qui manquait et qui causait l'erreur !
        timestamp: new Date().toISOString()
    };

    console.log('Payload envoye (avec nonce unique) :');
    console.log(JSON.stringify(payload, null, 2));
    console.log('\nSoumission a SubmitAttestation...');

    try {
        const resultBytes = await contract.submitTransaction('SubmitAttestation', JSON.stringify(payload));
        console.log('\n✅ SUCCES !');
        console.log('Resultat:', JSON.parse(resultBytes.toString()));
    } catch (error) {
        console.log('\n========== ERREUR ==========');
        console.log('Message:', error.message);
        if (error.details) console.log('Details:', JSON.stringify(error.details, null, 2));
        console.log('============================');
    }

    gateway.close();
    client.close();
}

debug().catch(err => {
    console.error('Erreur fatale:', err);
    process.exit(1);
});
