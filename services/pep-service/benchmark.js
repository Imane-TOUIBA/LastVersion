'use strict';
const fsSync = require('fs');
const path = require('path');
const crypto = require('crypto');
const { connect, hash } = require('@hyperledger/fabric-gateway');
const { newGrpcConnection, newIdentity, newSigner } = require('./connect');

const CHANNEL = 'global-channel';
const CHAINCODE = 'gouvernancecc';
const CONTRACT = 'AttestationContract';
const RESULTS_DIR = path.join(__dirname, '../../benchmark_results');
const TIMESTAMP = new Date().toISOString().replace(/[:.]/g, '-');

const USERS = ['DrEinstein', 'DrCurie', 'DrSmith', 'DrTuring', 'DrPasteur', 'DrInactive', 'DrUnauthorized'];
const RESOURCES = ['o2b', 'o3c', 'o4d'];
const PATIENTS = ['alpha', 'beta', 'gamma', 'delta'];
const ACTIONS = ['Executer', 'Lire'];

function loadDirectory() {
    const data = fsSync.readFileSync(path.join(__dirname, 'directory.json'), 'utf-8');
    return JSON.parse(data);
}

function evaluatePrequester(userId, projectId) {
    const directory = loadDirectory();
    const user = directory[userId];
    if (!user) return { ok: false, reason: 'Utilisateur inconnu', clearance: null };
    if (!user.active) return { ok: false, reason: 'Compte inactif', clearance: null };
    if (!user.projects.includes(projectId)) return { ok: false, reason: 'Non autorise sur le projet', clearance: null };
    return { ok: true, reason: null, clearance: user.clearance };
}

async function submitAttestation(gateway, userId, resourceId, action, projectId, patientId, prequesterResult) {
    const network = gateway.getNetwork(CHANNEL);
    const contract = network.getContract(CHAINCODE, CONTRACT);
    
    // NONCE UNIQUE OBLIGATOIRE
    const uniqueNonce = 'bench-' + Date.now() + '-' + Math.random().toString(36).substring(2, 10);
    const attestationId = crypto.createHash('sha256').update(uniqueNonce).digest('hex');

    const payload = {
        attestation_id: attestationId,
        requester_org: 'CGNMSP',
        user_id: userId,
        user_clearance: prequesterResult.clearance,
        resource_id: resourceId,
        owner_org: 'IBMSP',
        action: action,
        project_id: projectId,
        patient_id: patientId,
        prequester_ok: prequesterResult.ok,
        nonce: uniqueNonce, // <-- Correction appliquée ici
        timestamp: new Date().toISOString()
    };

    const resultBytes = await contract.submitTransaction('SubmitAttestation', JSON.stringify(payload));
    return JSON.parse(new TextDecoder().decode(resultBytes));
}

