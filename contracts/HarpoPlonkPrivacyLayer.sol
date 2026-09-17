// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IPrivacyLayer} from "./interfaces/IPrivacyLayer.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IPlonkVerifier {
    function verifyProof(uint256[24] calldata _proof, uint256[2] calldata _pubSignals) external view returns (bool);
}

/**
 * @title HarpoPlonkPrivacyLayer — domínio ZK sob IPrivacyLayer com sistema de prova PLONK
 * @notice A MESMA liquidação confidencial do domínio Groth16 (HarpoZkPrivacyLayer), mas provada
 *   com PLONK (setup UNIVERSAL — sem cerimônia por circuito). Prova que o harpo é agnóstico de
 *   SISTEMA DE PROVA: o consumidor resolve o domínio por nome no HarpoRegistry e chama a MESMA
 *   IPrivacyLayer.verifyConfidentialSettlement; trocar Groth16 ↔ PLONK é 1 registry.set, sem o
 *   contrato de negócio mudar. Cada sistema de prova é apenas um adapter sob a mesma junta
 *   (Groth16, PLONK agora; Halo2/STARK plugam igual — outro verifier, mesmo seam).
 *
 *   Encoding:
 *     - `proof`        = abi.encode(uint256[24])  // formato da prova PLONK do snarkjs
 *     - `publicInputs` = abi.encode(uint256 e2eIdHash)  // anti-replay
 *     - `commitment`   = 1º sinal público (Poseidon), igual ao domínio Groth16
 */
contract HarpoPlonkPrivacyLayer is IPrivacyLayer, IERC165 {
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

    /// @notice Mesmo modelo (ZK) do domínio Groth16 — o que muda é o SISTEMA DE PROVA, não o modelo.
    function privacyModel() external pure override returns (bytes32) {
        return keccak256("ZK");
    }

    // `auditAuthority()` não faz parte do núcleo `IPrivacyLayer` — este domínio
    // não implementa a extensão auditável. O valor continua legível via o
    // getter público `auditAuthorityAddr`.

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
        uint256[24] memory p = abi.decode(proof, (uint256[24]));
        uint256 e2eIdHash = abi.decode(publicInputs, (uint256));
        uint256[2] memory pub = [uint256(commitment), e2eIdHash];
        return IPlonkVerifier(verifier).verifyProof(p, pub);
    }
}
