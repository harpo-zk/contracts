// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title HarpoRegistry — address book do protocolo (baixo acoplamento)
 * @notice Resolve nome -> endereço para os componentes do protocolo Harpo.
 *         Permite trocar uma "peça" (verifier, SMT, Poseidon, domínio...) de
 *         forma transparente: os consumidores resolvem a dependência pelo NOME
 *         em vez de endereço fixo. Cada atualização versiona e mantém histórico.
 *
 *         Atualização é restrita à role REGISTRY_ADMIN_ROLE. Leitura é pública.
 *
 * Uso típico:
 *   registry.set("Harpo", 0x...);              // admin publica/atualiza
 *   address harpo = registry.get("Harpo");     // consumidor resolve
 */
contract HarpoRegistry is AccessControl {
    bytes32 public constant REGISTRY_ADMIN_ROLE = keccak256("REGISTRY_ADMIN_ROLE");

    struct Record {
        address addr;       // endereço atual
        uint64 version;     // incrementa a cada set (1 = primeira publicação)
        uint64 updatedAt;   // timestamp da última atualização
    }

    mapping(bytes32 => Record) private _records;      // key(nome) -> registro atual
    mapping(bytes32 => address[]) private _history;   // key(nome) -> histórico de endereços
    mapping(bytes32 => string) private _names;        // key(nome) -> nome legível
    mapping(bytes32 => bool) private _known;          // já existe?
    bytes32[] private _keys;                          // enumeração dos nomes

    event Registered(
        bytes32 indexed key,
        string name,
        address indexed addr,
        uint64 version,
        address previous
    );

    /// @param admin recebe DEFAULT_ADMIN_ROLE (gerência de roles) e REGISTRY_ADMIN_ROLE (atualizar o livro).
    constructor(address admin) {
        require(admin != address(0), "HarpoRegistry: admin zero");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRY_ADMIN_ROLE, admin);
    }

    /// @notice Hash do nome usado como chave de armazenamento.
    function keyOf(string memory name) public pure returns (bytes32) {
        return keccak256(bytes(name));
    }

    /// @notice Publica ou atualiza o endereço de um componente. Só ADMIN.
    function set(string calldata name, address addr) external onlyRole(REGISTRY_ADMIN_ROLE) {
        require(addr != address(0), "HarpoRegistry: endereco zero");
        bytes32 k = keccak256(bytes(name));
        Record storage r = _records[k];
        address previous = r.addr;

        r.addr = addr;
        r.version += 1;
        r.updatedAt = uint64(block.timestamp);
        _history[k].push(addr);

        if (!_known[k]) {
            _known[k] = true;
            _keys.push(k);
            _names[k] = name;
        }

        emit Registered(k, name, addr, r.version, previous);
    }

    /// @notice Atualiza vários de uma vez (útil pra semear o livro pós-migração). Só ADMIN.
    function setMany(string[] calldata namesArr, address[] calldata addrs) external onlyRole(REGISTRY_ADMIN_ROLE) {
        require(namesArr.length == addrs.length, "HarpoRegistry: tamanhos diferentes");
        for (uint256 i = 0; i < namesArr.length; i++) {
            _set(namesArr[i], addrs[i]);
        }
    }

    /// @notice Resolve nome -> endereço. Reverte se não existir.
    function get(string calldata name) external view returns (address) {
        address a = _records[keccak256(bytes(name))].addr;
        require(a != address(0), "HarpoRegistry: nao encontrado");
        return a;
    }

    /// @notice Resolve nome -> endereço, retornando address(0) se não existir (sem reverter).
    function tryGet(string calldata name) external view returns (address) {
        return _records[keccak256(bytes(name))].addr;
    }

    /// @notice Registro completo (endereço + versão + timestamp).
    function record(string calldata name) external view returns (address addr, uint64 version, uint64 updatedAt) {
        Record storage r = _records[keccak256(bytes(name))];
        return (r.addr, r.version, r.updatedAt);
    }

    /// @notice Histórico de todos os endereços já publicados sob um nome.
    function history(string calldata name) external view returns (address[] memory) {
        return _history[keccak256(bytes(name))];
    }

    /// @notice Total de nomes registrados.
    function count() external view returns (uint256) {
        return _keys.length;
    }

    /// @notice Nome legível a partir da chave (para enumeração).
    function nameAt(uint256 index) external view returns (string memory) {
        return _names[_keys[index]];
    }

    // -- interno --
    function _set(string calldata name, address addr) internal {
        require(addr != address(0), "HarpoRegistry: endereco zero");
        bytes32 k = keccak256(bytes(name));
        Record storage r = _records[k];
        address previous = r.addr;
        r.addr = addr;
        r.version += 1;
        r.updatedAt = uint64(block.timestamp);
        _history[k].push(addr);
        if (!_known[k]) {
            _known[k] = true;
            _keys.push(k);
            _names[k] = name;
        }
        emit Registered(k, name, addr, r.version, previous);
    }
}
