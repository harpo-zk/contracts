// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Groth16Verifier_step} from "./verifiers/StepVerify.sol";

/**
 * @dev Interface para verificadores ZKP
 */
interface IZKPVerifier {
    function verify(
        uint256[2] memory pA,
        uint256[2][2] memory pB,
        uint256[2] memory pC,
        bytes memory publicInputs
    ) external view returns (bool);
}

/**
 * @title EnhancedStepSequence
 * @dev Contract to manage step sequence verification with configurable conditions
 */
contract EnhancedStepSequence {
    
    // Verificadores ZKP
    Groth16Verifier_step internal verifier_step;
    
    // Estrutura para armazenar um compromisso criptográfico
    struct Commitment {
        bytes32 value;
        bool exists;
    }
    
    // Estrutura para uma condição de passo
    struct StepCondition {
        address verifierContract;
        bytes4 verifierMethod;
        bool required;
        mapping(bytes32 => Commitment) expectedCommitments;
    }
    
    // Estrutura para configuração de um passo
    struct StepConfig {
        StepCondition[] conditions;
        uint256 requiredConditions;
        bool allowPartialVerification;
        bool configured;
    }
    
    // Mapeamento de tipo de transação para configuração de passos
    mapping(bytes32 => mapping(uint256 => StepConfig)) public stepConfigurations;
    
    // Mapeamento de ID de transação para último passo concluído
    mapping(uint256 => uint256) public transactionSteps;
    
    // Mapeamento de ID de transação para tipo de transação
    mapping(uint256 => bytes32) public transactionTypes;
    
    // Eventos
    event StepCompleted(uint256 indexed transactionId, uint256 step);
    event StepConfigured(bytes32 indexed transactionType, uint256 step, uint256 conditionsCount);
    event CommitmentConfigured(bytes32 indexed transactionType, uint256 step, uint256 conditionIndex, bytes32 paramKey);
    
    // Erros
    error StepNotConfigured(bytes32 transactionType, uint256 step);
    error InvalidStepSequence(uint256 currentStep, uint256 requestedStep);
    error NotEnoughConditionsVerified(uint256 verified, uint256 required);
    error RequiredConditionFailed(uint256 conditionIndex);
    
    constructor(Groth16Verifier_step _verifier_step) {
        verifier_step = _verifier_step;
    }
    
    /**
     * @dev Estrutura para uma prova ZKP
     */
    struct Proof {
        uint[2] pA;
        uint[2][2] pB;
        uint[2] pC;
        uint[] inR;
    }
    
    /**
     * @dev Estrutura para submissão de prova
     */
    struct ProofSubmission {
        uint256 conditionIndex;
        uint[2] pA;
        uint[2][2] pB;
        uint[2] pC;
        bytes publicInputs;
    }
    

    /**
     * @dev Configura um passo para um tipo de transação
     * @param transactionType O tipo de transação (ex: "realEstateTransaction")
     * @param step O número do passo
     * @param conditionsCount Número de condições para este passo
     * @param requiredConditions Número mínimo de condições que devem ser satisfeitas
     * @param allowPartialVerification Se a verificação parcial é permitida
     */
    function configureStep(
        bytes32 transactionType,
        uint256 step,
        uint256 conditionsCount,
        uint256 requiredConditions,
        bool allowPartialVerification
    ) external {
        StepConfig storage config = stepConfigurations[transactionType][step];
        
        // Limpar configuração existente se houver
        if (config.configured) {
            delete stepConfigurations[transactionType][step];
        }
        
        // Inicializar array de condições
        for (uint i = 0; i < conditionsCount; i++) {
            config.conditions.push();
        }
        
        config.requiredConditions = requiredConditions;
        config.allowPartialVerification = allowPartialVerification;
        config.configured = true;
        
        emit StepConfigured(transactionType, step, conditionsCount);
    }
    
    /**
     * @dev Configura uma condição para um passo
     * @param transactionType O tipo de transação
     * @param step O número do passo
     * @param conditionIndex O índice da condição
     * @param verifierContract O contrato verificador ZKP
     * @param verifierMethod O seletor do método verificador
     * @param required Se a condição é obrigatória
     */
    function configureStepCondition(
        bytes32 transactionType,
        uint256 step,
        uint256 conditionIndex,
        address verifierContract,
        bytes4 verifierMethod,
        bool required
    ) external {
        StepConfig storage config = stepConfigurations[transactionType][step];
        require(config.configured, "Step not configured");
        require(conditionIndex < config.conditions.length, "Invalid condition index");
        
        StepCondition storage condition = config.conditions[conditionIndex];
        condition.verifierContract = verifierContract;
        condition.verifierMethod = verifierMethod;
        condition.required = required;
    }
    
    /**
     * @dev Configura um compromisso para uma condição
     * @param transactionType O tipo de transação
     * @param step O número do passo
     * @param conditionIndex O índice da condição
     * @param paramKey A chave do parâmetro
     * @param commitmentValue O valor do compromisso
     */
    function configureCommitment(
        bytes32 transactionType,
        uint256 step,
        uint256 conditionIndex,
        bytes32 paramKey,
        bytes32 commitmentValue
    ) external {
        StepConfig storage config = stepConfigurations[transactionType][step];
        require(config.configured, "Step not configured");
        require(conditionIndex < config.conditions.length, "Invalid condition index");
        
        StepCondition storage condition = config.conditions[conditionIndex];
        condition.expectedCommitments[paramKey] = Commitment({
            value: commitmentValue,
            exists: true
        });
        
        emit CommitmentConfigured(transactionType, step, conditionIndex, paramKey);
    }
    
    /**
     * @dev Executa um passo na sequência
     * @param transactionType O tipo de transação
     * @param transactionId O ID da transação
     * @param targetStep O passo alvo a ser executado
     * @param proofs Array de provas ZKP
     */
    function executeStep(
        bytes32 transactionType,
        uint256 transactionId,
        uint256 targetStep,
        ProofSubmission[] memory proofs
    ) external {
        // Verificar se o passo está configurado
        StepConfig storage config = stepConfigurations[transactionType][targetStep];
        if (!config.configured) {
            revert StepNotConfigured(transactionType, targetStep);
        }
        
        // Verificar sequência de passos
        uint256 currentStep = transactionSteps[transactionId];
        if (targetStep != currentStep + 1) {
            revert InvalidStepSequence(currentStep, targetStep);
        }
        
        // Verificar tipo de transação
        bytes32 storedType = transactionTypes[transactionId];
        if (storedType == bytes32(0)) {
            // Primeira execução para esta transação
            transactionTypes[transactionId] = transactionType;
        } else {
            // Verificar que o tipo de transação é consistente
            require(storedType == transactionType, "Transaction type mismatch");
        }
        
        // Verificar provas
        uint256 verifiedCount = 0;
        
        for (uint i = 0; i < proofs.length; i++) {
            ProofSubmission memory proof = proofs[i];
            
            // Verificar que o índice da condição é válido
            require(proof.conditionIndex < config.conditions.length, "Invalid condition index");
            
            StepCondition storage condition = config.conditions[proof.conditionIndex];
            
            // Verificar a prova usando o contrato verificador
            bool verified = IZKPVerifier(condition.verifierContract).verify(
                proof.pA,
                proof.pB,
                proof.pC,
                proof.publicInputs
            );
            
            if (verified) {
                verifiedCount++;
            } else if (condition.required) {
                revert RequiredConditionFailed(proof.conditionIndex);
            }
        }
        
        // Verificar que o número mínimo de condições foi satisfeito
        if (verifiedCount < config.requiredConditions) {
            revert NotEnoughConditionsVerified(verifiedCount, config.requiredConditions);
        }
        
        // Atualizar o passo da transação
        transactionSteps[transactionId] = targetStep;
        
        // Emitir evento
        emit StepCompleted(transactionId, targetStep);
    }
    
    /**
     * @dev Executa um passo na sequência usando o verificador de passos padrão
     * @param transactionId O ID da transação
     * @param proof A prova do passo
     */
    function executeBasicStep(
        uint256 transactionId,
        Proof memory proof
    ) external {
        uint256[1] memory pubInputs;
        
        // Obter o último passo concluído para esta transação
        uint256 lastStep = transactionSteps[transactionId];
        pubInputs[0] = lastStep + 1;
        
        // Verificar que o passo é o próximo na sequência
        require(
            verifier_step.verifyProof(
                proof.pA,
                proof.pB,
                proof.pC,
                pubInputs
            ),
            "Invalid step sequence: must execute steps in order"
        );
        
        // Atualizar o passo da transação
        transactionSteps[transactionId] = lastStep + 1;
        
        // Emitir evento
        emit StepCompleted(transactionId, lastStep + 1);
    }
    
    /**
     * @dev Obtém o passo atual para uma transação
     * @param transactionId O ID da transação
     * @return O passo atual
     */
    function getCurrentStep(uint256 transactionId) public view returns (uint256) {
        return transactionSteps[transactionId];
    }
    
    /**
     * @dev Verifica se um passo pode ser executado
     * @param transactionId O ID da transação
     * @param step O passo a verificar
     * @return True se o passo pode ser executado
     */
    function canExecuteStep(uint256 transactionId, uint256 step) public view returns (bool) {
        return step == transactionSteps[transactionId] + 1;
    }
    
    /**
     * @dev Inicializa uma nova transação com o passo 0
     * @param transactionId O ID da transação
     */
    function initializeTransaction(uint256 transactionId) public {
        require(transactionSteps[transactionId] == 0, "Transaction already initialized");
        
        // Passo 0 é o passo de inicialização
        transactionSteps[transactionId] = 0;
        emit StepCompleted(transactionId, 0);
    }
}
