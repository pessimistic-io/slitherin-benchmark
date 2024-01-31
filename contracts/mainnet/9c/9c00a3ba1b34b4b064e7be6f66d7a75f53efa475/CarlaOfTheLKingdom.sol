// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./ERC721A.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./Strings.sol";


/// @title Carla of the L Kingdom
/// @notice  https://twitter.com/CarlaoftheL
contract CarlaOfTheLKingdom is ERC721A, Ownable {
    using SafeMath for uint256;
    using Strings for uint256;

    uint256 public constant price = 0.05 ether;
    bool public publicSaleStarted = false;
    uint256 public  MAX_SUPPLY = 53;
    string public baseURI = "ipfs://Qmd2crrwsXGVEQ9HxxgCoZAzPiUufJLL57SWeAEKVbCcTf/";

    constructor() ERC721A("CarlaOfTheLKingdom", "CarlaOfTheLKingdom") {
    }

    function togglePublicSaleStarted() external onlyOwner {
        publicSaleStarted = !publicSaleStarted;
    }

    function setBaseURI(string memory _newBaseURI) external onlyOwner {
        baseURI = _newBaseURI;
    }

    function setMaxSupply(uint256 _new_max_supply) external onlyOwner {
        MAX_SUPPLY = _new_max_supply;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        return super.tokenURI(tokenId);
    }


    /// Public Sale mint function
    /// @param tokens number of tokens to mint
    /// @dev reverts if any of the public sale preconditions aren't satisfied
    function mint(uint256 tokens) external payable {
        require(publicSaleStarted, "Carla of the L Kingdom: Public sale has not started");
        require(totalSupply() + tokens <= MAX_SUPPLY, "Carla of the L Kingdom: Minting would exceed max supply");
        require(tokens > 0, "Carla of the L Kingdom: Must mint at least one token");
        require(price * tokens == msg.value, "Carla of the L Kingdom: ETH amount is incorrect");
        _safeMint(_msgSender(), tokens);
    }

    /// Distribute funds to wallets
    function withdrawAll() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "Carla of the L Kingdom: Insufficient balance");
        _withdraw(owner(), address(this).balance);
    }

    function _withdraw(address _address, uint256 _amount) private {
        (bool success,) = _address.call{value : _amount}("");
        require(success, "Carla of the L Kingdom: Failed to withdraw Ether");
    }

}

