// SPDX-License-Identifier: Apache-2.0
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

    function getAssetA() public view returns (address) {
        return address(assetA);
    }

    function getAssetB() public view returns (address) {
        return address(assetB);
    }

    //todo adicionar logica para cancelar dvp, removendo transações do mapping , e/ou expiração das trasnsções..
    //todo criar função para consultar ? faz sentido no cenario privado?
    //todo todo faz sentido emitir eventos no cenario privado?
    //todo dvp atual para transações 1x1
    function addTransaction(
        Harpo.DelegatedTransfer memory newTransaction
    ) public {
        for (uint i = 0; i < newTransaction.inputs.length; i++) {
            transactions[transactionCounter].inputs.push(
                newTransaction.inputs[i]
            );
        }
        for (uint i = 0; i < newTransaction.outputs.length; i++) {
            transactions[transactionCounter].outputs.push(
                newTransaction.outputs[i]
            );
        }
        for (uint i = 0; i < newTransaction.counterpartAsset.length; i++) {
            uint256[] memory innerArray = new uint256[](
                newTransaction.counterpartAsset[i].length
            );
            for (
                uint j = 0;
                j < newTransaction.counterpartAsset[i].length;
                j++
            ) {
                innerArray[j] = newTransaction.counterpartAsset[i][j];
            }
            transactions[transactionCounter].counterpartAsset.push(innerArray);
        }
        for (uint i = 0; i < newTransaction.auditSecret.length; i++) {
            transactions[transactionCounter].auditSecret.push(
                newTransaction.auditSecret[i]
            );
        }

        transactions[transactionCounter].merkleRoot = newTransaction.merkleRoot;
        transactions[transactionCounter].settlementAgent = newTransaction
            .settlementAgent;
        transactions[transactionCounter].proof = newTransaction.proof;
        transactions[transactionCounter].proof1x3 = newTransaction.proof1x3;

        transactionCounter++;
        //evento de trx adicionada aki?
        autoExecuteDVP(transactionCounter - 1);
    }

    function autoExecuteDVP(uint256 newTransactionId) internal {
        Harpo.DelegatedTransfer storage newTx = transactions[newTransactionId];

        for (uint256 i = 0; i < transactionCounter; i++) {
            if (i == newTransactionId) continue; // Pula a transação recém-adicionada

            Harpo.DelegatedTransfer storage existingTx = transactions[i];

            // Verificar se todos os elementos de counterpartAsset têm correspondência em outputs
            if (compareAllSecrets(newTx.counterpartAsset, existingTx.outputs)) {
                executeDVP(i, newTransactionId);
                break;
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
    
    function compareAllSecrets(
        uint256[][] memory counterpartAssets,
        Harpo.Output[] memory outputs
    ) internal returns (bool) {
        // Check if arrays have the same number of elements
        if (counterpartAssets.length != outputs.length) {
            return false;
        }

        // Track which outputs have been matched
        bool[] memory matchedOutputs = new bool[](outputs.length);
        uint256 matchesFound = 0;

        // For each secret in counterpartAssets, find a unique matching output
        for (uint256 i = 0; i < counterpartAssets.length; i++) {
            bool foundMatch = false;

            for (uint256 j = 0; j < outputs.length; j++) {
                // Skip already matched outputs
                if (matchedOutputs[j]) {
                    continue;
                }
                
                // Compare the current secret with the current output
                bool isMatch = compareSecretWithOutput(counterpartAssets[i], outputs[j].secret);
                
                if (isMatch) {
                    // Mark this output as matched
                    matchedOutputs[j] = true;
                    matchesFound++;
                    foundMatch = true;
                    break;  // Move to next counterpart asset after finding a match
                }
            }

            // If no match found for this secret, no need to continue
            if (!foundMatch) {
                return false;
            }
        }

        // Ensure we've matched exactly the same number of elements
        bool finalResult = (matchesFound == counterpartAssets.length);
        return finalResult;
    }

    function compareSecretWithOutput(
        uint256[] memory secret,
        uint256[15] memory outputSecret
    ) internal pure returns (bool) {
        // Verificar se o secret tem o tamanho correto
        if (secret.length != 15) {
            return false;
        }

        // Comparar cada elemento do secret com o outputSecret
        for (uint256 i = 0; i < secret.length; i++) {
            if (secret[i] != outputSecret[i]) {
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
