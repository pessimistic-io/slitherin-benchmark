// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./IERC721.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";

error NftMarketplace__PriceMustNotBeZero();
error NftMarketplace__NotApprovedForMarketplace();
error NftMarketplace__NotOwner();
error NftMarketplace__NoProceeds();
error NftMarketplace__AlreadyListed(address nftAddress, uint256 tokenId);
error NftMarketplace__NotListed(address nftAddress, uint256 tokenId);
error NftMarketplace__PriceNotMet(address nftAddress, uint256 tokenId, uint256 price);
error NftMarketplace__TransferFailed();

contract NftMarketplace is ReentrancyGuard, Ownable {
  struct Listing {
    uint256 price;
    address seller;
  }

  event ItemListed(
    address indexed seller,
    address indexed nftAddress,
    uint256 indexed tokenId,
    uint256 price
  );

  event ItemCanceled(address indexed seller, address indexed nftAddress, uint256 indexed tokenId);

  event ItemBought(
    address indexed buyer,
    address indexed nftAddress,
    uint256 indexed tokenId,
    uint256 price
  );

  mapping(address => mapping(uint256 => Listing)) private s_listings;
  mapping(address => uint256) private s_proceeds;
  modifier notListed(
    address nftAddress,
    uint256 tokenId,
    address owner
  ) {
    Listing memory listing = s_listings[nftAddress][tokenId];
    if (listing.price > 0) {
      revert NftMarketplace__AlreadyListed(nftAddress, tokenId);
    }
    _;
  }

  modifier isOwner(
    address nftAddress,
    uint256 tokenId,
    address ownercheck
  ) {
    IERC721 nft = IERC721(nftAddress);
    address owner = nft.ownerOf(tokenId);
    if (ownercheck != owner) {
      revert NftMarketplace__NotOwner();
    }
    _;
  }

  modifier isListed(address nftAddress, uint256 tokenId) {
    Listing memory listing = s_listings[nftAddress][tokenId];
    if (listing.price <= 0) {
      revert NftMarketplace__NotListed(nftAddress, tokenId);
    }
    _;
  }

  /*
   * @notice Method for listing NFT
   * @param nftAddress Address of NFT contract
   * @param tokenId Token ID of NFT
   * @param price sale price for each item
   */

  function listItem(
    address nftAddress,
    uint256 tokenId,
    uint256 price
  ) external notListed(nftAddress, tokenId, msg.sender) isOwner(nftAddress, tokenId, msg.sender) {
    if (price <= 0) {
      revert NftMarketplace__PriceMustNotBeZero();
    }
    IERC721 nft = IERC721(nftAddress);
    if (nft.getApproved(tokenId) != address(this)) {
      revert NftMarketplace__NotApprovedForMarketplace();
    }
    s_listings[nftAddress][tokenId] = Listing(price, msg.sender);
    emit ItemListed(msg.sender, nftAddress, tokenId, price);
  }

  function cancelListing(address nftAddress, uint256 tokenId)
    external
    isOwner(nftAddress, tokenId, msg.sender)
    isListed(nftAddress, tokenId)
  {
    delete (s_listings[nftAddress][tokenId]);
    emit ItemCanceled(msg.sender, nftAddress, tokenId);
  }

  function updateListing(
    address nftAddress,
    uint256 tokenId,
    uint256 newPrice
  ) external isListed(nftAddress, tokenId) nonReentrant isOwner(nftAddress, tokenId, msg.sender) {
    //We should check the value of `newPrice` and revert if it's below zero (like we also check in `listItem()`)
    if (newPrice <= 0) {
      revert NftMarketplace__PriceMustNotBeZero();
    }
    s_listings[nftAddress][tokenId].price = newPrice;
    emit ItemListed(msg.sender, nftAddress, tokenId, newPrice);
  }

  function buyItem(address nftAddress, uint256 tokenId)
    external
    payable
    isListed(nftAddress, tokenId)
    nonReentrant
  {
    Listing memory listedItem = s_listings[nftAddress][tokenId];
    if (msg.value < listedItem.price) {
      revert NftMarketplace__PriceNotMet(nftAddress, tokenId, listedItem.price);
    }
    s_proceeds[listedItem.seller] += listedItem.price;
    // Could just send the money...
    // https://fravoll.github.io/solidity-patterns/pull_over_push.html
    delete (s_listings[nftAddress][tokenId]);
    IERC721(nftAddress).safeTransferFrom(listedItem.seller, msg.sender, tokenId);
    emit ItemBought(msg.sender, nftAddress, tokenId, listedItem.price);
  }

  function withdrawProceeds() external {
    uint256 proceeds = s_proceeds[msg.sender];
    if (proceeds <= 0) {
      revert NftMarketplace__NoProceeds();
    }
    s_proceeds[msg.sender] = 0;
    (bool success, ) = payable(msg.sender).call{value: proceeds}("");
    require(success, "Transfer failed");
  }

  // function withdraw() public onlyOwner {
  //   uint256 amount = address(this).balance;
  //   (bool success, ) = payable(msg.sender).call{value: amount}("");
  //   if (!success) {
  //     revert NftMarketplace__TransferFailed();
  //   }
  // }

  function getListing(address nftAddress, uint256 tokenId) external view returns (Listing memory) {
    return s_listings[nftAddress][tokenId];
  }

  function getProceeds(address seller) external view returns (uint256) {
    return s_proceeds[seller];
  }
}

