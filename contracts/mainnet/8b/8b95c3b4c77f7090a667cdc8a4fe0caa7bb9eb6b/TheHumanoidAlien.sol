// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/**
             .-""""-.
  :: +. :.  /        \
H . '  -   /##      ##\
U         /:###    ###:\
M . +     |:####  ####:|
A      .   \    ||    /
N- .  _     \        /
O      "     \  0O  /
I. .  +-      '.__.'
D              |  |
 < >  .     ||||  ||||

**/

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./ERC721URIStorage.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./IERC2981.sol";
import "./DefaultOperatorFilterer.sol";

contract TheHumanoidAlien is ERC721, IERC2981, ERC721Enumerable, ERC721URIStorage, Ownable, DefaultOperatorFilterer {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;
    uint256 public MAX_SUPPLY = 9999;

    // ======== Royalties =========
    address public royaltyAddress;
    uint256 public royaltyPercent;

    constructor() ERC721("TheHumanoidAlien", "THA") {
        royaltyAddress = owner();
        royaltyPercent = 10;
    }

    function mintNFT(address recipient, string memory uri) public onlyOwner returns (uint256){
        require(totalSupply() < MAX_SUPPLY, "Can't mint more.");
        _tokenIdCounter.increment();
        uint256 newItemId = _tokenIdCounter.current();
        _mint(recipient, newItemId);
        _setTokenURI(newItemId, uri);

        return newItemId;
    }

    // Open Sea Enforcement
    function setApprovalForAll(address operator, bool approved) public override(ERC721, IERC721) onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId) public override(ERC721, IERC721) onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        override(ERC721, IERC721)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    // The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory){
        return super.tokenURI(tokenId);
    }

    // ======== Royalties =========
    function setRoyaltyReceiver(address royaltyReceiver) public onlyOwner {
        royaltyAddress = royaltyReceiver;
    }

    function setRoyaltyPercentage(uint256 royaltyPercentage) public onlyOwner {
        royaltyPercent = royaltyPercentage;
    }

    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view override returns (address receiver, uint256 royaltyAmount) {
        require(_exists(tokenId), "Non-existent token");
        return (royaltyAddress, salePrice * royaltyPercent / 100);
    }


    function supportsInterface(bytes4 interfaceId) public view override(ERC721, IERC165, ERC721Enumerable) returns (bool){
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    // ======== Withdraw =========
    function withdraw() public onlyOwner {
        require(address(this).balance > 0, "Balance is 0");
        payable(owner()).transfer(address(this).balance);
    }
}
