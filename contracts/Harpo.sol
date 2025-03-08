// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import {Groth16Verifier_mint} from "./MintVerify.sol";
import {Groth16Verifier_1x1} from "./1x1Verify.sol";
import {Groth16Verifier_1x2} from "./1x2Verify.sol";
import {Groth16Verifier_2x2} from "./2x2Verify.sol";
import {SmtLib} from "./SmtLib.sol";
import {PubKeyRegistry} from "./PubKeyRegistry.sol";
import {PoseidonT2} from "./PoseidonT2.sol";
import {PoseidonT4} from "./PoseidonT4.sol";
import {PoseidonT6} from "./PoseidonT6.sol";

contract Harpo {
    Groth16Verifier_mint internal verifier_mint;
    Groth16Verifier_1x1 internal verifier_1x1;
    Groth16Verifier_1x2 internal verifier_1x2;
    Groth16Verifier_2x2 internal verifier_2x2;

    PubKeyRegistry pubKeyRegistry;

    constructor(
        address _pubKeyRegistryAddress,
        Groth16Verifier_mint _verifier_mint,
        Groth16Verifier_1x1 _verifier_1x1,
        Groth16Verifier_1x2 _verifier_1x2,
        Groth16Verifier_2x2 _verifier_2x2
    ) {
        pubKeyRegistry = PubKeyRegistry(_pubKeyRegistryAddress);
        verifier_mint = _verifier_mint;
        verifier_1x1 = _verifier_1x1;
        verifier_1x2 = _verifier_1x2;
        verifier_2x2 = _verifier_2x2;
        _commitments.initialize(uint256(16)); //TODO valor arbitrario para testes
    }

    uint256 public constant TOKEN_TYPE = 1;

    struct Proof4 {
        uint[2] pA;
        uint[2][2] pB;
        uint[2] pC;
        uint[4] inR;
    }
    struct Proof12 {
        uint[2] pA;
        uint[2][2] pB;
        uint[2] pC;
        uint[12] inR;
    }
    struct Proof14 {
        uint[2] pA;
        uint[2][2] pB;
        uint[2] pC;
        uint[14] inR;
    }

    struct Proof16 {
        uint[2] pA;
        uint[2][2] pB;
        uint[2] pC;
        uint[16] inR;
    }
    struct ProofCommitment {
        uint256 root;
        bool existence;
        uint256[] siblings;
        uint256 index;
        uint256 value;
        bool auxExistence;
        uint256 auxIndex;
        uint256 auxValue;
    }
    struct Input {
        uint256 nullifier;
    }
    struct Output {
        uint256[15] secret;
    }

    struct Transfer1x1 {
        Input[] inputs;
        uint256 merkleRoot;
        Output[] outputs;
        uint256[] auditSecret;
        Proof12 proof;
    }
    struct Transfer1x2 {
        Input[] inputs;
        uint256 merkleRoot;
        Output[] outputs;
        uint256[] auditSecret;
        Proof14 proof;
    }

    struct Transfer2x2 {
        Input[] inputs;
        uint256 merkleRoot;
        Output[] outputs;
        uint256[] auditSecret;
        Proof16 proof;
    }

    struct DelegatedTransfer {
        Input[] inputs;
        uint256 merkleRoot;
        Output[] outputs;
        uint256[] counterpartAsset;
        address settlementAgent;
        uint256[] auditSecret;
        Proof12 proof; // todo apto para transações 1x1
    }

    event CommitmentGenerated(uint256 commitment, uint256[15] secret);

    event AuditSecretEmmited(uint256[] auditSecret);

    event SecretGenerated(uint256[15] secret, uint256 nonce);

    event C1Generated(uint256[2] c1);

    event LogProofValidation(bool proofValid);

    error InvalidProof(
        bytes32 leaf,
        uint256 index,
        uint256 enables,
        bytes32[] path
    );

    error RootNotFound(uint256 merkleRoot);
    error CommitmentAlreadyExists(uint256 commitment);

    mapping(uint256 => bool) public nullifiersUsed; //todo private

    SmtLib.Data internal _commitments;
    using SmtLib for SmtLib.Data;

    //todo validações , verificar se commitment já existe, modifier
    function mint(uint256[15] memory secret, uint256 amount, Proof4 memory proof, address sender) public {

        uint256[4] memory pubInputs;
        uint256[2] memory pubJub = _getPubJubJub(sender);

        pubInputs[0] = _hashSecret(secret);
        pubInputs[1] = amount;
        pubInputs[2] = pubJub[0];
        pubInputs[3] = pubJub[1];
        require(
            verifier_mint.verifyProof(
                proof.pA,
                proof.pB,
                proof.pC,
                pubInputs
            ),
            "Mint proof invalida"
        );

        _generateCommitment(secret);
        
    }
    
    function _getPubJubJub(
        address ethAddress
    ) internal view returns (uint256[2] memory) {
        return pubKeyRegistry.getBabyJubJubKey(ethAddress);
    }
    
    function processDelegatedTransfer(
        DelegatedTransfer memory transfer
    ) public {
        //todo registrar todos os possiveis contratos liquidantes DVP e validar aki, (settlement mapping)?

        require(
            transfer.settlementAgent == msg.sender,
            "Only the settlement agent can call this function"
        );

        if (!_commitments.rootExists(transfer.merkleRoot)) {
            revert RootNotFound(transfer.merkleRoot);
        }

        for (uint i = 0; i < transfer.inputs.length; i++) {
            uint256 nullifier = transfer.inputs[i].nullifier;
            require(!nullifiersUsed[nullifier], "Nullifier ja utilizado");
            nullifiersUsed[nullifier] = true;
        }

        require(
            verifier_1x1.verifyProof(
                transfer.proof.pA,
                transfer.proof.pB,
                transfer.proof.pC,
                transfer.proof.inR // todo enviar valores recebidos na transação para compor as entradas publicas
            ),
            "Transfer proof invalida"
        );

        for (uint i = 0; i < transfer.outputs.length; i++) {
            _generateCommitment(transfer.outputs[i].secret);
        }

        emit AuditSecretEmmited(transfer.auditSecret);
    }

    //todo validar tipo do ativo, tipo pode ser definido no construtor da instancia do contrato Harpo
    function processTransfer1x1(Transfer1x1 memory transfer) public {
        if (!_commitments.rootExists(transfer.merkleRoot)) {
            revert RootNotFound(transfer.merkleRoot);
        }

        uint256[12] memory pubInputs;

        for (uint i = 0; i < transfer.inputs.length; i++) {
            uint256 nullifier = transfer.inputs[i].nullifier;
            require(!nullifiersUsed[nullifier], "Nullifier ja utilizado");
            nullifiersUsed[nullifier] = true;
        }

        pubInputs[0] = transfer.inputs[0].nullifier;
        pubInputs[1] = _hashSecret(transfer.outputs[0].secret); //gene
        //pubInputs[1] = transfer.auditSecret[0];//errado pra teste
        pubInputs[2] = transfer.auditSecret[0];
        pubInputs[3] = transfer.auditSecret[1];
        pubInputs[4] = transfer.auditSecret[2];
        pubInputs[5] = transfer.auditSecret[3];
        pubInputs[6] = transfer.auditSecret[4];
        pubInputs[7] = transfer.auditSecret[5];
        pubInputs[8] = transfer.auditSecret[6];
        pubInputs[9] = transfer.auditSecret[7];
        pubInputs[10] = transfer.auditSecret[8];
        pubInputs[11] = transfer.auditSecret[9];

        for (uint i = 0; i < transfer.proof.inR.length; i++) {
            require(
                pubInputs[i] == transfer.proof.inR[i],
                "Invalid Input value"
            );
        }

        bool proofValid = verifier_1x1.verifyProof(
            transfer.proof.pA,
            transfer.proof.pB,
            transfer.proof.pC,
            pubInputs
        );
        emit LogProofValidation(proofValid);
        require(proofValid, "Transfer proof invalida");

        for (uint i = 0; i < transfer.outputs.length; i++) {
            _generateCommitment(transfer.outputs[i].secret);
        }

        emit AuditSecretEmmited(transfer.auditSecret);
    }

    function processTransfer1x2(Transfer1x2 memory transfer) public {
        if (!_commitments.rootExists(transfer.merkleRoot)) {
            revert RootNotFound(transfer.merkleRoot);
        }

        for (uint i = 0; i < transfer.inputs.length; i++) {
            uint256 nullifier = transfer.inputs[i].nullifier;
            require(!nullifiersUsed[nullifier], "Nullifier ja utilizado");
            nullifiersUsed[nullifier] = true;
        }

        require(
            verifier_1x2.verifyProof(
                transfer.proof.pA,
                transfer.proof.pB,
                transfer.proof.pC,
                transfer.proof.inR
            ),
            "Transfer proof invalida"
        );

        for (uint i = 0; i < transfer.outputs.length; i++) {
            _generateCommitment(transfer.outputs[i].secret);
        }

        emit AuditSecretEmmited(transfer.auditSecret);
    }

    function processTransfer2x2(Transfer2x2 memory transfer) public {
        if (!_commitments.rootExists(transfer.merkleRoot)) {
            revert RootNotFound(transfer.merkleRoot);
        }

        for (uint i = 0; i < transfer.inputs.length; i++) {
            uint256 nullifier = transfer.inputs[i].nullifier;
            require(!nullifiersUsed[nullifier], "Nullifier ja utilizado");
            nullifiersUsed[nullifier] = true;
        }

        require(
            verifier_2x2.verifyProof(
                transfer.proof.pA,
                transfer.proof.pB,
                transfer.proof.pC,
                transfer.proof.inR
            ),
            "Transfer proof invalida"
        );

        for (uint i = 0; i < transfer.outputs.length; i++) {
            _generateCommitment(transfer.outputs[i].secret);
        }

        emit AuditSecretEmmited(transfer.auditSecret);
    }

    function getRoot() public view returns (uint256) {
        return _commitments.getRoot();
    }

    function getProof(
        uint256 commitment
    ) public view returns (SmtLib.Proof memory) {
        return _commitments.getProof(commitment);
    }

    function isNullifierUsed(uint256 nullifier) public view returns (bool) {
        return nullifiersUsed[nullifier];
    }

    function commitmentExists(uint256 commitment) public view returns (bool) {
        //return commitments[commitment];
    }

    function getCommitmentPath(uint256 commitment) public view returns (bool) {
        //return commitments[commitment];
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

    function _generateCommitment(uint256[15] memory secret) public {
        uint256 commitment = _hashSecret(secret);

        _commitments.addLeaf(commitment, commitment);

        emit CommitmentGenerated(commitment, secret);
    }
}
