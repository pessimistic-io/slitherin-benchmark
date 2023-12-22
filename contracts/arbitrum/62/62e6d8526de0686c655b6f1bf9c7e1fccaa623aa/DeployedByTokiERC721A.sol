/**
    TokiBot
    Toki Bot is a Telegram bot that was created with the aim of making contract creation accessible to everyone.

    Website: https://tokibot.xyz/
    Twitter: https://twitter.com/tokigenerator
    Telegram: t.me/tokigenerator
    Telegram Bot: t.me/tokigenerator_bot
**/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC721A.sol";
import "./Strings.sol";
import "./Ownable.sol";

/**
 * @title ERC20CustomF
 * @dev This contract implements an ERC-721 compatible NFT contract with custom features.
 */
contract DeployedByTokiERC721A is ERC721A, Ownable {

    using Strings for uint256;

    string public baseURI;
    string public baseExtension = ".json";
    bool public saleIsActive = true;
    uint256 public mintPrice;
    uint256 public maxSupply;

    /**
     * @dev Emitted when the contract owner withdraws the contract's balance.
     * @param amount The amount of ether withdrawn.
     */
    event Withdraw(uint256 amount);

    /**
     * @dev Initializes the ERC20CustomF contract with the given parameters.
     * @param _name The name of the NFT contract.
     * @param _symbol The symbol of the NFT contract.
     * @param _baseURI The base URI used for metadata.
     * @param _maxSupply The maximum supply of NFTs that can be minted.
     * @param _mintPrice The price in wei to mint a single NFT.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseURI,
        uint256 _maxSupply,
        uint256 _mintPrice
    ) ERC721A(_name, _symbol) {
        baseURI = _baseURI;
        maxSupply = _maxSupply;
        mintPrice = _mintPrice;
    }

    /**
     * @dev Mints NFTs by users when the sale is active and they send enough Ether.
     * @param _quantity The number of NFTs to mint.
     *
     * Requirements:
     * - The sale must be active (saleIsActive is true).
     * - The `msg.sender` must send enough Ether to cover the minting cost.
     * - The total supply of NFTs after minting must not exceed the maximum supply.
     * Emits a {Transfer} event for each minted token.
     */
    function mint(uint16 _quantity) public payable {
        require(saleIsActive, "Sale must be active to mint tokens");
        require(msg.value >= mintPrice * _quantity, "Not enough funds");
        uint256 supply = totalSupply();
        require(supply + _quantity <= maxSupply, "Max supply exceeded");
        _safeMint(msg.sender, _quantity);
    }

    /**
     * @dev Sets the base URI used for metadata of the NFTs.
     * @param _baseURI The new base URI.
     * Only the contract owner can call this function.
     */
    function setBaseURI(string memory _baseURI) public onlyOwner {
        baseURI = _baseURI;
    }

    /**
     * @dev Sets whether or not the NFT sale is active.
     * @param isActive Whether or not the sale will be active.
     * Only the contract owner can call this function.
     */
    function setSaleIsActive(bool isActive) external onlyOwner {
        saleIsActive = isActive;
    }

    /**
     * @dev Sets the price in wei to mint a single NFT.
     * @param _newMintPrice The new mint price.
     * Only the contract owner can call this function.
     */
    function setMintPrice(uint256 _newMintPrice) public onlyOwner {
        mintPrice = _newMintPrice;
    }

    /**
     * @dev Returns the metadata URI for a specific NFT token.
     * @param _tokenId The ID of the NFT token.
     * @return The metadata URI of the token.
     * Requires the token to exist (the token with the given ID must exist).
     */
    function tokenURI(uint _tokenId) public view virtual override returns (string memory) {
        require(_exists(_tokenId), "URI query for nonexistent token");
        return string(abi.encodePacked(baseURI, _tokenId.toString(), baseExtension));
    }

    /**
     * @dev A way for the owner to reserve a specific number of NFTs without having to
     * interact with the sale.
     * @param _quantity The number of NFTs to reserve.
     * Only the contract owner can call this function.
     */
    function reserve(uint256 _quantity) external onlyOwner {
        uint256 supply = totalSupply();
        require(supply + _quantity <= maxSupply, "Max supply exceeded");
        _safeMint(msg.sender, _quantity);
    }

    /**
     * @dev Withdraws the contract's balance to the owner.
     *
     * Requirements:
     * - The caller must be the contract owner.
     * - The contract must have a positive balance to withdraw.
     *
     * Emits a {Withdraw} event on successful withdrawal.
     */
    function withdraw() public onlyOwner {
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "No funds to withdraw");

        (bool success, ) = payable(owner()).call{value: contractBalance}("");
        require(success, "Withdrawal failed");

        emit Withdraw(contractBalance);
    }

}
