// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IPrivacyLayer — a "junta" (seam) trocável da camada de privacidade
 * @notice O fluxo de negócio (ex.: home equity / financiamento) depende DESTA
 *   interface — não da implementação. Harpo (ZK/Groth16/UTXO) é UMA implementação;
 *   amanhã um domínio notary-based, TEE, ou outro ZK pode implementar a MESMA
 *   interface e ser plugado via HarpoRegistry, sem tocar no contrato de negócio.
 *
 *   Princípio de design: a interface expressa INTENÇÃO ("essa liquidação
 *   confidencial é válida?"), não MECANISMO (Groth16, sinais públicos,
 *   pairing...). É isso que permite trocar a camada de privacidade de forma
 *   transparente — a chave da intercambiabilidade (estilo domínios do Paladin:
 *   Zeto / Noto / Pente por trás de uma mesma fachada).
 *
 *   Núcleo normativo do ERC ("Confidential Settlement Domain Interface"):
 *   `domainId`, `privacyModel`, `verifyConfidentialSettlement` — exatamente
 *   estes três. `auditAuthority()` NÃO pertence a este núcleo; um domínio com
 *   história de auditoria implementa `IAuditableConfidentialSettlementDomain`
 *   (extensão), que herda
 *   esta interface e adiciona `auditAuthority()` + o evento `AuditableSecret`.
 *   Um domínio sem nada para auditar simplesmente não implementa a extensão —
 *   descobrível via `ERC-165`, sem precisar de um stub retornando `address(0)`.
 */
interface IPrivacyLayer {
    /**
     * @notice Verifica uma liquidação confidencial contra um compromisso registrado,
     *   sem revelar os valores. Cada implementação decide COMO (ZK, notary, TEE...).
     * @param commitment   compromisso público previamente registrado (ex.: Poseidon).
     * @param proof        prova opaca (o formato é problema da implementação).
     * @param publicInputs sinais públicos mínimos necessários (ex.: anti-replay).
     * @return ok true se a liquidação confidencial é válida.
     */
    function verifyConfidentialSettlement(
        bytes32 commitment,
        bytes calldata proof,
        bytes calldata publicInputs
    ) external view returns (bool ok);

    /// @notice Identificador legível da implementação/domínio (ex.: "harpo-zk-groth16").
    function domainId() external view returns (string memory);

    /// @notice Modelo de privacidade (ex.: keccak256("ZK") / "FHE" / "MPC" / "TEE" / "NOTARY").
    function privacyModel() external view returns (bytes32);
}
