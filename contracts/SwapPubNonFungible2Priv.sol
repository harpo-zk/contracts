// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Harpo} from "./Harpo.sol";
import {PubNonFungibleAsset} from "./PubNonFungibleAsset.sol";

contract SwapPubNonFungible2Priv {
    PubNonFungibleAsset pubNonFungibleAsset;
    Harpo privAsset;
    
    event SwapExecuted(address indexed user, uint256 amount);

    constructor(address _pubNonFungibleAsset, address _privAsset) {
        pubNonFungibleAsset = PubNonFungibleAsset(_pubNonFungibleAsset);
        privAsset = Harpo(_privAsset);
    }

    function swap(address sender, uint256 tokenId, uint256 amount, uint256[15] memory secret, Harpo.Proof memory proof) external {
        require(amount > 0, "Amount must be greater than zero");        
        // Verificar saldo
        uint256 balance = pubNonFungibleAsset.balanceOf(sender, tokenId);
        require(balance >= amount, "Insufficient balance");        
        
        pubNonFungibleAsset.burnFrom(sender, tokenId, amount);
        
        // Mint no contrato privado
        privAsset.mint(secret, amount, proof, sender);

        emit SwapExecuted(sender, amount);
    }

    function balanceOf(address account, uint256 tokenId) external view returns (uint256) {
        return pubNonFungibleAsset.balanceOf(account, tokenId);
    }
} 