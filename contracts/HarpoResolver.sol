// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IHarpoRegistry {
    function get(string calldata name) external view returns (address);
    function record(string calldata name) external view returns (address addr, uint64 version, uint64 updatedAt);
    function tryGet(string calldata name) external view returns (address);
}

/**
 * @title HarpoResolver — resolução de componentes via registry, com auditoria por uso
 * @notice Mixin que consumidores herdam para resolver dependências pelo NOME
 *   (pull: sempre a versão corrente do registry), SEM cachear e SEM precisar ser
 *   avisado de updates.
 *
 *   Por que PULL e não PUSH (updateAddress): no push o registry teria que conhecer
 *   TODOS os consumidores para avisá-los — um contrato novo/desconhecido ficaria de
 *   fora, e manter a lista vira um loop de gas ilimitado. Com pull o consumidor
 *   resolve sozinho; não há lista para manter. Trocar uma peça = 1 `registry.set()`
 *   do admin (idealmente atrás de timelock/governança).
 *
 *   AUDITABILIDADE: `_use()` resolve E emite um evento com exatamente qual
 *   (endereço, versão) foi usado nesta transação — prova on-chain imutável de
 *   "qual verifier validou a tx X?", a cada chamada. `_resolve()` é a via barata
 *   (view, sem evento) para leituras não-críticas.
 */
abstract contract HarpoResolver {
    IHarpoRegistry public immutable registry;

    /// @notice Emitido a cada uso auditável — trilha de qual implementação foi usada.
    event ComponentUsed(bytes32 indexed key, string name, address impl, uint64 version);

    constructor(address registry_) {
        require(registry_ != address(0), "HarpoResolver: registry zero");
        registry = IHarpoRegistry(registry_);
    }

    /// @notice Resolve o endereço corrente (view, barato, sem auditoria).
    function _resolve(string memory name) internal view returns (address) {
        return registry.get(name);
    }

    /// @notice Resolve + emite qual (endereço, versão) foi usado nesta tx.
    /// @dev Use em operações críticas (ex.: verificação de prova) para auditoria por chamada.
    function _use(string memory name) internal returns (address impl) {
        uint64 version;
        (impl, version, ) = registry.record(name);
        require(impl != address(0), "HarpoResolver: componente nao encontrado");
        emit ComponentUsed(keccak256(bytes(name)), name, impl, version);
    }
}
