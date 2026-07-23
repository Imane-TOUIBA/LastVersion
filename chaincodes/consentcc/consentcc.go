package main

import (
	"encoding/json"
	"fmt"
	"time"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

type ConsentContract struct {
	contractapi.Contract
}

type ConsentRecord struct {
	PatientID  string `json:"patient_id"`
	OrgID      string `json:"org_id"`
	ResourceID string `json:"resource_id"`
	ProjectID  string `json:"project_id"`
	Status     string `json:"status"`
	ExpiresAt  string `json:"expires_at"`
	RevokedAt  string `json:"revoked_at"`
}

func consentKey(ctx contractapi.TransactionContextInterface, patientID, orgID, resourceID, projectID string) (string, error) {
	return ctx.GetStub().CreateCompositeKey("CONSENT", []string{patientID, orgID, resourceID, projectID})
}

func (c *ConsentContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	consents := []ConsentRecord{
		{PatientID: "alpha", OrgID: "CGNMSP", ResourceID: "o2b", ProjectID: "Oncologie", Status: "actif", ExpiresAt: "2030-12-31"},
	}
	for _, consent := range consents {
		key, err := consentKey(ctx, consent.PatientID, consent.OrgID, consent.ResourceID, consent.ProjectID)
		if err != nil { return err }
		data, err := json.Marshal(consent)
		if err != nil { return err }
		if err := ctx.GetStub().PutState(key, data); err != nil {
			return fmt.Errorf("failed to put to world state: %v", err)
		}
	}
	return nil
}

func (c *ConsentContract) RegisterConsent(ctx contractapi.TransactionContextInterface, patientID, orgID, resourceID, projectID, expiresAt string) error {
	callerMSP, _ := ctx.GetClientIdentity().GetMSPID()
	if callerMSP != orgID {
		return fmt.Errorf("seule l'organisation %s peut enregistrer ce consentement, appel reçu de %s", orgID, callerMSP)
	}
	
	consent := ConsentRecord{
		PatientID: patientID, OrgID: orgID, ResourceID: resourceID,
		ProjectID: projectID, Status: "actif", ExpiresAt: expiresAt,
	}
	key, err := consentKey(ctx, patientID, orgID, resourceID, projectID)
	if err != nil { return err }
	data, err := json.Marshal(consent)
	if err != nil { return err }
	
	if err := ctx.GetStub().PutState(key, data); err != nil { return err }
	return ctx.GetStub().SetEvent("ConsentRegistered", data)
}

func (c *ConsentContract) RevokeConsent(ctx contractapi.TransactionContextInterface, patientID, orgID, resourceID, projectID string) error {
	callerMSP, _ := ctx.GetClientIdentity().GetMSPID()
	if callerMSP != orgID {
		return fmt.Errorf("seule l'organisation %s peut révoquer ce consentement, appel reçu de %s", orgID, callerMSP)
	}

	key, err := consentKey(ctx, patientID, orgID, resourceID, projectID)
	if err != nil { return err }

	data, err := ctx.GetStub().GetState(key)
	if err != nil || data == nil {
		return fmt.Errorf("consentement introuvable pour le patient %s", patientID)
	}

	var consent ConsentRecord
	if err := json.Unmarshal(data, &consent); err != nil {
		return err
	}

	if consent.Status == "revoque" {
		return fmt.Errorf("ce consentement est déjà révoqué")
	}

	consent.Status = "revoque"
	txTimestamp, _ := ctx.GetStub().GetTxTimestamp()
	now := time.Unix(txTimestamp.GetSeconds(), int64(txTimestamp.GetNanos()))
	consent.RevokedAt = now.UTC().Format(time.RFC3339)

	updatedData, err := json.Marshal(consent)
	if err != nil { return err }

	if err := ctx.GetStub().PutState(key, updatedData); err != nil { return err }
	
	return ctx.GetStub().SetEvent("ConsentRevoked", updatedData)
}

func (c *ConsentContract) CheckConsent(ctx contractapi.TransactionContextInterface, patientID, orgID, resourceID, projectID string) (bool, error) {
	key, err := consentKey(ctx, patientID, orgID, resourceID, projectID)
	if err != nil { return false, err }
	
	data, err := ctx.GetStub().GetState(key)
	if err != nil || data == nil { return false, nil }
	
	var consent ConsentRecord
	if err := json.Unmarshal(data, &consent); err != nil { return false, err }
	
	if consent.Status != "actif" {
		return false, nil
	}
	if consent.ExpiresAt != "" {
		expiry, err := time.Parse("2006-01-02", consent.ExpiresAt)
		if err == nil && time.Now().After(expiry) {
			return false, nil
		}
	}
	return true, nil
}

func (c *ConsentContract) VerifyConsent(ctx contractapi.TransactionContextInterface, patientID, org, resource, action, project, currentTime string) (bool, error) {
	return c.CheckConsent(ctx, patientID, org, resource, project)
}

// FONCTION MAIN AJOUTÉE : Indispensable pour compiler le chaincode
func main() {
	chaincode, err := contractapi.NewChaincode(&ConsentContract{})
	if err != nil {
		fmt.Printf("Error creating consentcc chaincode: %v", err)
		return
	}
	if err := chaincode.Start(); err != nil {
		fmt.Printf("Error starting consentcc chaincode: %v", err)
	}
}
