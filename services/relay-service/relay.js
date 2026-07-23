'use strict';
const { connect, hash, checkpointers, GatewayError } = require('@hyperledger/fabric-gateway');
const grpc = require('@grpc/grpc-js');
const { newGrpcConnection, newIdentity, newSigner } = require('./connect');

const GLOBAL_CHANNEL = 'global-channel';
const PROJECT_CHANNEL = 'project-channel';
const GOVERNANCE_CHAINCODE = 'gouvernancecc';
const POLICY_CHAINCODE = 'policycc';
const ATTESTATION_EVENT_NAME = 'AttestationValidated';
const utf8Decoder = new TextDecoder();

async function main() {
    const client = await newGrpcConnection();
    const gateway = connect({
        client, identity: await newIdentity(), signer: await newSigner(), hash: hash.sha256,
        evaluateOptions: () => ({ deadline: Date.now() + 5000 }),
        endorseOptions: () => ({ deadline: Date.now() + 15000 }),
        submitOptions: () => ({ deadline: Date.now() + 5000 }),
        commitStatusOptions: () => ({ deadline: Date.now() + 60000 }),
    });
    console.log(`[relay] connecté avec l'identité CGNMSP`);

    try {
        const globalNetwork = gateway.getNetwork(GLOBAL_CHANNEL);
        const projectNetwork = gateway.getNetwork(PROJECT_CHANNEL);
        const policyContract = projectNetwork.getContract(POLICY_CHAINCODE);
        await listenAndRelayForever(globalNetwork, policyContract);
    } finally {
        gateway.close();
        client.close();
    }
}

async function listenAndRelayForever(globalNetwork, policyContract) {
    const checkpointer = checkpointers.inMemory();
    while (true) {
        let events;
        try {
            events = await globalNetwork.getChaincodeEvents(GOVERNANCE_CHAINCODE, { checkpoint: checkpointer });
            console.log(`[relay] écoute des événements "${ATTESTATION_EVENT_NAME}" sur ${GLOBAL_CHANNEL}...`);
            for await (const event of events) {
                await handleEvent(event, policyContract, checkpointer);
            }
        } catch (error) {
            if (isCancelledByClose(error)) break;
            console.error('[relay] erreur de connexion, nouvelle tentative dans 5s :', error.message);
            await sleep(5000);
        } finally {
            events?.close();
        }
    }
}

async function handleEvent(event, policyContract, checkpointer) {
    if (event.eventName !== ATTESTATION_EVENT_NAME) {
        await checkpointer.checkpointChaincodeEvent(event);
        return;
    }

    let attestationResult;
    try {
        const rawPayload = utf8Decoder.decode(event.payload);
        console.log('[relay] PAYLOAD BRUT RECU DU CHAINCODE :', rawPayload);
        attestationResult = JSON.parse(rawPayload);
    } catch (parseError) {
        console.error('[relay] impossible de parser le payload, événement ignoré :', parseError.message);
        await checkpointer.checkpointChaincodeEvent(event);
        return;
    }

    // CORRECTION : Adapter aux champs réels de la struct AccessResult en Go
    const isValid = attestationResult.status === "PERMIT";
    const attId = attestationResult.attestation_id || "auto_generated_" + Date.now();

    console.log(`[relay] événement reçu : attestation_id=${attId} valid=${isValid}`);

    if (!isValid) {
        console.log(`[relay] attestation invalide (status: ${attestationResult.status}), non relayée.`);
        await checkpointer.checkpointChaincodeEvent(event);
        return;
    }

    try {
        const attestationResultJSON = JSON.stringify(attestationResult);
        console.log(`[relay] soumission de EvaluatePolicy sur project-channel...`);
        const resultBytes = await policyContract.submitTransaction('EvaluatePolicy', attestationResultJSON);
        const decision = JSON.parse(utf8Decoder.decode(resultBytes));
        console.log(`[relay] décision enregistrée : ${decision.decision}`);
    } catch (submitError) {
        console.error('[relay] échec de soumission à PolicyContract :', submitError.message);
    }
    await checkpointer.checkpointChaincodeEvent(event);
}

function isCancelledByClose(error) {
    return error instanceof GatewayError && error.code === grpc.status.CANCELLED.valueOf();
}

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

main().catch((error) => {
    console.error('[relay] erreur fatale :', error);
    process.exitCode = 1;
});
