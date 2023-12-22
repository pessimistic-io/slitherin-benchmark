// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IChronosMarketplace.sol";
import "./IVoter.sol";
import "./Errors.sol";

contract ChronosMarketplace is
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    ERC721HolderUpgradeable,
    IChronosMarketPlace
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    address[] public chronosNftList;
    mapping(address => uint16) public tokenType;
    mapping(uint256 => SellInfo) public sellInfos;
    mapping(uint256 => AuctionInfo) public auctionInfos;
    mapping(uint256 => OfferInfo) public offerInfos;
    uint256 public saleId;
    uint256 public auctionId;
    uint256 public offerId;

    mapping(address => EnumerableSet.UintSet) private userSaleIds;
    mapping(address => EnumerableSet.UintSet) private userAuctionIds;
    mapping(address => EnumerableSet.UintSet) private userOfferIds;

    EnumerableSet.UintSet private availableSaleIds;
    EnumerableSet.UintSet private availableAuctionIds;
    EnumerableSet.UintSet private availableOfferIds;

    uint16[] public platformFee;
    uint16 public constant FIXED_POINT = 1000;
    address payable treasury;
    mapping(address => bool) public allowedTokens;
    IVoter vt;

    
    mapping(address => uint256) private refundToUser;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _voterAddress) public initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __ERC721Holder_init();
        saleId = 1;
        auctionId = 1;
        offerId = 1;
        vt = IVoter(_voterAddress);
    }

    /// @inheritdoc IChronosMarketPlace
    function setAllowedToken(
        address[] memory _tokens,
        bool _isAdd
    ) external override onlyOwner {
        uint256 length = _tokens.length;
        require(length > 0, Errors.INVALID_LENGTH);
        for (uint256 i = 0; i < length; i++) {
            allowedTokens[_tokens[i]] = _isAdd;
        }

        emit AllowedTokenSet(_tokens, _isAdd);
    }

    /// @inheritdoc IChronosMarketPlace
    function setPlatformFee(
        uint16[] memory _platformFee
    ) external override onlyOwner {
        require(
            _platformFee.length > 0 && _platformFee.length <= 3,
            Errors.INVALID_FEE
        );

        delete platformFee;
        for (uint16 i = 0; i < _platformFee.length; i++) {
            require(_platformFee[i] < FIXED_POINT, Errors.INVALID_FEE);
            platformFee.push(_platformFee[i]);
        }

        emit PlatformFeeSet(_platformFee);
    }

    /// @inheritdoc IChronosMarketPlace
    function setTreasury(
        address payable _treasury
    ) external override onlyOwner {
        require(_treasury != address(0), Errors.INVALID_TREASURY_ADDRESS);
        treasury = _treasury;

        emit TreasurySet(_treasury);
    }

    /// @inheritdoc IChronosMarketPlace
    function setNftList(address[] memory _nftList) external override onlyOwner {
        require(_nftList.length > 0 && _nftList.length <= 2, Errors.EMPTY_NFTS);
        delete chronosNftList;

        for (uint16 i = 0; i < _nftList.length; i++) {
            chronosNftList.push(_nftList[i]);
            tokenType[_nftList[i]] = i + 1;
        }

        emit NftListSet(_nftList);
    }

    /// @inheritdoc IChronosMarketPlace
    function getChronosNftType(address _nft) public override returns (uint16) {
        if (tokenType[_nft] > 0) return tokenType[_nft];
        if (tokenType[_nft] == 0 && vt.isGauge(_nft)) {
            tokenType[_nft] = 3;
            return tokenType[_nft];
        }
        return 5;
    }

    /// @inheritdoc IChronosMarketPlace
    function isChronosNft(address _nft) public override returns (bool) {
        return getChronosNftType(_nft) != 5;
    }

    /// @inheritdoc IChronosMarketPlace
    function pause() external override whenNotPaused onlyOwner {
        _pause();
        emit Pause();
    }

    /// @inheritdoc IChronosMarketPlace
    function unpause() external override whenPaused onlyOwner {
        _unpause();
        emit Unpause();
    }

    /// Fixed Sale

    /// @inheritdoc IChronosMarketPlace
    function listNftForFixed(
        address _nft,
        uint256 _tokenId,
        address _paymentToken,
        uint256 _price,
        uint256 _saleDuration
    ) external override nonReentrant whenNotPaused {
        address seller = msg.sender;
        require(isChronosNft(_nft), Errors.NOT_CHRONOS_NFT);

        require(
            allowedTokens[_paymentToken] || _paymentToken == address(0),
            Errors.INVALID_TOKEN
        );

        require(_price > 0, Errors.INVALID_PRICE);

        require(
            IERC721(_nft).ownerOf(_tokenId) == seller,
            Errors.SELLER_NOT_OWNER_OF_NFT
        );

        require(_saleDuration > 0, Errors.INVALID_SALE_DURATION);

        _setSaleId(saleId, seller, true);

        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + _saleDuration;

        sellInfos[saleId++] = SellInfo(
            seller,
            address(0),
            _nft,
            _paymentToken,
            _tokenId,
            startTime,
            endTime,
            _price
        );

        IERC721(_nft).safeTransferFrom(seller, address(this), _tokenId);

        emit ListNftForFixed(
            saleId - 1,
            seller,
            _nft,
            _tokenId,
            _paymentToken,
            _price,
            startTime,
            endTime
        );
    }

    /// @inheritdoc IChronosMarketPlace
    function getAvailableSaleIds()
        external
        view
        override
        returns (uint256[] memory)
    {
        return availableSaleIds.values();
    }

    /// @inheritdoc IChronosMarketPlace
    function getNftListForFixedOfUser(
        address _user
    ) external view override returns (uint256[] memory) {
        return userSaleIds[_user].values();
    }

    /// @inheritdoc IChronosMarketPlace
    function cancelListNftForFixed(
        uint256 _saleId
    ) external override nonReentrant whenNotPaused {
        require(availableSaleIds.contains(_saleId), Errors.NOT_EXISTED_SAILID);

        SellInfo storage sellInfo = sellInfos[_saleId];
        require(msg.sender == sellInfo.seller, Errors.NO_PERMISSION);

        _setSaleId(_saleId, sellInfo.seller, false);

        IERC721(sellInfo.nft).safeTransferFrom(
            address(this),
            sellInfo.seller,
            sellInfo.tokenId
        );

        emit CancelListNftForFixed(_saleId);
    }

    /// @inheritdoc IChronosMarketPlace
    function changeSaleInfo(
        uint256 _saleId,
        uint256 _saleDuration,
        address _paymentToken,
        uint256 _price
    ) external override nonReentrant whenNotPaused {
        require(availableSaleIds.contains(_saleId), Errors.NOT_EXISTED_SAILID);

        SellInfo storage sellInfo = sellInfos[_saleId];
        require(msg.sender == sellInfo.seller, Errors.NO_PERMISSION);

        require(
            allowedTokens[_paymentToken] || _paymentToken == address(0),
            Errors.INVALID_TOKEN
        );

        require(_price > 0, Errors.INVALID_PRICE);

        require(_saleDuration > 0, Errors.INVALID_SALE_DURATION);

        sellInfo.startTime = block.timestamp;
        sellInfo.endTime = sellInfo.startTime + _saleDuration;
        sellInfo.paymentToken = _paymentToken;
        sellInfo.price = _price;

        emit SaleInfoChanged(
            _saleId,
            sellInfo.startTime,
            sellInfo.endTime,
            sellInfo.paymentToken,
            sellInfo.price
        );
    }

    /// @inheritdoc IChronosMarketPlace
    function buyNow(
        uint256 _saleId,
        uint256 _price
    ) external override nonReentrant whenNotPaused {
        address buyer = msg.sender;
        uint256 currentTime = block.timestamp;

        require(availableSaleIds.contains(_saleId), Errors.NOT_EXISTED_SAILID);

        SellInfo storage saleInfo = sellInfos[_saleId];
        require(buyer != saleInfo.seller, Errors.INVALID_BUYER);

        require(saleInfo.price == _price, Errors.INVALID_PRICE);

        require(
            saleInfo.startTime <= currentTime && currentTime < saleInfo.endTime,
            Errors.NOT_SALE_PERIOD
        );

        require(saleInfo.buyer == address(0), Errors.ALREADY_SOLD);

        _setSaleId(_saleId, saleInfo.seller, false);
        saleInfo.buyer = buyer;

        uint16 NFTType = tokenType[saleInfo.nft];
        uint256 fee = (saleInfo.price * platformFee[NFTType - 1]) / FIXED_POINT;

        IERC20(saleInfo.paymentToken).safeTransferFrom(
            buyer,
            saleInfo.seller,
            saleInfo.price - fee
        );
        IERC20(saleInfo.paymentToken).safeTransferFrom(buyer, treasury, fee);

        IERC721(saleInfo.nft).safeTransferFrom(
            address(this),
            buyer,
            saleInfo.tokenId
        );

        emit Bought(_saleId, saleInfo.buyer);
    }

    /// @inheritdoc IChronosMarketPlace
    function buyNowWithETH(
        uint256 _saleId
    ) external payable override nonReentrant whenNotPaused {
        require(availableSaleIds.contains(_saleId), Errors.NOT_EXISTED_SAILID);

        address buyer = msg.sender;
        uint256 currentTime = block.timestamp;
        SellInfo storage saleInfo = sellInfos[_saleId];

        require(msg.value >= saleInfo.price, Errors.LOW_ETH_BALANCE);

        require(buyer != saleInfo.seller, Errors.INVALID_BUYER);

        require(
            saleInfo.startTime <= currentTime && currentTime < saleInfo.endTime,
            Errors.NOT_SALE_PERIOD
        );

        require(saleInfo.buyer == address(0), Errors.ALREADY_SOLD);

        require(saleInfo.paymentToken == address(0), Errors.INVALID_TOKEN);

        saleInfo.buyer = buyer;

        _setSaleId(_saleId, saleInfo.seller, false);

        uint16 NFTType = tokenType[saleInfo.nft];
        uint256 fee = (saleInfo.price * platformFee[NFTType - 1]) / FIXED_POINT;

        payable(saleInfo.seller).transfer(saleInfo.price - fee);
        payable(treasury).transfer(fee);

        IERC721(saleInfo.nft).safeTransferFrom(
            address(this),
            buyer,
            saleInfo.tokenId
        );

        emit Bought(_saleId, saleInfo.buyer);
    }

    /// Bid

    /// @inheritdoc IChronosMarketPlace
    function listNftForAuction(
        address _nft,
        uint256 _tokenId,
        address _paymentToken,
        uint256 _minimumPrice,
        uint256 _saleDuration
    ) external override nonReentrant whenNotPaused {
        address seller = msg.sender;
        require(isChronosNft(_nft), Errors.NOT_CHRONOS_NFT);

        require(
            allowedTokens[_paymentToken] || _paymentToken == address(0),
            Errors.INVALID_TOKEN
        );

        require(_minimumPrice > 0, Errors.INVALID_PRICE);

        require(
            IERC721(_nft).ownerOf(_tokenId) == seller,
            Errors.SELLER_NOT_OWNER_OF_NFT
        );

        require(_saleDuration > 0, Errors.INVALID_SALE_DURATION);

        _setAuctionId(auctionId, seller, true);

        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + _saleDuration;

        auctionInfos[auctionId++] = AuctionInfo(
            seller,
            _nft,
            _paymentToken,
            address(0),
            _tokenId,
            startTime,
            endTime,
            _minimumPrice,
            0
        );

        IERC721(_nft).safeTransferFrom(seller, address(this), _tokenId);

        emit ListNftForAuction(
            auctionId - 1,
            seller,
            _nft,
            _tokenId,
            _paymentToken,
            _minimumPrice,
            _saleDuration
        );
    }

    /// @inheritdoc IChronosMarketPlace
    function getAvailableAuctionIds()
        external
        view
        override
        returns (uint256[] memory)
    {
        return availableAuctionIds.values();
    }

    /// @inheritdoc IChronosMarketPlace
    function getNftListForAuctionOfUser(
        address _user
    ) external view override returns (uint256[] memory) {
        return userAuctionIds[_user].values();
    }

    /// @inheritdoc IChronosMarketPlace
    function cancelListNftForAuction(
        uint256 _auctionId
    ) external override nonReentrant whenNotPaused onlyOwner {
        require(
            availableAuctionIds.contains(_auctionId),
            Errors.NOT_EXISTED_AUCTIONID
        );

        AuctionInfo storage auctionInfo = auctionInfos[_auctionId];

        _setAuctionId(_auctionId, auctionInfo.seller, false);

        if (auctionInfo.highestBidder != address(0)) {
            if (auctionInfo.paymentToken == address(0)) {
                (bool sent, ) = payable(auctionInfo.highestBidder).call{
                    value: auctionInfo.highestBidPrice
                }("");
                if (!sent) {
                    refundToUser[auctionInfo.highestBidder] += auctionInfo.highestBidPrice;
                    emit TransferFailForETH(auctionInfo.highestBidder);
                }
            } else {
                IERC20(auctionInfo.paymentToken).safeTransfer(
                    auctionInfo.highestBidder,
                    auctionInfo.highestBidPrice
                );
            }
        }

        IERC721(auctionInfo.nft).safeTransferFrom(
            address(this),
            auctionInfo.seller,
            auctionInfo.tokenId
        );

        emit CancelListNftForAuction(_auctionId);
    }

    /// @inheritdoc IChronosMarketPlace
    function finishAuction(
        uint256 _auctionId
    ) external override nonReentrant whenNotPaused {
        address sender = msg.sender;
        require(
            availableAuctionIds.contains(_auctionId),
            Errors.NOT_EXISTED_AUCTIONID
        );

        AuctionInfo storage auctionInfo = auctionInfos[_auctionId];

        require(
            auctionInfo.seller == sender || auctionInfo.highestBidder == sender,
            Errors.NO_PERMISSION
        );

        if (sender == auctionInfo.highestBidder) {
            require(
                block.timestamp >= auctionInfo.endTime,
                Errors.BEFORE_AUCTION_MATURITY
            );
        }

        if (sender == auctionInfo.seller) {
            require(
                block.timestamp > auctionInfo.startTime,
                Errors.BEFORE_AUCTION_MATURITY
            );

            if (block.timestamp < auctionInfo.endTime) {
                require(
                    auctionInfo.highestBidder != address(0),
                    Errors.BEFORE_AUCTION_MATURITY
                );
            }
        }

        _setAuctionId(_auctionId, auctionInfo.seller, false);

        if (auctionInfo.highestBidder != address(0)) {
            uint256 price = auctionInfo.highestBidPrice;

            uint16 NFTType = getChronosNftType(auctionInfo.nft);
            uint256 fee = (price * platformFee[NFTType - 1]) / FIXED_POINT;

            if (auctionInfo.paymentToken == address(0)) {
                (bool sent, ) = payable(auctionInfo.seller).call{
                    value: (price - fee)
                }("");
                if (!sent) {
                    refundToUser[auctionInfo.seller] += (price - fee);
                    emit TransferFailForETH(auctionInfo.seller);
                }

                payable(treasury).transfer(fee);
            } else {
                IERC20(auctionInfo.paymentToken).safeTransfer(
                    auctionInfo.seller,
                    price - fee
                );

                IERC20(auctionInfo.paymentToken).safeTransfer(treasury, fee);
            }

            IERC721(auctionInfo.nft).safeTransferFrom(
                address(this),
                auctionInfo.highestBidder,
                auctionInfo.tokenId
            );
        } else {
            IERC721(auctionInfo.nft).safeTransferFrom(
                address(this),
                auctionInfo.seller,
                auctionInfo.tokenId
            );
        }

        emit FinishAuction(_auctionId);
    }

    /// @inheritdoc IChronosMarketPlace
    function placeBid(
        uint256 _auctionId,
        uint256 _bidPrice
    ) external override nonReentrant whenNotPaused {
        address bidder = msg.sender;
        uint256 currentTime = block.timestamp;

        require(bidder == tx.origin, Errors.NOT_ALLOWED_CALL);

        require(
            availableAuctionIds.contains(_auctionId),
            Errors.NOT_EXISTED_AUCTIONID
        );

        AuctionInfo storage auctionInfo = auctionInfos[_auctionId];
        require(auctionInfo.seller != msg.sender, Errors.INVALID_BUYER);

        require(
            currentTime >= auctionInfo.startTime &&
                currentTime < auctionInfo.endTime,
            Errors.NOT_SALE_PERIOD
        );

        uint256 minimumBidPrice = (auctionInfo.highestBidPrice == 0)
            ? auctionInfo.minimumPrice
            : auctionInfo.highestBidPrice;

        require(_bidPrice > minimumBidPrice, Errors.LOW_BID_PRICE);

        address oldWinner = auctionInfo.highestBidder;
        uint256 oldBidPrice = auctionInfo.highestBidPrice;

        auctionInfo.highestBidder = bidder;
        auctionInfo.highestBidPrice = _bidPrice;

        IERC20(auctionInfo.paymentToken).safeTransferFrom(
            bidder,
            address(this),
            _bidPrice
        );

        if (oldWinner != address(0)) {
            IERC20(auctionInfo.paymentToken).safeTransfer(
                oldWinner,
                oldBidPrice
            );
        }

        emit PlaceBid(bidder, _auctionId, _bidPrice);
    }

    /// @inheritdoc IChronosMarketPlace
    function placeBidWithETH(
        uint256 _auctionId
    ) external payable override nonReentrant whenNotPaused {
        address bidder = msg.sender;
        uint256 bidPrice = msg.value;
        uint256 currentTime = block.timestamp;

        require(bidder == tx.origin, Errors.NOT_ALLOWED_CALL);

        require(
            availableAuctionIds.contains(_auctionId),
            Errors.NOT_EXISTED_AUCTIONID
        );

        AuctionInfo storage auctionInfo = auctionInfos[_auctionId];
        require(auctionInfo.seller != msg.sender, Errors.INVALID_BUYER);

        require(auctionInfo.paymentToken == address(0), Errors.INVALID_TOKEN);

        require(
            currentTime >= auctionInfo.startTime &&
                currentTime < auctionInfo.endTime,
            Errors.NOT_SALE_PERIOD
        );

        uint256 minimumBidPrice = (auctionInfo.highestBidPrice == 0)
            ? auctionInfo.minimumPrice
            : auctionInfo.highestBidPrice;

        require(bidPrice > minimumBidPrice, Errors.LOW_BID_PRICE);

        address oldWinner = auctionInfo.highestBidder;
        uint256 oldBidPrice = auctionInfo.highestBidPrice;

        auctionInfo.highestBidder = bidder;
        auctionInfo.highestBidPrice = bidPrice;

        if (oldWinner != address(0)) {
            (bool sent, ) = payable(oldWinner).call{value: oldBidPrice}("");
            if (!sent) {
                refundToUser[oldWinner] += oldBidPrice;
                emit TransferFailForETH(oldWinner);
            }
        }

        emit PlaceBid(bidder, _auctionId, bidPrice);
    }

    /// @inheritdoc IChronosMarketPlace
    function refundBidprice() external override nonReentrant whenNotPaused {
        address user = msg.sender;
        require(refundToUser[user] > 0, Errors.LOW_ETH_BALANCE);

        uint256 price = refundToUser[user];
        refundToUser[user] = 0;

        (bool success, ) = payable(user).call{value: price}("");
        require(success, Errors.FAILED_TRANSFER);

        emit RefundBidPrice(user, price);
    }

    /// Offer

    /// @inheritdoc IChronosMarketPlace
    function makeOffer(
        address _nft,
        uint256 _tokenId,
        address _paymentToken,
        uint256 _offerPrice
    ) external override nonReentrant whenNotPaused {
        require(isChronosNft(_nft), Errors.NOT_CHRONOS_NFT);

        require(allowedTokens[_paymentToken], Errors.INVALID_TOKEN);

        address offeror = msg.sender;

        _setOfferId(offerId, offeror, true);

        offerInfos[offerId++] = OfferInfo(
            offeror,
            _paymentToken,
            _nft,
            _tokenId,
            _offerPrice
        );

        IERC20(_paymentToken).safeTransferFrom(
            offeror,
            address(this),
            _offerPrice
        );

        emit MakeOffer(
            offerId - 1,
            offeror,
            _nft,
            _tokenId,
            _paymentToken,
            _offerPrice
        );
    }

    /// @inheritdoc IChronosMarketPlace
    function makeOfferWithETH(
        address _nft,
        uint256 _tokenId,
        address _paymentToken,
        uint256 _offerPrice
    ) external payable override nonReentrant whenNotPaused {
        require(isChronosNft(_nft), Errors.NOT_CHRONOS_NFT);

        require(_paymentToken == address(0), Errors.INVALID_TOKEN);

        require(
            msg.value >= _offerPrice && _offerPrice > 0,
            Errors.INVALID_PRICE
        );

        address offeror = msg.sender;

        _setOfferId(offerId, offeror, true);

        offerInfos[offerId++] = OfferInfo(
            offeror,
            _paymentToken,
            _nft,
            _tokenId,
            _offerPrice
        );

        emit MakeOffer(
            offerId - 1,
            offeror,
            _nft,
            _tokenId,
            _paymentToken,
            _offerPrice
        );
    }

    /// @inheritdoc IChronosMarketPlace
    function getAvailableOfferIds()
        external
        view
        override
        returns (uint256[] memory)
    {
        return availableOfferIds.values();
    }

    /// @inheritdoc IChronosMarketPlace
    function acceptOffer(
        uint256 _offerId
    ) external override nonReentrant whenNotPaused {
        address sender = msg.sender;
        OfferInfo storage offerInfo = offerInfos[_offerId];
        require(
            availableOfferIds.contains(_offerId),
            Errors.NOT_EXISTED_OFFERID
        );

        require(
            IERC721(offerInfo.nft).ownerOf(offerInfo.tokenId) == sender,
            Errors.NO_PERMISSION
        );

        uint256 price = offerInfo.offerPrice;
        uint16 NFTType = tokenType[offerInfo.nft];
        uint256 fee = (price * platformFee[NFTType - 1]) / FIXED_POINT;

        _setOfferId(_offerId, offerInfo.offeror, false);

        if (offerInfo.paymentToken == address(0)) {
            payable(sender).transfer(price - fee);
            payable(treasury).transfer(fee);
        } else {
            IERC20(offerInfo.paymentToken).safeTransfer(sender, price - fee);
            IERC20(offerInfo.paymentToken).safeTransfer(treasury, fee);
        }

        IERC721(offerInfo.nft).safeTransferFrom(
            sender,
            offerInfo.offeror,
            offerInfo.tokenId
        );

        emit AcceptOffer(_offerId, sender);
    }

    /// @inheritdoc IChronosMarketPlace
    function cancelOffer(
        uint256 _offerId
    ) external override nonReentrant whenNotPaused {
        address sender = msg.sender;
        OfferInfo storage offerInfo = offerInfos[_offerId];
        require(
            availableOfferIds.contains(_offerId),
            Errors.NOT_EXISTED_OFFERID
        );
        require(offerInfo.offeror == sender, Errors.NO_PERMISSION);

        _setOfferId(_offerId, offerInfo.offeror, false);

        if (offerInfo.paymentToken == address(0)) {
            payable(sender).transfer(offerInfo.offerPrice);
        } else {
            IERC20(offerInfo.paymentToken).safeTransfer(
                sender,
                offerInfo.offerPrice
            );
        }

        emit CancelOffer(_offerId);
    }

    function _setSaleId(
        uint256 _saleId,
        address _seller,
        bool _isAdd
    ) internal {
        if (_isAdd) {
            availableSaleIds.add(_saleId);
            userSaleIds[_seller].add(_saleId);
        } else {
            availableSaleIds.remove(_saleId);
            userSaleIds[_seller].remove(_saleId);
        }
    }

    function _setAuctionId(
        uint256 _auctionId,
        address _auctionMaker,
        bool _isAdd
    ) internal {
        if (_isAdd) {
            availableAuctionIds.add(_auctionId);
            userAuctionIds[_auctionMaker].add(_auctionId);
        } else {
            availableAuctionIds.remove(_auctionId);
            userAuctionIds[_auctionMaker].remove(_auctionId);
        }
    }

    function _setOfferId(
        uint256 _offerId,
        address _offerMaker,
        bool _isAdd
    ) internal {
        if (_isAdd) {
            availableOfferIds.add(_offerId);
            userOfferIds[_offerMaker].add(_offerId);
        } else {
            availableOfferIds.remove(_offerId);
            userOfferIds[_offerMaker].remove(_offerId);
        }
    }

    fallback() external payable {}

    receive() external payable {}
}
