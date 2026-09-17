// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IPrivacyLayer} from "./interfaces/IPrivacyLayer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Superfície mínima do HarpoRegistry usada pelo consumidor.
interface IHarpoRegistry {
    function get(string calldata name) external view returns (address);
}

/**
 * @title HarpoSettlementConsumer — consumidor de referência para liquidação confidencial
 * @notice Um único contrato reúne três garantias:
 *
 *   1. **Amarração ao processo de negócio**: `commitment` nunca é aceito como
 *      parâmetro de `liquidar()` — é resolvido internamente de
 *      `expectedCommitment[processoId]`, pré-registrado pelo dono do processo
 *      no momento do setup. Uma prova válida para um commitment C só pode
 *      liquidar o processo que registrou exatamente C como esperado.
 *   2. **Proteção contra replay**: `require(!liquidado[processoId])` explícito
 *      antes de qualquer verificação.
 *   3. **Descoberta não é confiança**: mantém uma allowlist própria
 *      (`acceptedDomains`), chaveada no endereço resolvido, não no
 *      `domainId()` autodeclarado pelo domínio.
 *
 *   Não conhece o mecanismo por trás da liquidação: resolve `"PrivacyLayer"`
 *   por nome no registry e fala apenas a linguagem de `IPrivacyLayer`.
 */
contract HarpoSettlementConsumer is Ownable {
    /// @notice HarpoRegistry (address book) — imutável no consumidor.
    IHarpoRegistry public immutable registry;

    /// @notice Nome do domínio de settlement que o consumidor resolve (a "junta").
    string public constant DOMAIN_NAME = "PrivacyLayer";

    /// @notice endereço de domínio => aceito pela política PRÓPRIA deste consumidor?
    mapping(address => bool) public acceptedDomains;

    /// @notice processoId => commitment esperado (pré-registrado no setup do processo).
    mapping(bytes32 => bytes32) public expectedCommitment;

    /// @notice processoId => liquidado confidencialmente (replay guard explícito).
    mapping(bytes32 => bool) public liquidado;

    /// @notice processoId => domainId que efetivou a liquidação (rastro do mecanismo usado).
    mapping(bytes32 => string) public liquidadoPor;

    event DomainAccepted(address indexed domain, bool accepted);
    event SettlementExpected(bytes32 indexed processoId, bytes32 commitment);
    event Liquidado(bytes32 indexed processoId, address indexed domain, string domainId, bytes32 privacyModel);

    constructor(address registry_, address owner_) Ownable(owner_) {
        require(registry_ != address(0), "HarpoSettlementConsumer: registry zero");
        registry = IHarpoRegistry(registry_);
    }

    /// @notice Admite (ou revoga) um ENDEREÇO de domínio na política de aceitação própria.
    function setAcceptedDomain(address domain, bool accepted) external onlyOwner {
        require(domain != address(0), "HarpoSettlementConsumer: domain zero");
        acceptedDomains[domain] = accepted;
        emit DomainAccepted(domain, accepted);
    }

    event SettlementCancelled(bytes32 indexed processoId, bytes32 commitment);

    /// @notice Registra o commitment ESPERADO para um processo, no momento do setup —
    ///   antes de qualquer prova existir. Só pode ser feito uma vez por processo.
    function setExpectedSettlement(bytes32 processoId, bytes32 commitment) external onlyOwner {
        require(expectedCommitment[processoId] == bytes32(0), "HarpoSettlementConsumer: processo ja registrado");
        require(commitment != bytes32(0), "HarpoSettlementConsumer: commitment invalido");
        expectedCommitment[processoId] = commitment;
        emit SettlementExpected(processoId, commitment);
    }

    /// @notice Cancela um commitment esperado ainda NÃO liquidado, permitindo corrigir
    ///   um registro errado ou abortar um processo. Não afeta processos já liquidados.
    function cancelExpectedSettlement(bytes32 processoId) external onlyOwner {
        require(!liquidado[processoId], "HarpoSettlementConsumer: processo ja liquidado");
        bytes32 c = expectedCommitment[processoId];
        require(c != bytes32(0), "HarpoSettlementConsumer: processo nao registrado");
        delete expectedCommitment[processoId];
        emit SettlementCancelled(processoId, c);
    }

    /**
     * @notice Liquida um processo confidencialmente pelo domínio de settlement ATIVO no
     *   registry — mas só se: (a) esse endereço estiver na allowlist própria, (b) o
     *   processo tiver um commitment esperado pré-registrado, (c) o processo ainda não
     *   tiver sido liquidado. `commitment` não é parâmetro — é sempre o valor
     *   pré-registrado, nunca o que o chamador quiser submeter.
     */
    function liquidar(
        bytes32 processoId,
        bytes calldata proof,
        bytes calldata publicInputs
    ) external {
        require(!liquidado[processoId], "HarpoSettlementConsumer: processo ja liquidado");

        bytes32 commitment = expectedCommitment[processoId];
        require(commitment != bytes32(0), "HarpoSettlementConsumer: processo nao registrado");

        address domainAddr = registry.get(DOMAIN_NAME);
        require(acceptedDomains[domainAddr], "HarpoSettlementConsumer: domain fora da politica de aceitacao");

        IPrivacyLayer layer = IPrivacyLayer(domainAddr);
        bool ok = layer.verifyConfidentialSettlement(commitment, proof, publicInputs);
        require(ok, "HarpoSettlementConsumer: liquidacao confidencial invalida");

        // Uma única leitura de domainId(), reutilizada no storage e no evento,
        // para que os dois nunca divirjam.
        string memory usedDomainId = layer.domainId();
        liquidado[processoId] = true;
        liquidadoPor[processoId] = usedDomainId;
        emit Liquidado(processoId, domainAddr, usedDomainId, layer.privacyModel());
    }
}
