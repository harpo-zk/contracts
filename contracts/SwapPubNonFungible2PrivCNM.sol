// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Harpo} from "./Harpo.sol";
import {PubNonFungibleAsset} from "./PubNonFungibleAsset.sol";

contract SwapPubNonFungible2PrivCNM {
    PubNonFungibleAsset nftAsset;
    Harpo privAsset;
    
    event SwapExecuted(address indexed user);

    constructor(address _nftAsset, address _privAsset) {
        nftAsset = PubNonFungibleAsset(_nftAsset);
        privAsset = Harpo(_privAsset);
    }

    function swap(address sender, uint256 tokenId, uint256[15] memory secret, Harpo.Proof memory proof) external {      
        // Verificar se o sender possui o token (ERC1155)
        require(nftAsset.balanceOf(sender, tokenId) > 0, "Not token owner");    
        
        // Mint no contrato privado
        privAsset.mint(secret, 1, proof, sender);

        emit SwapExecuted(sender);
    }
    
} 