// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IPrivacyLayer} from "./interfaces/IPrivacyLayer.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title HarpoNotaryPrivacyLayer — domínio de privacidade NOTARY sob a interface IPrivacyLayer
 * @notice Implementa `IPrivacyLayer` com um mecanismo sem ZK: em vez de provar a
 *   liquidação com um circuito (verifier, pairing, sinais públicos), este domínio
 *   confia numa assinatura EIP-712 de um notário confiável atestando que a
 *   liquidação confidencial daquele commitment é válida.
 *
 *   O consumidor de negócio resolve o domínio pelo nome no `HarpoRegistry` e
 *   chama `verifyConfidentialSettlement` contra a interface `IPrivacyLayer`. Se
 *   o registry aponta para um domínio ZK ou para este domínio notary, a chamada
 *   do consumidor é idêntica — trocar o backend é um `registry.set()`, sem
 *   tocar no contrato de negócio.
 *
 *   Encoding:
 *     - `proof`        = assinatura EIP-712 bruta (bytes r ‖ s ‖ v, 65 bytes) do
 *                        notário sobre o struct Settlement(bytes32 commitment, bytes32 publicInputsHash)
 *     - `publicInputs` = bytes arbitrários; o contrato deriva
 *                        publicInputsHash = keccak256(publicInputs) (ex.: anti-replay)
 *     - `commitment`   = compromisso público atestado (ex.: Poseidon), carimbado no struct
 *
 *   `verifyConfidentialSettlement` é `view` e nunca reverte — assinatura
 *   inválida (r/s/v fora de curva, tamanho errado, assinante diferente do
 *   notário) retorna `false`.
 */
contract HarpoNotaryPrivacyLayer is IPrivacyLayer, IERC165, EIP712 {
    // EIP-712 typehash do atestado de liquidação (mesmo encoding do signTypedData off-chain)
    bytes32 private constant _SETTLEMENT_TYPEHASH =
        keccak256("Settlement(bytes32 commitment,bytes32 publicInputsHash)");

    /// @notice Notário confiável: só assinaturas EIP-712 desta chave atestam liquidações.
    address public immutable notary;

    /// @notice Autoridade que pode decriptar a trilha de auditoria.
    address public immutable auditAuthorityAddr;

    /// @notice Identificador legível do domínio (ex.: "harpo-notary").
    string private _domainId;

    /// @param notary_           chave pública do notário (assinante confiável).
    /// @param auditAuthority_   autoridade de auditoria (ex.: o deployer).
    /// @param domainId_         identificador do domínio (ex.: "harpo-notary").
    constructor(address notary_, address auditAuthority_, string memory domainId_)
        EIP712("HarpoNotaryPrivacyLayer", "1")
    {
        require(notary_ != address(0), "HarpoNotaryPrivacyLayer: notary zero");
        notary = notary_;
        auditAuthorityAddr = auditAuthority_;
        _domainId = domainId_;
    }

    /// @inheritdoc IPrivacyLayer
    function domainId() external view override returns (string memory) {
        return _domainId;
    }

    /// @inheritdoc IPrivacyLayer
    function privacyModel() external pure override returns (bytes32) {
        return keccak256("NOTARY");
    }

    // `auditAuthority()` não faz parte do núcleo `IPrivacyLayer` — este domínio
    // não implementa a extensão auditável. O valor continua legível via o
    // getter público `auditAuthorityAddr`.

    /// @notice ERC-165 — este contrato é um domínio de liquidação confidencial
    ///   (interface IPrivacyLayer), com MECANISMO notary por trás da mesma fachada.
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IPrivacyLayer).interfaceId;
    }

    /// @inheritdoc IPrivacyLayer
    /// @dev Mecanismo NOTARY: recupera o assinante da assinatura EIP-712 sobre
    ///   Settlement(commitment, keccak256(publicInputs)) e aceita SÓ se for o notário.
    ///   Nunca reverte (a interface é view): assinatura malformada → false.
    function verifyConfidentialSettlement(
        bytes32 commitment,
        bytes calldata proof,
        bytes calldata publicInputs
    ) external view override returns (bool ok) {
        bytes32 publicInputsHash = keccak256(publicInputs);
        bytes32 structHash = keccak256(
            abi.encode(_SETTLEMENT_TYPEHASH, commitment, publicInputsHash)
        );
        (address signer, ECDSA.RecoverError err, ) =
            ECDSA.tryRecover(_hashTypedDataV4(structHash), proof);
        if (err != ECDSA.RecoverError.NoError) return false;
        return signer == notary;
    }
}
