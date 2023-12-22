// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./ERC721Enumerable.sol";

contract NftSale is ERC721Enumerable, Ownable, ReentrancyGuard {
    using Strings for uint256;

    string private _baseTokenURI = "https://";

    uint256 public maxSupply = 1250;

    uint256 public pricePerToken = 0.1 ether; //0.1 ETH

    bool public saleLive = false;

    uint256 public limitPerWallet =  10;

    constructor() ERC721("Dubble Pass NFT", "DNFT") {}

    /**
     * @dev Allows the public to buy multiple tokens.
     * @param _amount The number of tokens to purchase.
     */
    function publicBuy(uint256 _amount) external payable nonReentrant{
        require(saleLive, "not live");
        require(totalSupply() + _amount <= maxSupply, "out of stock");
        require(pricePerToken * _amount <= msg.value, "low amount");
        require(balanceOf(msg.sender) <= limitPerWallet, "you have reached the limit");
        for(uint256 i; i < _amount; ++i){
            _safeMint(msg.sender, totalSupply() + 1);
        }
        (bool success, ) =  owner().call{value: address(this).balance}("");
        require(success, "funds were not transferred");
    }

    /**
     * @dev Allows the admin to mint tokens for giveaways, airdrops, etc.
     * @param qty The number of tokens to mint.
     * @param to The address to receive the minted tokens.
     */
    function adminMint(uint256 qty, address to) public onlyOwner {
        require(qty > 0, "minimum 1 token");
        require(totalSupply() + qty <= maxSupply, "out of stock");
        for (uint256 i = 0; i < qty; i++) {
            _safeMint(to, totalSupply() + 1);
        }
    }

    /**
     * @dev Returns an array of token IDs owned by a given address.
     * @param _owner The address to query.
     * @return An array of token IDs.
     */
    function tokensOfOwner(address _owner) public view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(_owner);
        if (tokenCount == 0) {
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount);
            uint256 index;
            for (index = 0; index < tokenCount; index++) {
                result[index] = tokenOfOwnerByIndex(_owner, index);
            }
            return result;
        }
    }

    /**
     * @dev Burns a token.
     * @param tokenId The ID of the token to burn.
     */
    function burn(uint256 tokenId) public virtual {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "caller is not owner nor approved");
        _burn(tokenId);
    }

    /**
     * @dev Checks if a token with the given ID exists.
     * @param _tokenId The ID of the token to check.
     * @return A boolean indicating whether the token exists.
     */
    function exists(uint256 _tokenId) external view returns (bool) {
        return _exists(_tokenId);
    }

    /**
     * @dev Checks if the spender is approved or the owner of the token.
     * @param _spender The address to check.
     * @param _tokenId The ID of the token to check.
     * @return A boolean indicating whether the spender is approved or the owner of the token.
     */
    function isApprovedOrOwner(address _spender, uint256 _tokenId) external view returns (bool) {
        return _isApprovedOrOwner(_spender, _tokenId);
    }

    /**
     * @dev Returns the URI for a given token.
     * @param _tokenId The ID of the token.
     * @return The URI string for the token.
     */
    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        require(_exists(_tokenId), "ERC721Metadata: URI query for nonexistent token");
        return string(abi.encodePacked(_baseTokenURI, _tokenId.toString(), ".json"));
    }

    /**
     * @dev Sets the base URI for all tokens.
     * @param newBaseURI The new base URI.
     */
    function setBaseURI(string memory newBaseURI) public onlyOwner {
        _baseTokenURI = newBaseURI;
    }

    /**
     * @dev Sets limit per wallet.
     * @param newLimit The new limit.
     */
    function setLimit(uint256 newLimit) public onlyOwner {
        limitPerWallet = newLimit;
    }

    /**
     * @dev Allows the owner to withdraw contract earnings.
     */
    function withdrawEarnings() public onlyOwner {
        require(address(this).balance > 0, "contract has not funds");
        (bool success, ) =  owner().call{value: address(this).balance}("");
        require(success, "funds were not transferred");
    }

    /**
     * @dev Toggles the sale status (live or not live).
     */
    function toggleSaleStatus() external onlyOwner {
        saleLive = !saleLive;
    }

    /**
     * @dev Changes the price per token.
     * @param newPrice The new price per token.
     */
    function changePrice(uint256 newPrice) external onlyOwner {
        pricePerToken = newPrice;
    }

    /**
     * @dev Decreases the maximum supply.
     * @param newMaxSupply The new maximum supply.
     */
    function decreaseMaxSupply(uint256 newMaxSupply) external onlyOwner {
        require(newMaxSupply < maxSupply, "you can only decrease it");
        maxSupply = newMaxSupply;
    }
}
