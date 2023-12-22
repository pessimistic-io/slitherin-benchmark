// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ERC721HolderUpgradeable.sol";
import "./EnumerableSet.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IERC721.sol";

interface IChronosMarketPlace {
    struct SellInfo {
        address seller;
        address buyer;
        address nft;
        address paymentToken;
        uint256 tokenId;
        uint256 startTime;
        uint256 endTime;
        uint256 price;
    }

    struct AuctionInfo {
        address seller;
        address nft;
        address paymentToken;
        address highestBidder;
        uint256 tokenId;
        uint256 startTime;
        uint256 endTime;
        uint256 minimumPrice;
        uint256 highestBidPrice;
    }

    struct OfferInfo {
        address offeror;
        address paymentToken;
        address nft;
        uint256 tokenId;
        uint256 offerPrice;
    }

    /// @notice Set allowed payment token.
    /// @dev    Users can't trade NFT with token that not allowed.
    ///         Only owner can call this function.
    /// @param  tokens The token addresses.
    /// @param  isAdd Add/Remove = true/false
    function setAllowedToken(address[] memory tokens, bool isAdd) external;

    /// @notice Set marketplace platform fee.
    /// @dev Only owner can call this function.
    /// @dev Platform fees correspond to each type of NFT.
    ///      fee[0] --- tokenType = 1
    ///      fee[1] --- tokenType = 2
    ///      fee[2] --- tokenType = 3
    function setPlatformFee(uint16[] memory platformFee) external;

    /// @notice Set marketplace Treasury address.
    /// @dev Only owner can call this function.
    function setTreasury(address payable treasury) external;

    /// @notice Set NftList available in the marketplace.
    /// @dev    Only owner can call this function.
    function setNftList(address[] memory nftList) external;

    /// @notice return the token type of the nfts.
    /// @dev    ChronosNftList[0] - tokenType = 1
    ///         ChronosNftList[1] - tokenType = 2
    ///         maNfts            - tokenType = 3
    function getChronosNftType(address nft) external returns (uint16);

    /// @notice Check if the nft is included in the available nfts.
    function isChronosNft(address nft) external returns (bool);

    /// @notice Pause marketplace
    /// @dev    Only owner can call this function.
    function pause() external;

    /// @notice Unpause marketplace
    /// @dev    Only owner can call this function.
    function unpause() external;

    /// @notice List Nft for sale in the marketplace.
    /// @dev    Only owner of Nft can call this function.
    ///         Nft owners should send their nfts to marketplace.
    /// @param  nft:            the address of nft to list
    /// @param  tokenId:        token Id of the nft
    /// @param  paymentToken:   the address that the buyer should pay with.
    /// @param  saleDuration:   the duration that the nft will be listed.
    /// @param  price:          price to sell
    function listNftForFixed(
        address nft,
        uint256 tokenId,
        address paymentToken,
        uint256 price,
        uint256 saleDuration
    ) external;

    /// @notice Get available saleIds of listNft for fixed
    function getAvailableSaleIds() external view returns (uint256[] memory);

    /// @notice Get available saleIds of User's Listed Nfts for fixed price.
    function getNftListForFixedOfUser(
        address user
    ) external returns (uint256[] memory);

    /// @notice Cancel and retrieve the listed Nft for sale in the marketplace.
    /// @dev    Only sale creator can call this function.
    function cancelListNftForFixed(uint256 saleId) external;

    /// @notice Change the SaleInfo of listed Nft of user.
    /// @dev    only sale creator can call this function.
    function changeSaleInfo(
        uint256 saleId,
        uint256 saleDuration,
        address paymentToken,
        uint256 price
    ) external;

    /// @notice Buy the listed Nft for fixed
    /// @dev    Buyer can't same as seller.
    function buyNow(uint256 saleId, uint256 price) external;

    /// @notice Buy the listed Nft for fixed with ETH
    /// @dev    Buyer can't same as seller.
    /// @dev    Buyer needs to send ETH equal to the fixed price to the contract.
    function buyNowWithETH(uint256 saleId) external payable;

    /// @notice List the Nft for auction.
    /// @dev    Only the owner of the nft can call this function.
    ///         Nft should be the available nft in the platform.
    ///         Nft owners should send their nfts to marketplace.
    /// @param  nft:          the address of the nft for auction.
    /// @param  tokenId:      id of the nft
    /// @param  paymentToken: the address that the winner should pay with.
    /// @param  saleDuration: the duration for auction
    /// @param  minimumPrice: the start price for auction.
    function listNftForAuction(
        address nft,
        uint256 tokenId,
        address paymentToken,
        uint256 minimumPrice,
        uint256 saleDuration
    ) external;

