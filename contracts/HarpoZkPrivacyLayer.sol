// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IPrivacyLayer} from "./interfaces/IPrivacyLayer.sol";
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
 * @title HarpoZkPrivacyLayer — implementação de referência de IPrivacyLayer (domínio ZK Groth16)
 * @notice Adapta o verifier Groth16 do harpo (prova de pagamento Pix) à interface
 *   NEUTRA IPrivacyLayer. O consumidor de negócio fala com a interface; este
 *   adapter é UMA implementação (domínio "harpo-zk-groth16"). Trocar por outro
 *   domínio (outro ZK, FHE, notary) = 1 registry.set(), sem tocar no negócio.
 *
 *   Encoding (documentado, como exige a ERC):
 *     - `proof`        = abi.encode(uint256[2] pA, uint256[2][2] pB, uint256[2] pC)
 *     - `publicInputs` = abi.encode(uint256 e2eIdHash)   // anti-replay
 *     - `commitment`   = Poseidon(amount, salt, e2eId, txid)  → 1º sinal público
 */
contract HarpoZkPrivacyLayer is IPrivacyLayer, IERC165 {
    address public immutable verifier;
    address public immutable auditAuthorityAddr;
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

    // `auditAuthority()` não faz parte do núcleo `IPrivacyLayer` — este domínio
    // não implementa a extensão auditável (não emite `AuditableSecret`). O
    // valor configurado no construtor continua legível via o getter público
    // `auditAuthorityAddr`. Ver `HarpoZkPrivacyLayerAuditable` para o domínio
    // que implementa a extensão.

    /// @notice ERC-165 introspection — permite descobrir on-chain que este contrato
    ///   é um domínio de liquidação confidencial (interface IPrivacyLayer) sem tentativa-e-erro.
    ///   Exigido pela ERC "Confidential Settlement Domain Interface" (MUST implementar ERC-165).
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IPrivacyLayer).interfaceId;
    }

    /// @inheritdoc IPrivacyLayer
    function verifyConfidentialSettlement(
        bytes32 commitment,
        bytes calldata proof,
        bytes calldata publicInputs
    ) external view override returns (bool ok) {
        (uint256[2] memory pA, uint256[2][2] memory pB, uint256[2] memory pC) =
            abi.decode(proof, (uint256[2], uint256[2][2], uint256[2]));
        uint256 e2eIdHash = abi.decode(publicInputs, (uint256));
        uint256[2] memory pub = [uint256(commitment), e2eIdHash];
        return IPixPaymentVerifier(verifier).verifyProof(pA, pB, pC, pub);
    }
}