async function runBenchmark(totalRequests) {
    fsSync.mkdirSync(RESULTS_DIR, { recursive: true });
    const logFile = path.join(RESULTS_DIR, 'benchmark_' + TIMESTAMP + '.csv');
    fsSync.writeFileSync(logFile, 'id,duration_ms,status,user,resource,patient,reason\n');

    console.log('==========================================');
    console.log('Benchmark ABAC Genomic');
    console.log('Date: ' + new Date().toLocaleString());
    console.log('Nombre de requetes: ' + totalRequests);
    console.log('==========================================\n');

    console.log('[1/3] Connexion au reseau Fabric...');
    const client = await newGrpcConnection();
    const gateway = connect({
        client: client,
        identity: await newIdentity(),
        signer: await newSigner(),
        hash: hash.sha256,
        evaluateOptions: function() { return { deadline: Date.now() + 5000 }; },
        endorseOptions: function() { return { deadline: Date.now() + 15000 }; },
        submitOptions: function() { return { deadline: Date.now() + 5000 }; },
        commitStatusOptions: function() { return { deadline: Date.now() + 60000 }; },
    });
    console.log('[2/3] Connexion etablie. Lancement du benchmark...\n');

    const results = [];
    const startTime = Date.now();

    for (let i = 1; i <= totalRequests; i++) {
        const userId = USERS[Math.floor(Math.random() * USERS.length)];
        const resourceId = RESOURCES[Math.floor(Math.random() * RESOURCES.length)];
        const patientId = PATIENTS[Math.floor(Math.random() * PATIENTS.length)];
        const action = ACTIONS[Math.floor(Math.random() * ACTIONS.length)];

        const reqStart = Date.now();
        let status = 'ERROR';
        let reason = '';

        try {
            const preq = evaluatePrequester(userId, 'Oncologie');
            if (!preq.ok) {
                status = 'REJECTED_LOCAL';
                reason = preq.reason;
            } else {
                const result = await submitAttestation(gateway, userId, resourceId, action, 'Oncologie', patientId, preq);
                if (result.valid === true) {
                    status = 'PERMIT';
                    reason = '';
                } else {
                    status = 'DENY';
                    reason = result.deny_reason || 'Non specifie';
                }
            }
        } catch (error) {
            status = 'ERROR';
            reason = error.message;
        }

        const duration = Date.now() - reqStart;
        results.push({ id: i, duration: duration, status: status, userId: userId, resourceId: resourceId, patientId: patientId, reason: reason });
        fsSync.appendFileSync(logFile, i + ',' + duration + ',' + status + ',' + userId + ',' + resourceId + ',' + patientId + ',"' + reason.replace(/"/g, "'") + '"\n');

        console.log('Requete ' + i + '/' + totalRequests + ': ' + duration + 'ms - ' + status + ' (' + userId + ')');
    }

    const totalTime = Date.now() - startTime;
    gateway.close();
    client.close();

    const stats = {
        total: results.length,
        permit: results.filter(function(r) { return r.status === 'PERMIT'; }).length,
        deny: results.filter(function(r) { return r.status === 'DENY'; }).length,
        rejected_local: results.filter(function(r) { return r.status === 'REJECTED_LOCAL'; }).length,
        error: results.filter(function(r) { return r.status === 'ERROR'; }).length,
    };

    const durations = results.map(function(r) { return r.duration; }).sort(function(a, b) { return a - b; });
    const avg = durations.reduce(function(a, b) { return a + b; }, 0) / durations.length;
    const p50 = durations[Math.floor(durations.length * 0.5)];
    const p95 = durations[Math.floor(durations.length * 0.95)];
    const p99 = durations[Math.floor(durations.length * 0.99)];

    console.log('\n==========================================');
    console.log('Resultats du Benchmark');
    console.log('==========================================');
    console.log('Temps total: ' + totalTime + 'ms');
    console.log('Debit moyen: ' + (stats.total / (totalTime / 1000)).toFixed(2) + ' requetes/seconde');
    console.log('\nDistribution des resultats:');
    console.log('  PERMIT (acces autorise): ' + stats.permit + ' (' + (stats.permit * 100 / stats.total).toFixed(1) + '%)');
    console.log('  DENY (acces refuse blockchain): ' + stats.deny + ' (' + (stats.deny * 100 / stats.total).toFixed(1) + '%)');
    console.log('  REJET LOCAL (fail-fast): ' + stats.rejected_local + ' (' + (stats.rejected_local * 100 / stats.total).toFixed(1) + '%)');
    console.log('  ERREURS: ' + stats.error + ' (' + (stats.error * 100 / stats.total).toFixed(1) + '%)');
    console.log('\nLatence (ms):');
    console.log('  Minimum: ' + durations[0] + 'ms');
    console.log('  Maximum: ' + durations[durations.length - 1] + 'ms');
    console.log('  Moyenne: ' + avg.toFixed(2) + 'ms');
    console.log('  Median (P50): ' + p50 + 'ms');
    console.log('  P95: ' + p95 + 'ms');
    console.log('  P99: ' + p99 + 'ms');
    console.log('\nFichier de resultats: ' + logFile);
    console.log('==========================================');
}

var totalRequests = parseInt(process.argv[2]) || 20;
runBenchmark(totalRequests).catch(function(err) {
    console.error('Erreur fatale:', err);
    process.exit(1);
});
