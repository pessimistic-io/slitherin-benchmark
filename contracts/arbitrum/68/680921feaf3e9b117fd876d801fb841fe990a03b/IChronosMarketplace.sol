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
        address owner;
        address offeror;
        address paymentToken;
        address nft;
        uint256 tokenId;
        uint256 offerPrice;
    }

    /// @notice Set allowed payment token.
    /// @dev Users can't trade NFT with token that not allowed.
    ///      Only owner can call this function.
    /// @param _tokens The token addresses.
    /// @param _isAdd Add/Remove = true/false
    function setAllowedToken(address[] memory _tokens, bool _isAdd) external;

    /// @notice Set marketplace platform fee.
    /// @dev Only owner can call this function.
    function setPlatformFee(uint16 _platformFee) external;

    /// @notice Set marketplace Treasury address.
    /// @dev Only owner can call this function.
    function setTreasury(address _treasury) external;

    /// @notice Set NftList available in the marketplace.
    /// @dev Only owner can call this function.
    function setNftList(address[] memory nftList) external;

    /// @notice return the token type of the nfts.
    function getChronosNftType(address nft) external returns (uint16);

    /// @notice Check if the nft is included in the available nfts.
    function isChronosNft(address nft) external returns (bool);

    /// @notice Pause marketplace
    /// @dev Only owner can call this function.
    function pause() external;

    /// @notice Unpause marketplace
    /// @dev Only owner can call this function.
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
        uint256 saleDuration,
        uint256 price
    ) external;

    /// @notice Get available saleIds of listNft for fixed
    function getAvailableSaleIds() external view returns (uint256[] memory);

    /// @notice Get available saleIds of User's Listed Nfts for fixed price.
    function getNftListForFixedOfUser(address _user) external returns (uint256[] memory);

    /// @notice Cancel and retrieve the listed Nft for sale in the marketplace.
    /// @dev Only sale creator can call this function.
    function cancelListNftForFixed(uint256 _saleId) external;

    /// @notice Change the SaleInfo of listed Nft of user.
    /// @dev only sale creator can call this function.
    function changeSaleInfo(
        uint256 _saleId,
        uint256 _saleDuration,
        uint256 _price
    ) external;

    /// @notice Buy the listed Nft for fixed
    /// @dev Buyer can't same as seller.
    function buyNow(uint256 _saleId) external;

    /// @notice List the Nft for auction.
    /// @dev Only the owner of the nft can call this function.
    ///      Nft should be the available nft in the platform.
    ///      Nft owners should send their nfts to marketplace.
    /// @param  nft:          the address of the nft for auction.
    /// @param  tokenId:      id of the nft
    /// @param  paymentToken: the address that the winner should pay with.
    /// @param  saleDuration: the duration for auction
    /// @param  minimumPrice: the start price for auction.
    function listNftForAuction(
        address nft,
        uint256 tokenId,
        address paymentToken,
        uint256 saleDuration,
        uint256 minimumPrice
    ) external;

    /// @notice Get available ids of auction.
    function getAvailableAuctionIds() external view returns (uint256[] memory);

    /// @notice Cancel and retrieve the listed Nft for auction in the marketplace.
    /// @dev Only auction creator can call this function.
    function cancelListNftForAuction(uint256 _auctionId) external;

    /// @notice Get available nftlist of user for auction.
    /// @dev Only auction creator can call this function.
    function getNftListForAuctionOfUser(address _user) external returns (uint256[] memory);

    /// @notice Finish auction.
    /// @dev Caller should be the auction maker.
    ///      Winner receives the collection and auction maker gets token.
    function finishAuction(uint256 _auctionId) external;

    /// @notice Bid to auction with certain auction Id.
    /// @dev Users can get auctionIds from `getAvailableAuctionIds`
    /// @dev Bidder should bid with price that higher than last highestBidder's bid price.
    /// @param _auctionId The id of auction.
    /// @param _bidPrice The price of token to bid.
    function placeBid(uint256 _auctionId, uint256 _bidPrice) external;

    /// @notice Anyone can place offer to certain nfts in this platform.
    function makeOffer(
        address owner,
        address nft,
        uint256 tokenId,
        address paymentToken,
        uint256 offerPrice
    ) external;

    /// @notice the owner of nft can get the available offers to his nft.
    function getAvailableOffers(
        address _owner,
        address _nft
    ) external returns (OfferInfo[] memory, uint256[] memory);

    /// @notice Nft owner accept offer with certain offer Id.
    /// @dev Nft owner can get available offer ids from `geetAvailableOffers` function.
    function acceptOffer(uint256 _offerId) external;

    /// @notice Cancel the offer for the nft.
    /// @dev Only offer maker can call this function.
    function cancelOffer(uint256 _offerId) external;

    event AllowedTokenSet(address[] _tokens, bool _isAdd);

    event PlatformFeeSet(uint16 platformFee);

    event TreasurySet(address treasury);

    event NftListSet(address[] nftList);

    event Pause();

    event Unpause();

    event ListNftForFixed(
        address nft,
        address paymentToken,
        uint256 saleId,
        uint256 tokenId,
        uint256 saleDuration,
        uint256 fixedPrice
    );

    event CancelListNftForFixed(uint256 _saleId);

    event SaleInfoChanged(uint256 _saleId, uint256 _price);

    event ListNftForAuction(
        address nft,
        address paymentToken,
        uint256 itemId,
        uint256 tokenId,
        uint256 saleDuration,
        uint256 minimumPrice
    );

    event CancelListNftForAuction(uint256 _auctionId);

    event FinishAuction(uint256 _auctionId);

    event Bought(
        uint256 itemId,
        address nft,
        uint256 tokenId,
        address seller,
        address buyer,
        uint256 price
    );

    event PlaceBid(
        address bidder,
        uint256 tokenId,
        uint256 bidPrice
    );

    event MakeOffer(
        uint256 offerId,
        address offeror,
        address paymentToken,
        address nft,
        uint256 tokenId,
        uint256 offerPrice
    );

    event AcceptOffer(uint256 _offerId);
    event CancelOffer(uint256 _offerId);
}
