// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;


import {Groth16Verifier_step} from "./verifiers/StepVerify.sol";
/**
 * @title StepSequence
 * @dev Contract to manage step sequence verification
 */

contract StepSequence {

    Groth16Verifier_step internal verifier_step;
    // Mapping from transaction ID to last completed step
    mapping(uint256 => uint256) public transactionSteps;
    
    // Events
    event StepCompleted(uint256 indexed transactionId, uint256 step);
    
    constructor(Groth16Verifier_step _verifier_step) {
        verifier_step = _verifier_step;
    }

    struct Proof1 {
        uint[2] pA;
        uint[2][2] pB;
        uint[2] pC;
        uint[1] inR;
    }
    
    /**
     * @dev Execute a step in the sequence
     * @param transactionId The ID of the transaction
     * @param proof The proof of the step
     */
    function executeStep(
        uint256 transactionId,       
        Proof1 memory proof
    ) public {
        uint256[1] memory pubInputs;
        // Get the last completed step for this transaction
        uint256 lastStep = transactionSteps[transactionId];
        pubInputs[0] = lastStep + 1;
        // Verify that the step is the next in sequence
        require(
            verifier_step.verifyProof(
                proof.pA,
                proof.pB,
                proof.pC,
                pubInputs
            ),
            "Invalid step sequence: must execute steps in order");
        
        // Update the transaction step
        transactionSteps[transactionId] = lastStep + 1;
        
        // Emit event
        emit StepCompleted(transactionId, lastStep + 1);
    }
    
    /**
     * @dev Get the current step for a transaction
     * @param transactionId The ID of the transaction
     * @return The current step
     */
    function getCurrentStep(uint256 transactionId) public view returns (uint256) {
        return transactionSteps[transactionId];
    }
    
    /**
     * @dev Check if a step can be executed
     * @param transactionId The ID of the transaction
     * @param step The step to check
     * @return True if the step can be executed
     */
    function canExecuteStep(uint256 transactionId, uint256 step) public view returns (bool) {
        return step == transactionSteps[transactionId] + 1;
    }
    
    /**
     * @dev Initialize a new transaction with step 0
     * @param transactionId The ID of the transaction
     */
    function initializeTransaction(uint256 transactionId) public {
        require(transactionSteps[transactionId] == 0, "Transaction already initialized");
        // Step 0 is the initialization step
        transactionSteps[transactionId] = 0;
        emit StepCompleted(transactionId, 0);
    }
}
