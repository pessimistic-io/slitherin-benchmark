// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./ERC2981.sol";
import "./Address.sol";
import "./Ownable.sol";
import "./Base64.sol";
import "./ReentrancyGuard.sol";
import "./IERC721Receiver.sol";
import "./console.sol";

contract PMarketplace is ReentrancyGuard, IERC721Receiver, Ownable {
    using Address for address payable;

    ERC721 public immutable nftContract;
    mapping(uint256 => uint256) public tokenPrices;

    event NFTListed(uint256 indexed tokenId, uint256 price);
    event NFTPurchased(uint256 indexed tokenId, address buyer, uint256 price);

    constructor(address _nftContract) {
        nftContract = ERC721(_nftContract);
    }

    function listNFT(uint256 tokenId, uint256 price) external {
        require(nftContract.ownerOf(tokenId) == msg.sender, "Not token owner");
        require(nftContract.isApprovedForAll(msg.sender, address(this)), "Not approved for transfer");

        tokenPrices[tokenId] = price;

        emit NFTListed(tokenId, price);
    }

    function buyNFT(uint256 tokenId, uint256 newPrice) external payable nonReentrant {
        uint256 price = tokenPrices[tokenId];
        require(msg.value >= price, "Not enough eth sent");
        require(newPrice > price, "New price must be higher than current price");

        tokenPrices[tokenId] = newPrice;
        
        address seller = nftContract.ownerOf(tokenId);
        (, uint256 fee) = ERC2981(address(nftContract)).royaltyInfo(tokenId, price);

        // Transfer token from seller to buyer - have to use self as intermediary b/c of setApprovalForAll, cannot do direct safeTransferFrom(seller, msg.sender, tokenId);
        nftContract.safeTransferFrom(seller, address(this), tokenId);
        nftContract.safeTransferFrom(address(this), msg.sender, tokenId);

        // Transfer payment to seller
        payable(seller).sendValue(price - fee);

        // Keep fee here, we ignore royaltyInfo's receiver to save gas and keep it here for now
        // if (receiver != address(this)) {
        //     payable(receiver).sendValue(fee);
        // }

        emit NFTPurchased(tokenId, msg.sender, price);
    }

    // Needed b/c in buyNFT, we receive temporarily
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function withdraw() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
}

