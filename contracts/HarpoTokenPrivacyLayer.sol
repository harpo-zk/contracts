// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IPrivacyLayer} from "./interfaces/IPrivacyLayer.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface ITokenSettlementVerifier {
    function verifyProof(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[2] calldata pubSignals
    ) external view returns (bool);
}

/**
 * @title HarpoTokenPrivacyLayer — domínio de liquidação confidencial de transferência de token
 * @notice Implementação de referência de `IPrivacyLayer` para um claim de liquidação
 *   diferente: "o token T, no valor A, foi transferido do endereço S para o
 *   endereço R, sob a referência de liquidação settlementRef". Usa seu próprio
 *   circuito (`circuits/token_settlement_verify.circom`) e seu próprio verifier
 *   Groth16, com trusted setup independente de outros domínios ZK do protocolo.
 *
 *   Encoding:
 *     - `proof`        = abi.encode(uint256[2] pA, uint256[2][2] pB, uint256[2] pC)
 *     - `publicInputs` = abi.encode(uint256 settlementRefHash)   // anti-replay
 *     - `commitment`   = Poseidon(tokenId, amount, sender, receiver, salt) → 1º sinal público
 */
contract HarpoTokenPrivacyLayer is IPrivacyLayer, IERC165 {
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

    /// @notice Mesma tag ZK do domínio Pix — a interoperabilidade de mecanismo (ZK) é
    ///   idêntica; o que muda é a LIQUIDAÇÃO (o claim), não a família criptográfica.
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
        (uint256[2] memory pA, uint256[2][2] memory pB, uint256[2] memory pC) =
            abi.decode(proof, (uint256[2], uint256[2][2], uint256[2]));
        uint256 settlementRefHash = abi.decode(publicInputs, (uint256));
        uint256[2] memory pub = [uint256(commitment), settlementRefHash];
        return ITokenSettlementVerifier(verifier).verifyProof(pA, pB, pC, pub);
    }
}
