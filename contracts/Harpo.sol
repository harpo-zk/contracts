// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Groth16Verifier_mint} from "./verifiers/MintVerify.sol";
import {Groth16Verifier_withdraw} from "./verifiers/WithdrawVerify.sol";
import {Groth16Verifier_1x1} from "./verifiers/1x1Verify.sol";
import {Groth16Verifier_1x2} from "./verifiers/1x2Verify.sol";
import {Groth16Verifier_1x3} from "./verifiers/1x3Verify.sol";
import {Groth16Verifier_2x2} from "./verifiers/2x2Verify.sol";
import {SmtLib} from "./libs/SmtLib.sol";
import {PubKeyRegistry} from "./PubKeyRegistry.sol";
import {PoseidonT4} from "./libs/PoseidonT4.sol";
import {PoseidonT6} from "./libs/PoseidonT6.sol";

contract Harpo {
    Groth16Verifier_mint internal verifier_mint;
    Groth16Verifier_withdraw internal verifier_withdraw;
    Groth16Verifier_1x1 internal verifier_1x1;
    Groth16Verifier_1x2 internal verifier_1x2;
    Groth16Verifier_1x3 internal verifier_1x3;
    Groth16Verifier_2x2 internal verifier_2x2;

    PubKeyRegistry pubKeyRegistry;
    address public contractAuthority; // Autoridade do contrato

    constructor(
        address _pubKeyRegistryAddress,
        address _contractAuthority,
        Groth16Verifier_mint _verifier_mint,
        Groth16Verifier_withdraw _verifier_withdraw,
        Groth16Verifier_1x1 _verifier_1x1,
        Groth16Verifier_1x2 _verifier_1x2,
        Groth16Verifier_1x3 _verifier_1x3,
        Groth16Verifier_2x2 _verifier_2x2
    ) {
        pubKeyRegistry = PubKeyRegistry(_pubKeyRegistryAddress);
        contractAuthority = _contractAuthority;
        verifier_mint = _verifier_mint;
        verifier_withdraw = _verifier_withdraw;
        verifier_1x1 = _verifier_1x1;
        verifier_1x2 = _verifier_1x2;
        verifier_1x3 = _verifier_1x3;
        verifier_2x2 = _verifier_2x2;
        _commitments.initialize(uint256(16)); //TODO valor arbitrario para testes
    }

    uint256 public constant TOKEN_TYPE = 1;//todo passar via construtor

    struct Proof4 {
        uint[2] pA;
        uint[2][2] pB;
        uint[2] pC;
        uint[4] inR;
    }
    struct Proof {
        uint[2] pA;
        uint[2][2] pB;
        uint[2] pC;
    }    
    struct Proof12 {
        uint[2] pA;
        uint[2][2] pB;
        uint[2] pC;
        uint[12] inR;
    }
    struct Proof13 {
        uint[2] pA;
        uint[2][2] pB;
        uint[2] pC;
        uint[13] inR;
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
        uint256 nullifierAuthority;
    }
    struct Output {
        uint256[15] secret;
    }

    struct Transfer {
        Input[] inputs;
        uint256 merkleRoot;
        Output[] outputs;
        uint256[] auditSecret;
        Proof proof;
    }
    struct Transfer1x2 {
        Input[] inputs;
        uint256 merkleRoot;
        Output[] outputs;
        uint256[] auditSecret;
        Proof14 proof;
    }

    struct Transfer1x3 {
        Input[] inputs;
        uint256 merkleRoot;
        Output[] outputs;
        uint256[] auditSecret;
        Proof16 proof;
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
        uint256[][] counterpartAsset;
        address settlementAgent;
        uint256[] auditSecret;
        Proof13 proof; // todo apto para transações 1x1
        Proof16 proof1x3; // apto para transações 1x3
    }

    struct AuthorityRedemptionTransfer {
        uint256 nullifierAuthority;  // O nullifierAuthority bloqueado sendo resgatado
        uint256 merkleRoot;          // Root da árvore Merkle
        Output[] outputs;            // Outputs da transferência
        uint256[] auditSecret;       // Segredos de auditoria
        Proof13 proof;                // Prova específica para resgate de autoridade
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
    
    // Mapping para controle de autoridade sobre nullifiers
    // nullifierAuthority => AuthorityStatus
    mapping(uint256 => AuthorityStatus) public nullifierAuthorityStatus;
    
    struct AuthorityStatus {
        bool isBlocked;    // true se o ativo está bloqueado pela autoridade
        bool isRedeemed;   // true se o ativo foi resgatado pela autoridade
    }

    SmtLib.Data internal _commitments;
    using SmtLib for SmtLib.Data;


    //todo validações , verificar se commitment já existe, modifier
    function mint(uint256[15] memory secret, uint256 amount, Proof memory proof, address sender) public {

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

    function burn(uint256 nullifier, uint256 amount, Proof memory proof, address sender) public {

        uint256[4] memory pubInputs;
        uint256[2] memory pubJub = _getPubJubJub(sender);

        pubInputs[0] = nullifier;
        pubInputs[1] = amount;
        pubInputs[2] = pubJub[0];
        pubInputs[3] = pubJub[1];
        require(
            verifier_withdraw.verifyProof(
                proof.pA,
                proof.pB,
                proof.pC,
                pubInputs
            ),
            "Withdraw proof invalida"
        );

        require(!nullifiersUsed[nullifier], "Nullifier ja utilizado");
        nullifiersUsed[nullifier] = true;
        
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
            uint256 nullifierAuthority = transfer.inputs[i].nullifierAuthority;
            
            // Verifica se o nullifier já foi usado
            require(!nullifiersUsed[nullifier], "Nullifier ja utilizado");
            
            // Verifica se o nullifierAuthority está bloqueado ou foi resgatado
            _checkAuthorityStatus(nullifierAuthority);
            
            nullifiersUsed[nullifier] = true;
        }

        // Verificar se as provas são vazias (todos os valores são zero)
        bool isProof1x3Empty = _isProof16Empty(transfer.proof1x3);
        bool isProof1x1Empty = _isProof13Empty(transfer.proof);
        
        if(!isProof1x3Empty && isProof1x1Empty){
            // Usar a prova 1x3
            require(
                verifier_1x3.verifyProof(
                    transfer.proof1x3.pA,
                    transfer.proof1x3.pB,
                    transfer.proof1x3.pC,
                    transfer.proof1x3.inR
                ),
                "Transfer proof 1x3 invalida"
            );
        } else if(isProof1x3Empty && !isProof1x1Empty){
            // Usar a prova 1x1
            require(
                verifier_1x1.verifyProof(
                    transfer.proof.pA,
                    transfer.proof.pB,
                    transfer.proof.pC,
                    transfer.proof.inR
                ),
                "Transfer proof 1x1 invalida"
            );
        } else {
            // Nenhuma prova válida fornecida
            revert("Nenhuma prova valida fornecida");
        }

        for (uint i = 0; i < transfer.outputs.length; i++) {
            _generateCommitment(transfer.outputs[i].secret);
        }

        emit AuditSecretEmmited(transfer.auditSecret);
    }

    //todo validar tipo do ativo, tipo pode ser definido no construtor da instancia do contrato Harpo
    function processTransfer1x1(Transfer memory transfer) public {
        if (!_commitments.rootExists(transfer.merkleRoot)) {
            revert RootNotFound(transfer.merkleRoot);
        }

        uint256[13] memory pubInputs;

        for (uint i = 0; i < transfer.inputs.length; i++) {
            uint256 nullifier = transfer.inputs[i].nullifier;
            uint256 nullifierAuthority = transfer.inputs[i].nullifierAuthority;
            
            // Verifica se o nullifier já foi usado
            require(!nullifiersUsed[nullifier], "Nullifier ja utilizado");
            
            // Verifica se o nullifierAuthority está bloqueado ou foi resgatado
            _checkAuthorityStatus(nullifierAuthority);
            
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
        pubInputs[12] = transfer.inputs[0].nullifierAuthority;       

        bool proofValid = verifier_1x1.verifyProof(
            transfer.proof.pA,
            transfer.proof.pB,
            transfer.proof.pC,
            pubInputs
        );
        //emit LogProofValidation(proofValid);
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
            uint256 nullifierAuthority = transfer.inputs[i].nullifierAuthority;
            
            // Verifica se o nullifier já foi usado
            require(!nullifiersUsed[nullifier], "Nullifier ja utilizado");
            
            // Verifica se o nullifierAuthority está bloqueado ou foi resgatado
            _checkAuthorityStatus(nullifierAuthority);
            
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
            uint256 nullifierAuthority = transfer.inputs[i].nullifierAuthority;
            
            // Verifica se o nullifier já foi usado
            require(!nullifiersUsed[nullifier], "Nullifier ja utilizado");
            
            // Verifica se o nullifierAuthority está bloqueado ou foi resgatado
            _checkAuthorityStatus(nullifierAuthority);
            
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

    function processTransfer1x3(Transfer1x3 memory transfer) public {
        if (!_commitments.rootExists(transfer.merkleRoot)) {
            revert RootNotFound(transfer.merkleRoot);
        }

        for (uint i = 0; i < transfer.inputs.length; i++) {
            uint256 nullifier = transfer.inputs[i].nullifier;
            uint256 nullifierAuthority = transfer.inputs[i].nullifierAuthority;
            
            // Verifica se o nullifier já foi usado
            require(!nullifiersUsed[nullifier], "Nullifier ja utilizado");
            
            // Verifica se o nullifierAuthority está bloqueado ou foi resgatado
            _checkAuthorityStatus(nullifierAuthority);
            
            nullifiersUsed[nullifier] = true;
        }

        require(
            verifier_1x3.verifyProof(
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
    
    // Funções de controle de autoridade
    
    /**
     * @dev Bloqueia um ativo pela autoridade
     * @param nullifierAuthority O identificador do nullifierAuthority a ser bloqueado
     */
    function blockAsset(uint256 nullifierAuthority) public {
        // Apenas a autoridade do contrato pode bloquear ativos
        //require(msg.sender == contractAuthority, "Apenas a autoridade do contrato pode bloquear ativos");
        
        AuthorityStatus storage status = nullifierAuthorityStatus[nullifierAuthority];
        
        // Se já foi resgatado, não pode ser modificado
        require(!status.isRedeemed, "Ativo ja foi resgatado pela autoridade");
        
        status.isBlocked = true;
    }
    
    /**
     * @dev Desbloqueia um ativo pela autoridade
     * @param nullifierAuthority O identificador do nullifierAuthority a ser desbloqueado
     */
    function unblockAsset(uint256 nullifierAuthority) public {
        // Apenas a autoridade do contrato pode desbloquear ativos
        //require(msg.sender == contractAuthority, "Apenas a autoridade do contrato pode desbloquear ativos");
        
        AuthorityStatus storage status = nullifierAuthorityStatus[nullifierAuthority];
        
        // Se já foi resgatado, não pode ser desbloqueado
        require(!status.isRedeemed, "Ativo ja foi resgatado pela autoridade");
        
        // Remove completamente a entrada do mapping para otimizar performance
        delete nullifierAuthorityStatus[nullifierAuthority];
    }
    
    /**
     * @dev Processa uma transferência de resgate pela autoridade usando protocolo Harpo-ZK
     * @param transfer A transferência de resgate contendo nullifierAuthority bloqueado como input
     */
    function processAuthorityRedemption(AuthorityRedemptionTransfer memory transfer) public {
        // Apenas a autoridade do contrato pode executar resgates
        //require(msg.sender == contractAuthority, "Apenas a autoridade do contrato pode executar resgates");
        
        // Verifica se a merkle root existe
        if (!_commitments.rootExists(transfer.merkleRoot)) {
            revert RootNotFound(transfer.merkleRoot);
        }
        
        // Verifica se o nullifierAuthority está bloqueado (mas não resgatado ainda)
        AuthorityStatus storage status = nullifierAuthorityStatus[transfer.nullifierAuthority];
        require(status.isBlocked, "NullifierAuthority deve estar bloqueado para resgate");
        require(!status.isRedeemed, "NullifierAuthority ja foi resgatado");
        
        // Prepara inputs públicos para verificação da prova
        uint256[4] memory pubInputs;
        pubInputs[0] = transfer.nullifierAuthority;  // O nullifierAuthority sendo resgatado
        pubInputs[1] = _hashSecret(transfer.outputs[0].secret); // Commitment do output
        pubInputs[2] = transfer.auditSecret[0];     // Segredo de auditoria
        pubInputs[3] = transfer.merkleRoot;         // Root da árvore Merkle
        
        // TODO definir prova Verifica a prova zero-knowledge de resgate
       /* require(
            verifier_mint.verifyProof(  // Reutilizando verifier_mint para simplificação
                transfer.proof.pA,
                transfer.proof.pB,
                transfer.proof.pC,
                pubInputs
            ),
            "Prova de resgate invalida"
        );*/
        
        // Marca o nullifierAuthority como resgatado (irreversível)
        status.isRedeemed = true;
        
        // Gera commitments para os outputs da transferência
        for (uint i = 0; i < transfer.outputs.length; i++) {
            _generateCommitment(transfer.outputs[i].secret);
        }
        
        // Emite evento de auditoria
        emit AuditSecretEmmited(transfer.auditSecret);
        
        // Emite evento específico para resgate de autoridade
        emit AuthorityRedemptionExecuted(transfer.nullifierAuthority);
    }
    
    // Evento para resgate de autoridade
    event AuthorityRedemptionExecuted(uint256 nullifierAuthority);
    
    /**
     * @dev Consulta pública do status de um nullifierAuthority
     * @param nullifierAuthority O identificador do nullifierAuthority a ser consultado
     * @return isBlocked true se o ativo está bloqueado
     * @return isRedeemed true se o ativo foi resgatado
     * @return authority endereço da autoridade do contrato
     */
    function getAuthorityStatus(uint256 nullifierAuthority) public view returns (bool isBlocked, bool isRedeemed, address authority) {
        AuthorityStatus memory status = nullifierAuthorityStatus[nullifierAuthority];
        return (status.isBlocked, status.isRedeemed, contractAuthority);
    }
    
    /**
     * @dev Verifica se um nullifierAuthority está bloqueado ou foi resgatado
     * @param nullifierAuthority O identificador do nullifierAuthority a ser verificado
     */
    function _checkAuthorityStatus(uint256 nullifierAuthority) internal view {
        AuthorityStatus memory status = nullifierAuthorityStatus[nullifierAuthority];
        
        if (status.isRedeemed) {
            revert("Ativo resgatado pela autoridade");
        }
        
        if (status.isBlocked) {
            revert("Ativo bloqueado");
        }
    }

    function commitmentExists(uint256 commitment) public view returns (bool) {
        //return commitments[commitment];
    }

    function getCommitmentPath(uint256 commitment) public view returns (bool) {
        //return commitments[commitment];
    }

    // Helper function to check if a Proof12 is empty (all values are zero)
    function _isProof13Empty(Proof13 memory proof) internal pure returns (bool) {
        // Check if pA values are all zero
        if (proof.pA[0] != 0 || proof.pA[1] != 0) {
            return false;
        }

        // Check if pB values are all zero
        if (proof.pB[0][0] != 0 || proof.pB[0][1] != 0 || proof.pB[1][0] != 0 || proof.pB[1][1] != 0) {
            return false;
        }

        // Check if pC values are all zero
        if (proof.pC[0] != 0 || proof.pC[1] != 0) {
            return false;
        }

        // Check if inR values are all zero
        for (uint i = 0; i < proof.inR.length; i++) {
            if (proof.inR[i] != 0) {
                return false;
            }
        }

        return true;
    }
    
    // Helper function to check if a Proof16 is empty (all values are zero)
    function _isProof16Empty(Proof16 memory proof) internal pure returns (bool) {
        // Check if pA values are all zero
        if (proof.pA[0] != 0 || proof.pA[1] != 0) {
            return false;
        }

        // Check if pB values are all zero
        if (proof.pB[0][0] != 0 || proof.pB[0][1] != 0 || proof.pB[1][0] != 0 || proof.pB[1][1] != 0) {
            return false;
        }

        // Check if pC values are all zero
        if (proof.pC[0] != 0 || proof.pC[1] != 0) {
            return false;
        }

        // Check if inR values are all zero
        for (uint i = 0; i < proof.inR.length; i++) {
            if (proof.inR[i] != 0) {
                return false;
            }
        }

        return true;
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
