package main

import (
	"encoding/json"
	"fmt"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

type Consent struct {
	PatientID string `json:"patientID"`
	Org       string `json:"org"`
	Resource  string `json:"resource"`
	Action    string `json:"action"`
	Project   string `json:"project"`
	Status    string `json:"status"`
	Expiry    string `json:"expiry"`
}

type ConsentContract struct {
	contractapi.Contract
}

func (c *ConsentContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	consents := []Consent{
		{PatientID: "α", Org: "IB", Resource: "o2b", Action: "Exécuter", Project: "Oncologie", Status: "actif", Expiry: "2030-12-31"},
		{PatientID: "β", Org: "IB", Resource: "o2b", Action: "Exécuter", Project: "Oncologie", Status: "actif", Expiry: "2030-12-31"},
		{PatientID: "γ", Org: "*", Resource: "*", Action: "*", Project: "*", Status: "révoqué", Expiry: "2000-01-01"},
	}
	for _, cons := range consents {
		consJSON, err := json.Marshal(cons)
		if err != nil {
			return err
		}
		key := "CONSENT_" + cons.PatientID + "_" + cons.Org + "_" + cons.Resource
		if err := ctx.GetStub().PutState(key, consJSON); err != nil {
			return fmt.Errorf("failed to put to world state: %v", err)
		}
	}
	return nil
}

func (c *ConsentContract) VerifyConsent(ctx contractapi.TransactionContextInterface, patientID, org, resource, action, project, currentTime string) (bool, error) {
	key := "CONSENT_" + patientID + "_" + org + "_" + resource
	consentJSON, err := ctx.GetStub().GetState(key)
	
	if err != nil || len(consentJSON) == 0 {
		key = "CONSENT_" + patientID + "_*_*"
		consentJSON, err = ctx.GetStub().GetState(key)
	}
	
	if err != nil || len(consentJSON) == 0 {
		return false, fmt.Errorf("consent not found for patient %s", patientID)
	}

	var consent Consent
	if err := json.Unmarshal(consentJSON, &consent); err != nil {
		return false, err
	}

	if consent.Status != "actif" {
		return false, nil
	}
	if currentTime > consent.Expiry {
		return false, nil
	}
	return true, nil
}

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
