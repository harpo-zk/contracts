// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract PubKeyRegistry {
    struct KeyPair {
        uint256[2] babyJubJubKey;
        bool exists;
    }

    mapping(address => KeyPair) private ethToJubJub;
    mapping(bytes32 => address) private jubJubToEth;

    event KeyRegistered(address indexed ethAddress, uint256[2] babyJubJubKey);    
    
    function registerKeys(address ethpubKey, uint256[2] memory babyJubJubKey) external {
        require(!ethToJubJub[ethpubKey].exists, "Key already exists");

        ethToJubJub[ethpubKey] = KeyPair(babyJubJubKey, true);

        bytes32 jubJubHash = keccak256(abi.encodePacked(babyJubJubKey[0], babyJubJubKey[1]));
        jubJubToEth[jubJubHash] = ethpubKey;

        emit KeyRegistered(ethpubKey, babyJubJubKey);
    }
    
    function getBabyJubJubKey(address ethAddress) external view returns (uint256[2] memory) {
        require(ethToJubJub[ethAddress].exists, "Key not found");
        return ethToJubJub[ethAddress].babyJubJubKey;
    }
    
    function getEthereumAddress(uint256[2] memory babyJubJubKey) external view returns (address) {
        bytes32 jubJubHash = keccak256(abi.encodePacked(babyJubJubKey[0], babyJubJubKey[1]));
        address ethAddress = jubJubToEth[jubJubHash];
        require(ethAddress != address(0), "Ethereum address not found");
        return ethAddress;
    }
}
