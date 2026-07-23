package main

import (
	"encoding/json"
	"fmt"
	"time"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

type PolicyContract struct {
	contractapi.Contract
}

type ResourcePolicy struct {
	ResourceID        string   `json:"resource_id"`
	OwnerOrg          string   `json:"owner_org"`
	AuthorizedOrgs    []string `json:"authorized_orgs"`
	AllowedActions    []string `json:"allowed_actions"`
	MinClearance      string   `json:"min_clearance"`
	AccessWindowStart string   `json:"access_window_start"`
	AccessWindowEnd   string   `json:"access_window_end"`
}

var clearanceRank = map[string]int{"standard": 1, "elevee": 2, "maximale": 3}

func resourcePolicyKey(ctx contractapi.TransactionContextInterface, resourceID string) (string, error) {
	return ctx.GetStub().CreateCompositeKey("RESPOLICY", []string{resourceID})
}

func (pc *PolicyContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	pol := ResourcePolicy{
		ResourceID: "o2b", OwnerOrg: "IBMSP", AuthorizedOrgs: []string{"IBMSP", "CGNMSP"},
		AllowedActions: []string{"Executer", "Lire"}, MinClearance: "elevee",
		AccessWindowStart: "00:00", AccessWindowEnd: "23:59",
	}
	data, _ := json.Marshal(pol)
	key, _ := resourcePolicyKey(ctx, "o2b")
	return ctx.GetStub().PutState(key, data)
}

func (pc *PolicyContract) GetResourcePolicy(ctx contractapi.TransactionContextInterface, resourceID string) (*ResourcePolicy, error) {
	key, _ := resourcePolicyKey(ctx, resourceID)
	data, err := ctx.GetStub().GetState(key)
	if err != nil || data == nil {
		return nil, fmt.Errorf("politique introuvable pour %s", resourceID)
	}
	var policy ResourcePolicy
	json.Unmarshal(data, &policy)
	return &policy, nil
}

type AttestationResultInput struct {
	AttestationID string `json:"attestation_id"`
	RequesterOrg  string `json:"requester_org"`
	UserID        string `json:"user_id"`
	UserClearance string `json:"user_clearance"`
	ResourceID    string `json:"resource_id"`
	OwnerOrg      string `json:"owner_org"`
	Action        string `json:"action"`
	ProjectID     string `json:"project_id"`
	PatientID     string `json:"patient_id"`
	PrequesterOK  bool   `json:"prequester_ok"`
	PtrustOK      bool   `json:"ptrust_ok"`
	ConsentValid  bool   `json:"consent_valid"`
	Valid         bool   `json:"valid"`
	DenyReason    string `json:"deny_reason"`
	Timestamp     string `json:"timestamp"`
}

type DecisionRecord struct {
	DecisionID          string `json:"decision_id"`
	RequesterOrg        string `json:"requester_org"`
	UserID              string `json:"user_id"`
	OwnerOrg            string `json:"owner_org"`
	ResourceID          string `json:"resource_id"`
	Action              string `json:"action"`
	ProjectID           string `json:"project_id"`
	PatientID           string `json:"patient_id"`
	PrequesterOK        bool   `json:"prequester_ok"`
	PtrustOK            bool   `json:"ptrust_ok"`
	ConsentValid        bool   `json:"consent_valid"`
	OrgAuthorized       bool   `json:"org_authorized"`
	ActionAllowed       bool   `json:"action_allowed"`
	ClearanceSufficient bool   `json:"clearance_sufficient"`
	WithinWindow        bool   `json:"within_window"`
	PownerOK            bool   `json:"powner_ok"`
	Decision            string `json:"decision"`
	DenyReason          string `json:"deny_reason"`
	Timestamp           string `json:"timestamp"`
}

func decisionKey(ctx contractapi.TransactionContextInterface, decisionID string) (string, error) {
	return ctx.GetStub().CreateCompositeKey("DECISION", []string{decisionID})
}

func (pc *PolicyContract) EvaluatePolicy(ctx contractapi.TransactionContextInterface, attestationResultJSON string) (*DecisionRecord, error) {
	var attest AttestationResultInput
	if err := json.Unmarshal([]byte(attestationResultJSON), &attest); err != nil {
		return nil, fmt.Errorf("JSON invalide: %w", err)
	}

	txTimestamp, _ := ctx.GetStub().GetTxTimestamp()
	h := time.Unix(txTimestamp.GetSeconds(), int64(txTimestamp.GetNanos()))

	decision := DecisionRecord{
		DecisionID: attest.AttestationID, RequesterOrg: attest.RequesterOrg, UserID: attest.UserID,
		OwnerOrg: attest.OwnerOrg, ResourceID: attest.ResourceID, Action: attest.Action,
		ProjectID: attest.ProjectID, PatientID: attest.PatientID, PrequesterOK: attest.PrequesterOK,
		PtrustOK: attest.PtrustOK, ConsentValid: attest.ConsentValid,
		Timestamp: h.UTC().Format(time.RFC3339),
	}

	if !attest.Valid {
		decision.Decision = "DENY"
		decision.DenyReason = "ATTESTATION_INVALID"
		return pc.storeDecision(ctx, decision)
	}

	policy, err := pc.GetResourcePolicy(ctx, attest.ResourceID)
	if err != nil {
		decision.Decision = "DENY"
		decision.DenyReason = "POWNER_FAIL : politique introuvable"
		return pc.storeDecision(ctx, decision)
	}

	decision.OrgAuthorized = contains(policy.AuthorizedOrgs, attest.RequesterOrg)
	if !decision.OrgAuthorized {
		decision.Decision = "DENY"; decision.DenyReason = "POWNER_FAIL : Org non autorisée"
		return pc.storeDecision(ctx, decision)
	}

	decision.ActionAllowed = contains(policy.AllowedActions, attest.Action)
	if !decision.ActionAllowed {
		decision.Decision = "DENY"; decision.DenyReason = "POWNER_FAIL : Action non autorisée"
		return pc.storeDecision(ctx, decision)
	}

	decision.ClearanceSufficient = clearanceRank[attest.UserClearance] >= clearanceRank[policy.MinClearance]
	if !decision.ClearanceSufficient {
		decision.Decision = "DENY"; decision.DenyReason = "POWNER_FAIL : Habilitation insuffisante"
		return pc.storeDecision(ctx, decision)
	}

	current := fmt.Sprintf("%02d:%02d", h.UTC().Hour(), h.UTC().Minute())
	decision.WithinWindow = (current >= policy.AccessWindowStart && current <= policy.AccessWindowEnd)
	if !decision.WithinWindow {
		decision.Decision = "DENY"; decision.DenyReason = "POWNER_FAIL : Hors plage horaire"
		return pc.storeDecision(ctx, decision)
	}

	decision.PownerOK = true
	decision.Decision = "PERMIT"
	return pc.storeDecision(ctx, decision)
}

func (pc *PolicyContract) storeDecision(ctx contractapi.TransactionContextInterface, decision DecisionRecord) (*DecisionRecord, error) {
	data, _ := json.Marshal(decision)
	key, _ := decisionKey(ctx, decision.DecisionID)
	ctx.GetStub().PutState(key, data)
	ctx.GetStub().SetEvent("DecisionRecorded", data)
	return &decision, nil
}

func contains(list []string, value string) bool {
	for _, v := range list {
		if v == value { return true }
	}
	return false
}

func main() {
	chaincode, err := contractapi.NewChaincode(&PolicyContract{})
	if err != nil {
		fmt.Printf("Erreur lors de la création du chaincode: %v", err)
		return
	}
	if err := chaincode.Start(); err != nil {
		fmt.Printf("Erreur lors du démarrage du chaincode: %v", err)
	}
}
