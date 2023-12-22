// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./ERC721.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";

error PriceNotMet(address nftAddress, uint256 tokenId, uint256 price);
error ItemNotForSale(address nftAddress, uint256 tokenId);
error NotListed(address nftAddress, uint256 tokenId);
error AlreadyListed(address nftAddress, uint256 tokenId);
error NoProceeds();
error NotOwner();
error NotSeller();
error NotApprovedForMarketplace();
error PriceMustBeAboveZero();
error AvailableAtInThePast();
error ItemNotAvailableYet(address nftAddress, uint256 tokenId);

contract NftMarketplace is ReentrancyGuard, Ownable, ERC721TokenReceiver {
    using SafeERC20 for IERC20;
    struct Listing {
        uint256 price;
        address seller;
        uint256 tokenId;
        uint256 availableAt;
    }

    event ItemListed(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price,
        uint256 availableAt
    );

    event ItemCanceled(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId
    );

    event ItemBought(
        address indexed buyer,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price
    );

    mapping(address => mapping(uint256 => Listing)) private s_listings;

    modifier notListed(
        address nftAddress,
        uint256 tokenId,
        address owner
    ) {
        Listing memory listing = s_listings[nftAddress][tokenId];
        if (listing.price > 0) {
            revert AlreadyListed(nftAddress, tokenId);
        }
        _;
    }

    modifier isListed(address nftAddress, uint256 tokenId) {
        Listing memory listing = s_listings[nftAddress][tokenId];
        if (listing.price <= 0) {
            revert NotListed(nftAddress, tokenId);
        }
        _;
    }

    modifier isTokenOwner(
        address nftAddress,
        uint256 tokenId,
        address spender
    ) {
        ERC721 nft = ERC721(nftAddress);
        address tokenOwner = nft.ownerOf(tokenId);
        if (spender != tokenOwner) {
            revert NotOwner();
        }
        _;
    }

    modifier isTokenSeller(
        address nftAddress,
        uint256 tokenId,
        address seller
    ) {
        ERC721 nft = ERC721(nftAddress);
        address tokenSeller = s_listings[nftAddress][tokenId].seller;
        if (seller != tokenSeller) {
            revert NotSeller();
        }
        _;
    }

    IERC20 public immutable USDC;
    address royaltyAddress;

    constructor(
        IERC20 USDC_,
        address royaltyReceiverAddress,
        address multisigAddress
    ) {
        USDC = USDC_;
        royaltyAddress = royaltyReceiverAddress;
        Ownable.transferOwnership(multisigAddress);
    }

    /////////////////////
    // Main Functions //
    /////////////////////
    /*
     * @notice Method for listing NFT
     * @param nftAddress Address of NFT contract
     * @param tokenId Token ID of NFT
     * @param price sale price for each item
     */
    function listItem(
        address nftAddress,
        uint256 tokenId,
        uint256 price,
        uint256 availableAt
    ) external notListed(nftAddress, tokenId, msg.sender) onlyOwner {
        ERC721 nft = ERC721(nftAddress);
        address tokenOwner = nft.ownerOf(tokenId);
        if (availableAt < block.timestamp) revert AvailableAtInThePast();
        if (msg.sender != tokenOwner) revert NotOwner();
        if (price <= 0) revert PriceMustBeAboveZero();

        nft.safeTransferFrom(msg.sender, address(this), tokenId);
        s_listings[nftAddress][tokenId] = Listing(
            price,
            msg.sender,
            tokenId,
            availableAt
        );

        emit ItemListed(msg.sender, nftAddress, tokenId, price, availableAt);
    }

    /*
     * @notice Method for cancelling listing
     * @param nftAddress Address of NFT contract
     * @param tokenId Token ID of NFT
     */
    function cancelListing(address nftAddress, uint256 tokenId)
        external
        isTokenSeller(nftAddress, tokenId, msg.sender)
        isListed(nftAddress, tokenId)
        onlyOwner
    {
        ERC721(nftAddress).safeTransferFrom(address(this), msg.sender, tokenId);
        delete (s_listings[nftAddress][tokenId]);
        emit ItemCanceled(msg.sender, nftAddress, tokenId);
    }

    function buyItem(
        address nftAddress,
        uint256 tokenId,
        uint256 priceToPay
    ) external isListed(nftAddress, tokenId) nonReentrant {
        Listing memory listedItem = s_listings[nftAddress][tokenId];
        if (priceToPay < listedItem.price) {
            revert PriceNotMet(nftAddress, tokenId, listedItem.price);
        }

        if (listedItem.availableAt > block.timestamp) {
            revert ItemNotAvailableYet(nftAddress, tokenId);
        }

        // 99.75% to seller
        USDC.safeTransferFrom(
            msg.sender,
            listedItem.seller,
            (priceToPay * 9975) / 10000
        );
        // 0.25% to royalty address
        USDC.safeTransferFrom(
            msg.sender,
            royaltyAddress,
            (priceToPay * 25) / 10000
        );

        delete (s_listings[nftAddress][tokenId]);
        ERC721(nftAddress).safeTransferFrom(address(this), msg.sender, tokenId);
        emit ItemBought(msg.sender, nftAddress, tokenId, listedItem.price);
    }

    /*
     * @notice Method for updating listing
     * @param nftAddress Address of NFT contract
     * @param tokenId Token ID of NFT
     * @param newPrice Price in Wei of the item
     */
    function updateListing(
        address nftAddress,
        uint256 tokenId,
        uint256 newPrice,
        uint256 newAvailableAt
    )
        external
        isListed(nftAddress, tokenId)
        nonReentrant
        isTokenSeller(nftAddress, tokenId, msg.sender)
        onlyOwner
    {
        s_listings[nftAddress][tokenId].price = newPrice;
        s_listings[nftAddress][tokenId].availableAt = newAvailableAt;
        emit ItemListed(
            msg.sender,
            nftAddress,
            tokenId,
            newPrice,
            newAvailableAt
        );
    }

    /////////////////////
    // Getter Functions //
    /////////////////////

    function getListing(address nftAddress, uint256 tokenId)
        external
        view
        returns (Listing memory)
    {
        return s_listings[nftAddress][tokenId];
    }
}

