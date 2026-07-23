package main

import (
	"fmt"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

func main() {
	chaincode, err := contractapi.NewChaincode(&AttestationContract{}, &TrustContract{})
	if err != nil {
		fmt.Printf("Erreur lors de la création du chaincode: %v", err)
		return
	}
	if err := chaincode.Start(); err != nil {
		fmt.Printf("Erreur lors du démarrage du chaincode: %v", err)
	}
}
