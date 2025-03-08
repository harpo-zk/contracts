// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Harpo} from "./Harpo.sol";
import {PubAsset} from "./PubAsset.sol";

contract SwapPub2Priv {
    PubAsset pubAsset;
    Harpo privAsset;
    
    event SwapExecuted(address indexed user, uint256 amount);

    constructor(address _pubAsset, address _privAsset) {
        pubAsset = PubAsset(_pubAsset);
        privAsset = Harpo(_privAsset);
    }
    struct Proof4 {
        uint[2] pA;
        uint[2][2] pB;
        uint[2] pC;
        uint[4] inR;
    }

    function swap(address sender, uint256 amount, uint256[15] memory secret, Harpo.Proof4 memory proof) external {
        require(amount > 0, "Amount must be greater than zero");
        require(pubAsset.balanceOf(sender) >= amount, "Insufficient balance");

        require(pubAsset.burnFrom(sender, amount), "Transfer failed");        
        privAsset.mint(secret, amount, proof,sender);

        emit SwapExecuted(sender, amount);
    }
    
}
