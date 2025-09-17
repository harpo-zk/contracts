// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract PubKeyRegistry is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    constructor() {
        // Define o deployer como Admin e DEFAULT_ADMIN_ROLE
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function grantRoleAdmin(address account) public onlyRole(ADMIN_ROLE) {
        _grantRole(ADMIN_ROLE, account);
    }

    function revokeRoleAdmin(address account) public onlyRole(ADMIN_ROLE) {
        _revokeRole(ADMIN_ROLE, account);
    }
    
    modifier onlyAuthorizedAccount(address ethAddress) {
        // Somente o Admin ou o dono da conta podem registrar uma chave
        require(hasRole(ADMIN_ROLE, msg.sender) || ethAddress == msg.sender, "Not authorized Account");
        _;
    }

    struct KeyPair {
        uint256[2] babyJubJubKey;
        bool exists;
    }

    mapping(address => KeyPair) private ethToJubJub;

    event KeyRegistered(address indexed ethAddress, uint256[2] babyJubJubKey);    
     
    function registerKeys(address ethpubKey, uint256[2] memory babyJubJubKey) external onlyAuthorizedAccount(ethpubKey) {
        require(!ethToJubJub[ethpubKey].exists, "Key already exists");
        ethToJubJub[ethpubKey] = KeyPair(babyJubJubKey, true);
        emit KeyRegistered(ethpubKey, babyJubJubKey);
    }
    
    function getBabyJubJubKey(address ethAddress) external view returns (uint256[2] memory) {
        require(ethToJubJub[ethAddress].exists, "Key not found");
        return ethToJubJub[ethAddress].babyJubJubKey;
    }
}
