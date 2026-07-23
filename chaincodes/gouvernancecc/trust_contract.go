package main

import (
	"encoding/json"
	"fmt"
	"time"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

type TrustContract struct {
	contractapi.Contract
}

type Convention struct {
	OwnerOrg     string `json:"owner_org"`
	PartnerOrg   string `json:"partner_org"`
	ProjectID    string `json:"project_id"`
	ExpiresAt    string `json:"expires_at"`
	Revoked      bool   `json:"revoked"`
	RevokedAt    string `json:"revoked_at"`
	RegisteredBy string `json:"registered_by"`
}

func convKey(ctx contractapi.TransactionContextInterface, ownerOrg, partnerOrg, projectID string) (string, error) {
	return ctx.GetStub().CreateCompositeKey("CONV", []string{ownerOrg, partnerOrg, projectID})
}

func (tc *TrustContract) RegisterConvention(ctx contractapi.TransactionContextInterface, ownerOrg string, partnerOrg string, projectID string, expiresAt string) error {
	callerMSP, _ := ctx.GetClientIdentity().GetMSPID()
	if callerMSP != ownerOrg {
		return fmt.Errorf("seule l'organisation propriétaire %s peut enregistrer cette convention", ownerOrg)
	}
	conv := Convention{OwnerOrg: ownerOrg, PartnerOrg: partnerOrg, ProjectID: projectID, ExpiresAt: expiresAt, Revoked: false, RegisteredBy: callerMSP}
	key, _ := convKey(ctx, ownerOrg, partnerOrg, projectID)
	data, _ := json.Marshal(conv)
	ctx.GetStub().PutState(key, data)
	return ctx.GetStub().SetEvent("ConventionRegistered", data)
}

func IsConventionValid(ctx contractapi.TransactionContextInterface, ownerOrg string, partnerOrg string, projectID string, h time.Time) (bool, error) {
	key, _ := convKey(ctx, ownerOrg, partnerOrg, projectID)
	data, err := ctx.GetStub().GetState(key)
	if err != nil || data == nil {
		return false, nil
	}
	var conv Convention
	json.Unmarshal(data, &conv)
	if conv.Revoked {
		return false, nil
	}
	expiry, err := time.Parse(time.RFC3339, conv.ExpiresAt)
	if err != nil {
		return false, nil
	}
	return h.Before(expiry), nil
}
