// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Harpo} from "./Harpo.sol";
import {PubAsset} from "./PubAsset.sol";

contract SwapPriv2Pub {
    PubAsset pubAsset;
    Harpo privAsset;

    event SwapExecuted(address indexed user, uint256 amount);

    constructor(address _pubAsset, address _privAsset) {
        pubAsset = PubAsset(_pubAsset);
        privAsset = Harpo(_privAsset);
    }

    function swap(
        address sender,
        uint256 amount,
        uint256 nullifier,
        uint256 merkleRoot,
        Harpo.Proof memory proof
    ) external {
        require(amount > 0, "Amount must be greater than zero");

        privAsset.burn(nullifier, amount, proof, sender);

        pubAsset.mintTo(sender, amount);

        emit SwapExecuted(sender, amount);
    }
}
