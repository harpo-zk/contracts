// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";

contract PubNonFungibleAsset is ERC1155 {
    // Mapping from token ID to metadata URI
    mapping(uint256 => string) private _tokenURIs;
    
    // Counter for generating unique token IDs
    uint256 private _tokenIdCounter;

    // Events
    event TokenMinted(address indexed to, uint256 indexed tokenId, uint256 amount, string uri);
    event TokenBurned(address indexed from, uint256 indexed tokenId, uint256 amount);

    constructor() ERC1155("") {
        _tokenIdCounter = 0;
    }

    /**
     * @dev Mints a new token.
     * @param to The address that will receive the minted token
     * @param amount The amount of tokens to mint
     * @param uri The metadata URI for the token
     * @return tokenId The ID of the minted token
     */
    function mintTo(
        address to,
        uint256 amount,
        string memory uri
    ) public 
    //onlyOwner 
    returns (uint256) {
        require(to != address(0), "Invalid recipient address");
        require(bytes(uri).length > 0, "URI cannot be empty");

        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;

        _mint(to, tokenId, amount, "");
        _setURI(tokenId, uri);

        emit TokenMinted(to, tokenId, amount, uri);
        return tokenId;
    }



    /**
     * @dev Burns tokens.
     * @param tokenId The ID of the token to burn
     * @param amount The amount of tokens to burn
     */
    function burn(uint256 tokenId, uint256 amount) public {
        require(balanceOf(msg.sender, tokenId) >= amount, "Insufficient balance");
        _burn(msg.sender, tokenId, amount);
        emit TokenBurned(msg.sender, tokenId, amount);
    }

    function burnFrom(address from, uint256 tokenId, uint256 amount) public {
        require(balanceOf(from, tokenId) >= amount, "Insufficient balance");
        
        _burn(from, tokenId, amount);
        emit TokenBurned(from, tokenId, amount);
    }

    /**
     * @dev Sets the URI for a token type.
     * @param tokenId The ID of the token
     * @param uri The metadata URI
     */
    function _setURI(uint256 tokenId, string memory uri) internal {
        _tokenURIs[tokenId] = uri;
    }

    /**
     * @dev Returns the URI for a token type.
     * @param tokenId The ID of the token
     */
    function uri(uint256 tokenId) public view virtual override returns (string memory) {
        return _tokenURIs[tokenId];
    }

    /**
     * @dev See {IERC1155-safeTransferFrom}.
     * Overridden to add custom transfer logic if needed
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public virtual override {
        require(
            from == msg.sender || isApprovedForAll(from, msg.sender),
            "Caller is not owner nor approved"
        );
        super.safeTransferFrom(from, to, id, amount, data);
    }

    /**
     * @dev See {IERC1155-safeBatchTransferFrom}.
     * Overridden to add custom batch transfer logic if needed
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public virtual override {
        require(
            from == msg.sender || isApprovedForAll(from, msg.sender),
            "Caller is not owner nor approved"
        );
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    /**
     * @dev Returns the total number of token types minted.
     */
    function totalTokenTypes() public view returns (uint256) {
        return _tokenIdCounter;
    }

    /**
     * @dev Mints a new token (compatibility function).
     * @param secret The secret data for the token
     * @param amount The amount of tokens to mint
     * @param proof The proof for the mint operation
     * @param sender The address that will receive the minted token
     */
    function mint(
        uint256[15] memory secret,
        uint256 amount,
        Proof4 memory proof,
        address sender
    ) public {
        require(sender != address(0), "Invalid sender address");
        require(amount > 0, "Amount must be greater than zero");

        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;

        _mint(sender, tokenId, amount, "");
        _setURI(tokenId, ""); // Empty URI for compatibility

        emit TokenMinted(sender, tokenId, amount, "");
    }

    // Add Proof4 struct for compatibility
    struct Proof4 {
        uint[2] pA;
        uint[2][2] pB;
        uint[2] pC;
        uint[4] inR;
    }
} 