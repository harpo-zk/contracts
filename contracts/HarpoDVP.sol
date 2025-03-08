// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import {Harpo} from "./Harpo.sol";

contract HarpoDVP {    

    event TransferExecuted(
        uint256 indexed transactionId,
        uint256 indexed transactionId2
    );

    mapping(uint256 => Harpo.DelegatedTransfer) public transactions;
    uint256 public transactionCounter;

    Harpo assetA;
    Harpo assetB;
   
    constructor(address _assetAaddress, address _assetBaddress) {
        assetA = Harpo(_assetAaddress);
        assetB = Harpo(_assetBaddress);
    }

    //todo adicionar logica para cancelar dvp, removendo transações do mapping , e/ou expiração das trasnsções..
    //todo criar função para consultar ? faz sentido no cenario privado?
    //todo todo faz sentido emitir eventos no cenario privado?
    //todo dvp atual para transações 1x1
    function addTransaction(Harpo.DelegatedTransfer memory newTransaction) public {
        
        for(uint i = 0; i < newTransaction.inputs.length; i++) {
            transactions[transactionCounter].inputs.push(newTransaction.inputs[i]);
        }
        for(uint i = 0; i < newTransaction.outputs.length; i++) {
            transactions[transactionCounter].outputs.push(newTransaction.outputs[i]);
        }
        for(uint i = 0; i < newTransaction.counterpartAsset.length; i++) {
            transactions[transactionCounter].counterpartAsset.push(newTransaction.counterpartAsset[i]);
        }
        for(uint i = 0; i < newTransaction.auditSecret.length; i++) {
            transactions[transactionCounter].auditSecret.push(newTransaction.auditSecret[i]);
        }

        transactions[transactionCounter].merkleRoot = newTransaction.merkleRoot;
        transactions[transactionCounter].settlementAgent = newTransaction.settlementAgent;
        transactions[transactionCounter].proof = newTransaction.proof;
        
        transactionCounter++;
        //evento de trx adicionada aki?
        autoExecuteDVP(transactionCounter - 1);
    }

    function autoExecuteDVP(uint256 newTransactionId) internal {
        Harpo.DelegatedTransfer storage newTx = transactions[newTransactionId];

        for (uint256 i = 0; i < transactionCounter; i++) {
            if (i == newTransactionId) continue; // Pula a transação recém-adicionada

            Harpo.DelegatedTransfer storage existingTx = transactions[i];
            for (uint256 j = 0; j < existingTx.outputs.length; j++) {
                if (
                    compareSecrets(
                        newTx.counterpartAsset,
                        existingTx.outputs[j].secret
                    )
                ) {
                    executeDVP(i,newTransactionId);//todo ordem dos atributos deve obedecer o asset
                    break;
                }
            }
        }
        //todo  emitir evento de transação adicionada?
    }

    function compareSecrets(
        uint256[] memory a,
        uint256[15] memory b
    ) internal pure returns (bool) {
        if (a.length != b.length) {
            return false;
        }
        for (uint256 i = 0; i < a.length; i++) {
            if (a[i] != b[i]) {
                return false;
            }
        }
        return true;
    }

    function executeDVP(uint256 tx1Id, uint256 tx2Id) internal {
       
        try assetA.processDelegatedTransfer(transactions[tx1Id]) {

            try assetB.processDelegatedTransfer(transactions[tx2Id]) {
                emit TransferExecuted(tx1Id, tx2Id);
            } catch {
                revert("Transfer2 failed, reverting Transfer1");
            }
        } catch {
            revert("Transfer1 failed, reverting transaction");
        }
        
        //todo add status nas trxs pendente executado cancelado?
       
        // Removendo as trxs do mapping
        delete transactions[tx1Id];
        delete transactions[tx2Id];
    }
}
