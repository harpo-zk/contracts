// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title MockSettlementVerifier — verifier de teste, com as assinaturas que
 *   `HarpoZkPrivacyLayer`/`HarpoTokenPrivacyLayer` (Groth16, tupla de 3) e
 *   `HarpoPlonkPrivacyLayer` (PLONK, array de 24) esperam.
 * @notice Usado só em testes locais — não é usado por nenhum script de deploy
 *   real nem por nenhum contrato de produção. Deixa `result` fixo no deploy
 *   para simular um verifier que sempre aceita ou sempre rejeita, sem depender
 *   de circuitos/artefatos reais.
 */
contract MockSettlementVerifier {
    bool public immutable result;

    constructor(bool result_) {
        result = result_;
    }

    /// @notice Assinatura Groth16 (HarpoZkPrivacyLayer / HarpoTokenPrivacyLayer).
    function verifyProof(
        uint256[2] calldata,
        uint256[2][2] calldata,
        uint256[2] calldata,
        uint256[2] calldata
    ) external view returns (bool) {
        return result;
    }

    /// @notice Assinatura PLONK (HarpoPlonkPrivacyLayer).
    function verifyProof(
        uint256[24] calldata,
        uint256[2] calldata
    ) external view returns (bool) {
        return result;
    }
}
