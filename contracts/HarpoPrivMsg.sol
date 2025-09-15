// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import {Groth16Verifier_priv_msg_1} from "./verifiers/PrivMsgVerify1.sol";
import {Groth16Verifier_priv_msg_2} from "./verifiers/PrivMsgVerify2.sol";
import {Groth16Verifier_priv_msg_3} from "./verifiers/PrivMsgVerify3.sol";
import {PoseidonT4} from "./libs/PoseidonT4.sol";
import {PoseidonT6} from "./libs/PoseidonT6.sol";

contract HarpoPrivMsg {
    Groth16Verifier_priv_msg_1 internal verifier_priv_msg_1;
    Groth16Verifier_priv_msg_2 internal verifier_priv_msg_2;
    Groth16Verifier_priv_msg_3 internal verifier_priv_msg_3;

    constructor(
        Groth16Verifier_priv_msg_1 _verifier_priv_msg_1,
        Groth16Verifier_priv_msg_2 _verifier_priv_msg_2,
        Groth16Verifier_priv_msg_3 _verifier_priv_msg_3
    ) {
        verifier_priv_msg_1 = _verifier_priv_msg_1;
        verifier_priv_msg_2 = _verifier_priv_msg_2;
        verifier_priv_msg_3 = _verifier_priv_msg_3;
    }
      
    struct Proof {
        uint[2] pA;
        uint[2][2] pB;
        uint[2] pC;
    }
    
    event PrivateMessageEmitted(uint256[15] secret);
    
    struct PrivateMessage {
        uint256[15][] secrets; 
        Proof proof;
    }

    function processPrivateMessage(PrivateMessage memory message) public {
        require(message.secrets.length >= 1 && message.secrets.length <= 3, "Numero de segredos deve ser entre 1 e 3");

        // Gera commitments para cada segredo
        uint256[] memory commitments = new uint256[](message.secrets.length);
        for(uint i = 0; i < message.secrets.length; i++) {
            commitments[i] = _hashSecret(message.secrets[i]);
        }

        bool proofValid;
        
        // Verifica a prova baseada no tipo
        if(message.secrets.length == 1) {            
            uint256[1] memory pubInputs;
            pubInputs[0] = commitments[0];
            
            proofValid = verifier_priv_msg_1.verifyProof(
                message.proof.pA,
                message.proof.pB,
                message.proof.pC,
                pubInputs
            );
        } else if(message.secrets.length == 2) {
            uint256[2] memory pubInputs;
            pubInputs[0] = commitments[0];
            pubInputs[1] = commitments[1];
            proofValid = verifier_priv_msg_2.verifyProof(
                message.proof.pA,
                message.proof.pB,
                message.proof.pC,
                pubInputs
            );
        } else if(message.secrets.length == 3) {
            uint256[3] memory pubInputs;
            pubInputs[0] = commitments[0];
            pubInputs[1] = commitments[1];
            pubInputs[2] = commitments[2];
            proofValid = verifier_priv_msg_3.verifyProof(
                message.proof.pA,
                message.proof.pB,
                message.proof.pC,
                pubInputs
            );
        } else {
            revert("Combinacao invalida de tipo de prova e numero de segredos");
        }
        
        require(proofValid, "Prova invalida para mensagem privada");

        // Emite eventos para cada segredo
        for(uint i = 0; i < message.secrets.length; i++) {
            emit PrivateMessageEmitted(message.secrets[i]);
        }
    }
     
    function _hashSecret(
        uint256[15] memory secret
    ) public pure returns (uint256) {
        uint256 h1 = PoseidonT6.hash(
            [
                uint256(secret[0]),
                uint256(secret[1]),
                uint256(secret[2]),
                uint256(secret[3]),
                uint256(secret[4])
            ]
        );

        uint256 d1 = PoseidonT6.hash(
            [
                uint256(secret[5]),
                uint256(secret[6]),
                uint256(secret[7]),
                uint256(secret[8]),
                uint256(secret[9])
            ]
        );

        uint256 d2 = PoseidonT6.hash(
            [
                uint256(secret[10]),
                uint256(secret[11]),
                uint256(secret[12]),
                uint256(secret[13]),
                uint256(secret[14])
            ]
        );

        uint256[3] memory params = [h1, d1, d2];

        uint256 commitment = PoseidonT4.hash(params);

        return commitment;
    }    
}
