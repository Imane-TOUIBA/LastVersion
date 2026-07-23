'use strict';
const express = require('express');
const { connect, hash } = require('@hyperledger/fabric-gateway');
const { newGrpcConnection, newIdentity, newSigner } = require('./connect');

const app = express();
app.use(express.json());

let gateway, contract;

async function initFabric() {
    console.log("[Portail HU] Connexion a Fabric en tant que HUMSP...");
    const client = await newGrpcConnection();
    gateway = connect({
        client, identity: await newIdentity(), signer: await newSigner(), hash: hash.sha256,
        evaluateOptions: () => ({ deadline: Date.now() + 5000 }),
        endorseOptions: () => ({ deadline: Date.now() + 15000 }),
        submitOptions: () => ({ deadline: Date.now() + 5000 }),
        commitStatusOptions: () => ({ deadline: Date.now() + 60000 }),
    });
    const network = gateway.getNetwork('global-channel');
    // CORRECTION : le contrat cible est 'consentcc'
    contract = network.getContract('consentcc');
    console.log("[Portail HU] Connecte et pret a recevoir les requetes.");
}

// 1. Enregistrer un consentement
app.post('/api/consent', async (req, res) => {
    try {
        const { patientId, orgId, resourceId, projectId, expiresAt } = req.body;
        await contract.submitTransaction('RegisterConsent', patientId, orgId, resourceId, projectId, expiresAt);
        res.json({ success: true, message: "Consentement enregistre sur le ledger." });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// 2. Revoquer un consentement
app.delete('/api/consent', async (req, res) => {
    try {
        const { patientId, orgId, resourceId, projectId } = req.body;
        await contract.submitTransaction('RevokeConsent', patientId, orgId, resourceId, projectId);
        res.json({ success: true, message: "Consentement revoque sur le ledger." });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// 3. Consulter un consentement
app.get('/api/consent', async (req, res) => {
    try {
        const { patientId, orgId, resourceId, projectId } = req.query;
        const resultBytes = await contract.evaluateTransaction('GetConsent', patientId, orgId, resourceId, projectId);
        const result = JSON.parse(new TextDecoder().decode(resultBytes));
        res.json({ success: true, data: result });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

const PORT = 3000;
initFabric().then(() => {
    app.listen(PORT, () => console.log(`[Portail HU] Serveur web en ecoute sur http://localhost:${PORT}`));
}).catch(err => {
    console.error("[Portail HU] Erreur fatale d'initialisation :", err);
    process.exit(1);
});
