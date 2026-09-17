// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title HarpoSelectiveDisclosure — disclosure escopada, com threshold e trilha
 * @notice Autoriza a abertura de UMA transação para auditoria (por `commitment`),
 *   exigindo um THRESHOLD `t`-de-`n` de autoridades (nenhum auditor abre sozinho)
 *   e REGISTRANDO tudo on-chain (auditando o auditor). A decriptação do auditSecret
 *   segue off-chain, mas só é legítima quando `isDisclosureGranted` for true.
 *
 *   Contrasta com o modelo de "view key global", onde um único auditor vê tudo.
 */
contract HarpoSelectiveDisclosure {
    address public admin;
    mapping(address => bool) public isAuthority;
    uint256 public authorityCount;
    uint256 public threshold;

    struct Request {
        address requester;
        string reason;
        uint64 createdAt;
        uint64 approvals;
        bool granted;
    }
    mapping(bytes32 => Request) public requests;                       // commitment -> pedido
    mapping(bytes32 => mapping(address => bool)) public approvedBy;    // commitment -> autoridade -> aprovou?

    event AuthoritySet(address indexed who, bool enabled);
    event ThresholdSet(uint256 t);
    event DisclosureRequested(bytes32 indexed commitment, address indexed requester, string reason);
    event DisclosureApproved(bytes32 indexed commitment, address indexed authority, uint64 approvals);
    event DisclosureGranted(bytes32 indexed commitment, uint64 approvals);

    modifier onlyAdmin() { require(msg.sender == admin, "nao admin"); _; }
    modifier onlyAuthority() { require(isAuthority[msg.sender], "nao autoridade"); _; }

    constructor(address admin_, address[] memory authorities_, uint256 threshold_) {
        require(admin_ != address(0), "admin zero");
        admin = admin_;
        for (uint256 i = 0; i < authorities_.length; i++) {
            address a = authorities_[i];
            if (a != address(0) && !isAuthority[a]) {
                isAuthority[a] = true;
                authorityCount++;
                emit AuthoritySet(a, true);
            }
        }
        require(threshold_ > 0 && threshold_ <= authorityCount, "threshold invalido");
        threshold = threshold_;
        emit ThresholdSet(threshold_);
    }

    // -- gestão (admin) --
    function setAuthority(address who, bool enabled) external virtual onlyAdmin {
        if (enabled && !isAuthority[who]) { isAuthority[who] = true; authorityCount++; }
        else if (!enabled && isAuthority[who]) { isAuthority[who] = false; authorityCount--; }
        require(threshold <= authorityCount, "threshold > n");
        emit AuthoritySet(who, enabled);
    }

    function setThreshold(uint256 t) external virtual onlyAdmin {
        require(t > 0 && t <= authorityCount, "threshold invalido");
        threshold = t;
        emit ThresholdSet(t);
    }

    // -- fluxo de disclosure --

    /// @notice Uma autoridade abre um pedido ESCOPADO a um commitment, com motivo (logado).
    ///   O próprio solicitante já conta como 1 aprovação.
    function requestDisclosure(bytes32 commitment, string calldata reason) public virtual onlyAuthority {
        require(requests[commitment].createdAt == 0, "ja solicitado");
        Request storage r = requests[commitment];
        r.requester = msg.sender;
        r.reason = reason;
        r.createdAt = uint64(block.timestamp);
        emit DisclosureRequested(commitment, msg.sender, reason);
        _approve(commitment);
    }

    /// @notice Outra autoridade aprova. Ao atingir o threshold, a disclosure é concedida (e logada).
    function approveDisclosure(bytes32 commitment) external onlyAuthority {
        require(requests[commitment].createdAt != 0, "sem pedido");
        _approve(commitment);
    }

    function _approve(bytes32 commitment) internal {
        require(!approvedBy[commitment][msg.sender], "ja aprovou");
        approvedBy[commitment][msg.sender] = true;
        Request storage r = requests[commitment];
        r.approvals += 1;
        emit DisclosureApproved(commitment, msg.sender, r.approvals);
        if (!r.granted && r.approvals >= threshold) {
            r.granted = true;
            emit DisclosureGranted(commitment, r.approvals);
        }
    }

    /// @notice True se a abertura desta transação foi legitimamente autorizada (threshold atingido).
    function isDisclosureGranted(bytes32 commitment) external view returns (bool) {
        return requests[commitment].granted;
    }
}