    /// @notice Get available ids of auction.
    function getAvailableAuctionIds() external view returns (uint256[] memory);

    /// @notice Cancel and retrieve the listed Nft for auction in the marketplace.
    /// @dev    Only the owner of the contract can call this function.
    function cancelListNftForAuction(uint256 auctionId) external;

    /// @notice Get available nftlist of user for auction.
    function getNftListForAuctionOfUser(
        address user
    ) external returns (uint256[] memory);

    /// @notice Finish auction.
    /// @dev Caller should be the auction maker and highest bidder.
    ///      Highest bidder receives the NFT and auction maker gets token.
    ///      auction maker can finish anytime in case he has at least one bidder.
    ///      highest bidder can finish after the auction ends.
    function finishAuction(uint256 auctionId) external;

    /// @notice Bid to auction with certain auction Id.
    /// @dev    Another contract can't bid in the auction.
    /// @dev    Users can get auctionIds from `getAvailableAuctionIds`
    /// @dev    Bidder should bid with price higher than last highestBidder's bid price.
    /// @param  auctionId The id of auction.
    /// @param  bidPrice The price of token to bid.
    function placeBid(uint256 auctionId, uint256 bidPrice) external;

    /// @notice Bid to auction with certain auction Id.
    /// @dev    Another contract can't bid in the auction.
    /// @dev    Users can get auctionIds from `getAvailableAuctionIds`
    /// @dev    Bidder should bid with price higher than last highestBidder's bid price.
    /// @dev    msg.value- The price of token to bid.
    /// @param  auctionId- The id of auction.
    function placeBidWithETH(uint256 auctionId) external payable;

    /// @notice User can withDraw their oldBidPrice that was failed to transfer.
    function refundBidprice() external;

    /// @notice Anyone can place offer to certain nfts in this platform.
    function makeOffer(
        address nft,
        uint256 tokenId,
        address paymentToken,
        uint256 offerPrice
    ) external;

    /// @notice Anyone can place offer to certain nfts in this platform.
    /// @dev    User should offer with ETH equal to the offerPrice.
    function makeOfferWithETH(
        address nft,
        uint256 tokenId,
        address paymentToken,
        uint256 offerPrice
    ) external payable;

    /// @notice Get available ids of offer.
    function getAvailableOfferIds() external view returns (uint256[] memory);

    /// @notice Nft owner accept offer with certain offer Id.
    /// @dev    Nft owner can get available offer ids from `getAvailableOffers` function.
    function acceptOffer(uint256 offerId) external;

    /// @notice Cancel the offer for the nft.
    /// @dev    Only offer maker can call this function.
    function cancelOffer(uint256 offerId) external;

    event AllowedTokenSet(address[] tokens, bool _isAdd);

    event PlatformFeeSet(uint16[] platformFee);

    event TreasurySet(address treasury);

    event NftListSet(address[] nftList);

    event Pause();

    event Unpause();

    event ListNftForFixed(
        uint256 indexed saleId,
        address seller,
        address indexed nft,
        uint256 indexed tokenId,
        address paymentToken,
        uint256 fixedPrice,
        uint256 startTime,
        uint256 endTime
    );

    event CancelListNftForFixed(uint256 indexed saleId);

    event SaleInfoChanged(
        uint256 indexed saleId,
        uint256 startTime,
        uint256 endTime,
        address paymentToken,
        uint256 price
    );

    event Bought(uint256 indexed saleId, address indexed buyer);

    event ListNftForAuction(
        uint256 indexed auctionId,
        address seller,
        address indexed nft,
        uint256 indexed tokenId,
        address paymentToken,
        uint256 minimumPrice,
        uint256 saleDuration
    );

    event CancelListNftForAuction(uint256 indexed auctionId);

    event FinishAuction(uint256 indexed auctionId);

    event PlaceBid(
        address indexed bidder,
        uint256 indexed auctionId,
        uint256 bidPrice
    );

    event TransferFailForETH(address indexed user);

    event RefundBidPrice(address indexed user, uint256 price);

    event MakeOffer(
        uint256 indexed offerId,
        address offeror,
        address indexed nft,
        uint256 indexed tokenId,
        address paymentToken,
        uint256 offerPrice
    );

    event AcceptOffer(uint256 indexed offerId, address indexed user);
    event CancelOffer(uint256 indexed offerId);
}

