package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"time"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

type AttestationContract struct {
	contractapi.Contract
}

type ResourceDefinition struct {
	ResourceID      string `json:"resource_id"`
	OwnerOrg        string `json:"owner_org"`
	ConsentRequired bool   `json:"consent_required"`
	ProjectID       string `json:"project_id"`
}

func resourceKey(ctx contractapi.TransactionContextInterface, resourceID string) (string, error) {
	return ctx.GetStub().CreateCompositeKey("RES", []string{resourceID})
}

func (ac *AttestationContract) RegisterResource(ctx contractapi.TransactionContextInterface, resourceID string, ownerOrg string, consentRequired bool, projectID string) error {
	callerMSP, _ := ctx.GetClientIdentity().GetMSPID()
	if callerMSP != ownerOrg {
		return fmt.Errorf("RegisterResource : seule l'organisation propriétaire %s peut enregistrer cette ressource", ownerOrg)
	}
	res := ResourceDefinition{ResourceID: resourceID, OwnerOrg: ownerOrg, ConsentRequired: consentRequired, ProjectID: projectID}
	key, _ := resourceKey(ctx, resourceID)
	data, _ := json.Marshal(res)
	return ctx.GetStub().PutState(key, data)
}

func (ac *AttestationContract) GetResource(ctx contractapi.TransactionContextInterface, resourceID string) (*ResourceDefinition, error) {
	key, _ := resourceKey(ctx, resourceID)
	data, err := ctx.GetStub().GetState(key)
	if err != nil || data == nil {
		return nil, fmt.Errorf("ressource %s introuvable", resourceID)
	}
	var res ResourceDefinition
	json.Unmarshal(data, &res)
	return &res, nil
}

type RequesterAttestation struct {
	RequesterOrg  string `json:"requester_org"`
	UserID        string `json:"user_id"`
	UserClearance string `json:"user_clearance"`
	ResourceID    string `json:"resource_id"`
	Action        string `json:"action"`
	ProjectID     string `json:"project_id"`
	PatientID     string `json:"patient_id"`
	PrequesterOK  bool   `json:"prequester_ok"`
	Nonce         string `json:"nonce"`
}

type AttestationResult struct {
	AttestationID   string `json:"attestation_id"`
	RequesterOrg    string `json:"requester_org"`
	UserID          string `json:"user_id"`
	UserClearance   string `json:"user_clearance"`
	ResourceID      string `json:"resource_id"`
	OwnerOrg        string `json:"owner_org"`
	Action          string `json:"action"`
	ProjectID       string `json:"project_id"`
	PatientID       string `json:"patient_id"`
	PrequesterOK    bool   `json:"prequester_ok"`
	PtrustOK        bool   `json:"ptrust_ok"`
	ConsentRequired bool   `json:"consent_required"`
	ConsentValid    bool   `json:"consent_valid"`
	Valid           bool   `json:"valid"`
	DenyReason      string `json:"deny_reason"`
	Timestamp       string `json:"timestamp"`
}

func attestationKey(ctx contractapi.TransactionContextInterface, attestationID string) (string, error) {
	return ctx.GetStub().CreateCompositeKey("ATTEST", []string{attestationID})
}

func usedNonceKey(ctx contractapi.TransactionContextInterface, requesterOrg, nonce string) (string, error) {
	return ctx.GetStub().CreateCompositeKey("NONCE", []string{requesterOrg, nonce})
}

func (ac *AttestationContract) SubmitAttestation(ctx contractapi.TransactionContextInterface, attestationJSON string) (*AttestationResult, error) {
	var attest RequesterAttestation
	if err := json.Unmarshal([]byte(attestationJSON), &attest); err != nil {
		return nil, fmt.Errorf("JSON invalide: %w", err)
	}

	callerMSP, _ := ctx.GetClientIdentity().GetMSPID()
	if callerMSP != attest.RequesterOrg {
		return nil, fmt.Errorf("MSP mismatch: attendu %s, reçu %s", attest.RequesterOrg, callerMSP)
	}

	nKey, _ := usedNonceKey(ctx, attest.RequesterOrg, attest.Nonce)
	existingNonce, _ := ctx.GetStub().GetState(nKey)
	if existingNonce != nil {
		return nil, fmt.Errorf("nonce déjà utilisé")
	}
	ctx.GetStub().PutState(nKey, []byte("used"))

	txTimestamp, _ := ctx.GetStub().GetTxTimestamp()
	h := time.Unix(txTimestamp.GetSeconds(), int64(txTimestamp.GetNanos()))
	txID := ctx.GetStub().GetTxID()
	attestationID := fmt.Sprintf("%x", sha256.Sum256([]byte(txID+attest.ResourceID+attest.UserID)))

	result := AttestationResult{
		AttestationID: attestationID, RequesterOrg: attest.RequesterOrg, UserID: attest.UserID,
		UserClearance: attest.UserClearance, ResourceID: attest.ResourceID, Action: attest.Action,
		ProjectID: attest.ProjectID, PatientID: attest.PatientID, PrequesterOK: attest.PrequesterOK,
		Timestamp: h.UTC().Format(time.RFC3339), Valid: false,
	}

	if !attest.PrequesterOK {
		result.DenyReason = "PREQUESTER_FAIL"
		return ac.storeAndEmit(ctx, result)
	}

	res, err := ac.GetResource(ctx, attest.ResourceID)
	if err != nil {
		return nil, fmt.Errorf("SubmitAttestation : %w", err)
	}
	result.OwnerOrg = res.OwnerOrg
	result.ConsentRequired = res.ConsentRequired

	ptrustOK, _ := IsConventionValid(ctx, res.OwnerOrg, attest.RequesterOrg, attest.ProjectID, h)
	result.PtrustOK = ptrustOK
	if !ptrustOK {
		result.DenyReason = "PTRUST_FAIL"
		return ac.storeAndEmit(ctx, result)
	}

	if res.ConsentRequired {
		if attest.PatientID == "" {
			result.DenyReason = "CONSENT_FAIL : patient_id manquant"
			return ac.storeAndEmit(ctx, result)
		}
		consentArgs := [][]byte{[]byte("CheckConsent"), []byte(attest.PatientID), []byte(attest.RequesterOrg), []byte(attest.ResourceID), []byte(attest.ProjectID)}
		response := ctx.GetStub().InvokeChaincode("consentcc", consentArgs, "global-channel")
		var consentOK bool
		if response.Status == 200 {
			json.Unmarshal(response.Payload, &consentOK)
		}
		result.ConsentValid = consentOK
		if !consentOK {
			result.DenyReason = "CONSENT_FAIL"
			return ac.storeAndEmit(ctx, result)
		}
	} else {
		result.ConsentValid = true
	}

	result.Valid = true
	return ac.storeAndEmit(ctx, result)
}

func (ac *AttestationContract) storeAndEmit(ctx contractapi.TransactionContextInterface, result AttestationResult) (*AttestationResult, error) {
	data, _ := json.Marshal(result)
	key, _ := attestationKey(ctx, result.AttestationID)
	ctx.GetStub().PutState(key, data)
	ctx.GetStub().SetEvent("AttestationValidated", data)
	return &result, nil
}
