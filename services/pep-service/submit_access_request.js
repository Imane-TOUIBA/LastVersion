'use strict';
const { connect, hash } = require('@hyperledger/fabric-gateway');
const { newGrpcConnection, newIdentity, newSigner } = require('./connect');
const { evaluatePrequester } = require('./prequester');

async function main() {
    const args = process.argv.slice(2);
    if (args.length < 5) {
        console.log("Usage: node submit_access_request.js <userId> <resourceId> <action> <projectId> <patientId>");
        console.log("Exemple: node submit_access_request.js DrEinstein o2b Executer Oncologie alpha");
        return;
    }
    const [userId, resourceId, action, projectId, patientId] = args;

    console.log(`\n[PEP] Évaluation locale de Prequester pour ${userId} sur le projet ${projectId}...`);
    const prequesterResult = evaluatePrequester(userId, projectId);
    if (!prequesterResult.ok) {
        console.log(`[PEP] REJET LOCAL (Prequester) : ${prequesterResult.reason}`);
        return;
    }
    console.log(`[PEP] Prequester validé. Habilitation détectée : ${prequesterResult.clearance}`);

    console.log("[PEP] Connexion au réseau Fabric (CGNMSP)...");
    const client = await newGrpcConnection();
    const gateway = connect({
        client, identity: await newIdentity(), signer: await newSigner(), hash: hash.sha256,
        evaluateOptions: () => ({ deadline: Date.now() + 5000 }),
        endorseOptions: () => ({ deadline: Date.now() + 15000 }),
        submitOptions: () => ({ deadline: Date.now() + 5000 }),
        commitStatusOptions: () => ({ deadline: Date.now() + 60000 }),
    });

    try {
        const network = gateway.getNetwork('global-channel');
        const contract = network.getContract('gouvernancecc', 'AttestationContract');

        // CORRECTION : requester_org doit correspondre à l'identité MSP du connect.js (CGNMSP)
        const attestation = {
            requester_org: "CGNMSP",
            user_id: userId,
            user_clearance: prequesterResult.clearance,
            resource_id: resourceId,
            action: action,
            project_id: projectId,
            patient_id: patientId,
            prequester_ok: true,
            nonce: Date.now().toString()
        };

        console.log(`[PEP] Soumission de l'attestation à gouvernancecc...`);
        const resultBytes = await contract.submitTransaction('SubmitAttestation', JSON.stringify(attestation));
        const result = JSON.parse(new TextDecoder().decode(resultBytes));

        console.log("\n--- RÉSULTAT DE LA BLOCKCHAIN (global-channel) ---");
        console.log(`Validité globale : ${result.valid}`);
        if (!result.valid) {
            console.log(`Raison du refus : ${result.deny_reason}`);
        } else {
            console.log("✅ Attestation validée ! Le relais Node.js va transmettre à project-channel.");
        }
    } catch (error) {
        console.error("\n[PEP] ERREUR lors de la soumission :", error.message);
        if (error.details) console.error("[PEP] DÉTAILS :", error.details);
    } finally {
        gateway.close();
        client.close();
    }
}

main().catch(console.error);
