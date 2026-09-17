// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IPrivacyLayer} from "./interfaces/IPrivacyLayer.sol";
import {IAuditableConfidentialSettlementDomain} from "./interfaces/IAuditableConfidentialSettlementDomain.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IPixPaymentVerifier {
    function verifyProof(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[2] calldata pubSignals
    ) external view returns (bool);
}

/**
 * @title HarpoZkPrivacyLayerAuditable — HarpoZkPrivacyLayer + trilha de auditoria
 *   (IAuditableConfidentialSettlementDomain)
 * @notice Variante do domínio ZK que conecta a autoridade de auditoria a um
 *   contrato real (ex.: `HarpoSelectiveDisclosure`, com autorização threshold
 *   M-de-N por commitment) em vez de um EOA fixo, e implementa a extensão
 *   auditável para publicar um payload amarrado ao commitment liquidado.
 */
contract HarpoZkPrivacyLayerAuditable is IAuditableConfidentialSettlementDomain, IERC165 {
    address public immutable verifier;
    address public immutable auditAuthorityAddr; // MAY ser address(0); se não-zero, deve ser um contrato (HarpoSelectiveDisclosure ou equivalente)
    string private _domainId;

    constructor(address verifier_, address auditAuthority_, string memory domainId_) {
        require(verifier_ != address(0), "verifier zero");
        verifier = verifier_;
        auditAuthorityAddr = auditAuthority_;
        _domainId = domainId_;
    }

    function domainId() external view override returns (string memory) {
        return _domainId;
    }

    function privacyModel() external pure override returns (bytes32) {
        return keccak256("ZK");
    }

    /// @inheritdoc IAuditableConfidentialSettlementDomain
    function auditAuthority() external view override returns (address) {
        return auditAuthorityAddr;
    }

    /// @notice ERC-165 introspection — descobre on-chain que este contrato implementa
    ///   IPrivacyLayer (núcleo) E IAuditableConfidentialSettlementDomain (extensão de
    ///   auditoria), sem tentativa-e-erro.
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IPrivacyLayer).interfaceId
            || interfaceId == type(IAuditableConfidentialSettlementDomain).interfaceId;
    }

    /// @inheritdoc IPrivacyLayer
    function verifyConfidentialSettlement(
        bytes32 commitment,
        bytes calldata proof,
        bytes calldata publicInputs
    ) external view override returns (bool ok) {
        return _verify(commitment, proof, publicInputs);
    }

    /// @dev Núcleo da verificação, compartilhado entre `verifyConfidentialSettlement`
    ///   (view) e `emitAuditableSecret` (que exige uma liquidação verificada antes de
    ///   escrever a trilha de auditoria).
    function _verify(bytes32 commitment, bytes calldata proof, bytes calldata publicInputs)
        internal
        view
        returns (bool)
    {
        (uint256[2] memory pA, uint256[2][2] memory pB, uint256[2] memory pC) =
            abi.decode(proof, (uint256[2], uint256[2][2], uint256[2]));
        uint256 e2eIdHash = abi.decode(publicInputs, (uint256));
        uint256[2] memory pub = [uint256(commitment), e2eIdHash];
        return IPixPaymentVerifier(verifier).verifyProof(pA, pB, pC, pub);
    }

    /// @notice Publica um payload de auditoria amarrado a um commitment, exigindo uma
    ///   liquidação válida para o mesmo `(commitment, proof, publicInputs)` NESTA
    ///   MESMA chamada antes de emitir `AuditableSecret` — só quem apresenta uma
    ///   prova válida (i.e. quem de fato liquidou) pode escrever a trilha daquele
    ///   commitment. `auditPayload` DEVE ser cifrado para o canal do auditor (o
    ///   evento é público) — ver `HarpoSelectiveDisclosure`.
    /// @param commitment    lacre da liquidação a auditar (sinal público 0 do circuito).
    /// @param proof         mesma `proof` aceita por `verifyConfidentialSettlement`.
    /// @param publicInputs  mesmos `publicInputs` (abi.encode do `e2eIdHash`).
    /// @param auditPayload  material de auditoria, cifrado para a autoridade.
    function emitAuditableSecret(
        bytes32 commitment,
        bytes calldata proof,
        bytes calldata publicInputs,
        bytes calldata auditPayload
    ) external {
        require(auditAuthorityAddr != address(0), "HarpoZkPrivacyLayerAuditable: sem autoridade de auditoria");
        require(_verify(commitment, proof, publicInputs), "HarpoZkPrivacyLayerAuditable: liquidacao nao verificada");
        emit AuditableSecret(commitment, auditPayload);
    }
}
