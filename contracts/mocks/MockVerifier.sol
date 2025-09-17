// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

/**
 * @title MockVerifier
 * @dev Mock verifier contract for testing that always returns true
 */
contract MockVerifier {
    bool public constant verificationResult = true;
    
    // Mock function that mimics Groth16 verifier interface
    function verifyProof(
        uint[2] memory _pA,
        uint[2][2] memory _pB,
        uint[2] memory _pC,
        uint[] memory _pubSignals
    ) public pure returns (bool) {
        // Suppress unused parameter warnings
        _pA;
        _pB;
        _pC;
        _pubSignals;
        
        return true;
    }
    
    // Overloaded versions for different input sizes
    function verifyProof(
        uint[2] memory _pA,
        uint[2][2] memory _pB,
        uint[2] memory _pC,
        uint[4] memory _pubSignals
    ) public pure returns (bool) {
        _pA; _pB; _pC; _pubSignals;
        return true;
    }
    
    function verifyProof(
        uint[2] memory _pA,
        uint[2][2] memory _pB,
        uint[2] memory _pC,
        uint[12] memory _pubSignals
    ) public pure returns (bool) {
        _pA; _pB; _pC; _pubSignals;
        return true;
    }
    
    function verifyProof(
        uint[2] memory _pA,
        uint[2][2] memory _pB,
        uint[2] memory _pC,
        uint[13] memory _pubSignals
    ) public pure returns (bool) {
        _pA; _pB; _pC; _pubSignals;
        return true;
    }
    
    function verifyProof(
        uint[2] memory _pA,
        uint[2][2] memory _pB,
        uint[2] memory _pC,
        uint[14] memory _pubSignals
    ) public pure returns (bool) {
        _pA; _pB; _pC; _pubSignals;
        return true;
    }
    
    function verifyProof(
        uint[2] memory _pA,
        uint[2][2] memory _pB,
        uint[2] memory _pC,
        uint[16] memory _pubSignals
    ) public pure returns (bool) {
        _pA; _pB; _pC; _pubSignals;
        return true;
    }
}