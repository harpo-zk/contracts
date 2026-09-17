// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title IHarpoRegistry — superfície mínima do registry usada pelo guardião.
interface IHarpoRegistry {
    function set(string calldata name, address addr) external;
}

/**
 * @title HarpoRegistryGuardian — M-de-N + timelock na frente do HarpoRegistry
 * @notice Este contrato detém a `REGISTRY_ADMIN_ROLE` de um `HarpoRegistry` e é o
 *         único autorizado a chamar `registry.set`. Nenhuma chave única troca um
 *         componente sozinha: uma proposta só é executada depois de M-de-N
 *         guardiões aprovarem e do timelock (delay) vencer — o proponente já
 *         conta como 1 aprovação.
 *
 *         Controle do registry:
 *           grantRole(REGISTRY_ADMIN_ROLE, guardian)  + renounceRole do admin antigo
 *         Deploy do guardião:
 *           new HarpoRegistryGuardian(registry, [g1, g2, ...], M, delay)
 */
contract HarpoRegistryGuardian {
    // ── estado ────────────────────────────────────────────────────────────────────
    /// @notice HarpoRegistry sob guarda (immutable — nunca muda).
    address public immutable registry;
    /// @notice Conjunto de guardiões (M-de-N).
    address[] public guardians;
    /// @notice Mínimo de aprovações (M) para executar uma proposta.
    uint256 public threshold;
    /// @notice Timelock em segundos: proposta só executa após eta = criação + delay.
    uint64 public delay;

    /// @notice Proposta de set(name, addr) aguardando M aprovações + timelock.
    struct Proposal {
        string name;      // nome do componente no registry
        address addr;     // novo endereço
        uint64 eta;       // block.timestamp a partir do qual pode executar
        uint64 approvals; // total de votos a favor
        bool executed;    // já executada (não re-executa)
    }

    Proposal[] public proposals;
    mapping(uint256 => mapping(address => bool)) public approvedBy;

    // ── eventos ───────────────────────────────────────────────────────────────────
    event GuardianSet(address indexed guardian, bool enabled);
    event ProposalCreated(uint256 indexed id, string name, address addr, uint64 eta, address indexed proposer);
    event ProposalApproved(uint256 indexed id, address indexed guardian, uint64 approvals);
    event ProposalExecuted(uint256 indexed id, string name, address addr);

    modifier onlyGuardian() {
        require(isGuardian(msg.sender), "HarpoRegistryGuardian: nao e guardian");
        _;
    }

    /// @param registry_ HarpoRegistry que este contrato passa a controlar.
    /// @param guardians_ Guardiões (sem duplicatas).
    /// @param threshold_ M: mínimo de aprovações para executar (1 <= M <= N).
    /// @param delay_ Timelock em segundos (> 0).
    constructor(address registry_, address[] memory guardians_, uint256 threshold_, uint64 delay_) {
        require(registry_ != address(0), "HarpoRegistryGuardian: registry zero");
        require(threshold_ > 0 && threshold_ <= guardians_.length, "HarpoRegistryGuardian: threshold invalido");
        require(delay_ > 0, "HarpoRegistryGuardian: delay zero");
        registry = registry_;
        threshold = threshold_;
        delay = delay_;
        for (uint256 i = 0; i < guardians_.length; i++) {
            address g = guardians_[i];
            require(g != address(0), "HarpoRegistryGuardian: guardian zero");
            require(!isGuardian(g), "HarpoRegistryGuardian: guardian duplicado");
            guardians.push(g);
            emit GuardianSet(g, true);
        }
    }

    /// @notice Um endereço é guardião (tem direito a voto)?
    function isGuardian(address who) public view returns (bool) {
        for (uint256 i = 0; i < guardians.length; i++) {
            if (guardians[i] == who) return true;
        }
        return false;
    }

    /// @notice Cria proposta de set(name, addr). O proponente já conta como 1 aprovação.
    /// @return id Identificador da proposta (índice em `proposals`).
    function proposeSet(string calldata name, address addr) external onlyGuardian returns (uint256 id) {
        require(addr != address(0), "HarpoRegistryGuardian: endereco zero");
        id = proposals.length;
        uint64 eta = uint64(block.timestamp) + delay;
        proposals.push(Proposal({ name: name, addr: addr, eta: eta, approvals: 1, executed: false }));
        approvedBy[id][msg.sender] = true;
        emit ProposalCreated(id, name, addr, eta, msg.sender);
        emit ProposalApproved(id, msg.sender, 1);
    }

    /// @notice Voto a favor da proposta `id` (1 voto por guardião; sem repetir).
    function approveSet(uint256 id) external onlyGuardian {
        Proposal storage p = proposals[id];
        require(!p.executed, "HarpoRegistryGuardian: proposta executada");
        require(!approvedBy[id][msg.sender], "HarpoRegistryGuardian: ja aprovou");
        approvedBy[id][msg.sender] = true;
        p.approvals += 1;
        emit ProposalApproved(id, msg.sender, p.approvals);
    }

    /// @notice Executa a proposta: M aprovações + timelock vencido → registry.set.
    function executeSet(uint256 id) external onlyGuardian {
        Proposal storage p = proposals[id];
        require(p.approvals >= threshold, "HarpoRegistryGuardian: aprovacoes insuficientes");
        require(block.timestamp >= p.eta, "HarpoRegistryGuardian: timelock nao venceu");
        require(!p.executed, "HarpoRegistryGuardian: proposta executada");
        p.executed = true;
        IHarpoRegistry(registry).set(p.name, p.addr);
        emit ProposalExecuted(id, p.name, p.addr);
    }
}
