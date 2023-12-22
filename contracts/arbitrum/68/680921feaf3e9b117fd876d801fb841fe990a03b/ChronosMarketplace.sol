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
    mapping(address => uint16) tokenType;
    mapping(uint256 => SellInfo) public sellInfos;
    mapping(uint256 => AuctionInfo) public auctionInfos;
    mapping(uint256 => OfferInfo) public offerInfos;
    uint256 public saleId;
    uint256 public auctionId;
    uint256 public offerId;

    mapping(address => EnumerableSet.UintSet) private userSaleIds;
    mapping(address => EnumerableSet.UintSet) private userAuctionIds;
    mapping(address => mapping(address => EnumerableSet.UintSet))
        private userOfferIds;

    EnumerableSet.UintSet private availableSaleIds;
    EnumerableSet.UintSet private availableAuctionIds;
    EnumerableSet.UintSet private availableOfferIds;

    uint16 public platformFee;
    uint16 public constant FIXED_POINT = 1000;
    address public treasury;
    mapping(address => bool) public allowedTokens;
    IVoter vt;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _voterAddress, uint16 _platformFee) public initializer {
        __Ownable_init();
        require(_platformFee < FIXED_POINT, Errors.INVALID_FEE);
        saleId = 1;
        auctionId = 1;
        offerId = 1;
        vt = IVoter(_voterAddress);
        platformFee = _platformFee;
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
    function setPlatformFee(uint16 _platformFee) external override onlyOwner {
        require(_platformFee < FIXED_POINT, Errors.INVALID_FEE);
        platformFee = _platformFee;

        emit PlatformFeeSet(_platformFee);
    }

    /// @inheritdoc IChronosMarketPlace
    function setTreasury(address _treasury) external override onlyOwner {
        require(_treasury != address(0), Errors.INVALID_TREASURY_ADDRESS);
        treasury = _treasury;

        emit TreasurySet(_treasury);
    }

    /// @inheritdoc IChronosMarketPlace
    function setNftList(address[] memory _nftList) external override onlyOwner {
        require(_nftList.length > 0, Errors.EMPTY_NFTS);
        delete chronosNftList;

        for (uint16 i = 0; i < _nftList.length; i++) {
            chronosNftList.push(_nftList[i]);
            tokenType[_nftList[i]] = i + 1;
        }

        emit NftListSet(_nftList);
    }

    /// @inheritdoc IChronosMarketPlace
    function getChronosNftType(address _nft) public override returns (uint16) {
        if(tokenType[_nft] > 0) return tokenType[_nft];
        //if(tokenType[_nft] == 0 && vt.isGauge(_nft)) {
        if(false) {
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
        uint256 _saleDuration,
        uint256 _price
    ) external override whenNotPaused {
        address seller = msg.sender;
        require(isChronosNft(_nft), Errors.NOT_CHRONOS_NFT);
        require(allowedTokens[_paymentToken], Errors.INVALID_TOKEN);
        require(
            IERC721(_nft).ownerOf(_tokenId) == seller,
            Errors.SELLER_NOT_OWNER_OF_NFT
        );
        require(_saleDuration > 0, Errors.INVALID_SALE_DURATION);
        _setSaleId(saleId, seller, true);

        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + _saleDuration;

        IERC721(_nft).safeTransferFrom(seller, address(this), _tokenId);

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

        emit ListNftForFixed(
            _nft,
            _paymentToken,
            saleId - 1,
            _tokenId,
            _saleDuration,
            _price
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
        SellInfo memory sellInfo = sellInfos[_saleId];
        require(msg.sender == sellInfo.seller, Errors.NO_PERMISSION);

        IERC721(sellInfo.nft).safeTransferFrom(
            address(this),
            sellInfo.seller,
            sellInfo.tokenId
        );
        _setSaleId(_saleId, sellInfo.seller, false);

        emit CancelListNftForFixed(_saleId);
    }

    /// @inheritdoc IChronosMarketPlace
    function changeSaleInfo(
        uint256 _saleId,
        uint256 _saleDuration,
        uint256 _price
    ) external override nonReentrant whenNotPaused {
        require(availableSaleIds.contains(_saleId), Errors.NOT_EXISTED_SAILID);

        SellInfo memory sellInfo = sellInfos[_saleId];
        require(msg.sender == sellInfo.seller, Errors.NO_PERMISSION);
        require(_price > 0, Errors.INVALID_PRICE);
        require(_saleDuration > 0, Errors.INVALID_SALE_DURATION);

        sellInfo.startTime = block.timestamp;
        sellInfo.endTime = sellInfo.startTime + _saleDuration;
        sellInfo.price = _price;

        emit SaleInfoChanged(_saleId, sellInfo.price);
    }

    /// @inheritdoc IChronosMarketPlace
    function buyNow(
        uint256 _saleId
    ) external override whenNotPaused nonReentrant {
        address buyer = msg.sender;
        // uint256 amount = msg.value;
        uint256 currentTime = block.timestamp;
        require(availableSaleIds.contains(_saleId), Errors.NOT_EXISTED_SAILID);

        SellInfo storage saleInfo = sellInfos[_saleId];
        require(buyer != saleInfo.seller, Errors.INVALID_BUYER);
        require(currentTime < saleInfo.endTime, Errors.NOT_SALE_PERIOD);
        // require(amount > 0, Errors.INVALID_TOKEN_AMOUNT);
        require(saleInfo.buyer == address(0), Errors.ALREADY_SOLD);

        uint256 fee = (saleInfo.price * platformFee) / FIXED_POINT;
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
        saleInfo.buyer = buyer;

        _setSaleId(_saleId, saleInfo.seller, false);

        emit Bought(
            _saleId,
            saleInfo.nft,
            saleInfo.tokenId,
            saleInfo.seller,
            buyer,
            saleInfo.price
        );
    }

    /// Bid

    /// @inheritdoc IChronosMarketPlace
    function listNftForAuction(
        address _nft,
        uint256 _tokenId,
        address _paymentToken,
        uint256 _saleDuration,
        uint256 _minimumPrice
    ) external override whenNotPaused {
        address seller = msg.sender;
        require(isChronosNft(_nft), Errors.NOT_CHRONOS_NFT);
        require(allowedTokens[_paymentToken], Errors.INVALID_TOKEN);
        require(_minimumPrice > 0, Errors.INVALID_PRICE);
        require(
            IERC721(_nft).ownerOf(_tokenId) == seller,
            Errors.SELLER_NOT_OWNER_OF_NFT
        );
        require(_saleDuration > 0, Errors.INVALID_SALE_DURATION);

        _setAuctionId(auctionId, seller, true);

        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + _saleDuration;

        IERC721(_nft).safeTransferFrom(seller, address(this), _tokenId);

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

        emit ListNftForAuction(
            _nft,
            _paymentToken,
            auctionId,
            _tokenId,
            _saleDuration,
            _minimumPrice
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
    ) external override whenNotPaused onlyOwner{
        require(
            availableAuctionIds.contains(_auctionId),
            Errors.NOT_EXISTED_AUCTIONID
        );

        AuctionInfo storage auctionInfo = auctionInfos[_auctionId];

        _setAuctionId(_auctionId, auctionInfo.seller, false);

        if (auctionInfo.highestBidder != address(0)) {
            IERC20(auctionInfo.paymentToken).safeTransfer(
                auctionInfo.highestBidder,
                auctionInfo.highestBidPrice
            );
        }

        IERC721(auctionInfo.nft).safeTransferFrom(
            address(this),
            auctionInfo.seller,
            auctionInfo.tokenId
        );

        emit CancelListNftForAuction(_auctionId);
    }

    /// @inheritdoc IChronosMarketPlace
    function finishAuction(uint256 _auctionId) external override whenNotPaused {
        address sender = msg.sender;
        require(
            availableAuctionIds.contains(_auctionId),
            Errors.NOT_EXISTED_AUCTIONID
        );

        AuctionInfo storage auctionInfo = auctionInfos[_auctionId];

        require(
            block.timestamp >= auctionInfo.endTime,
            Errors.BEFORE_AUCTION_MATURITY
        );
        require(
            auctionInfo.seller == sender || auctionInfo.highestBidder == sender,
            Errors.NO_PERMISSION
        );

        if (auctionInfo.highestBidder != address(0)) {
            uint256 price = auctionInfo.highestBidPrice;
            uint256 fee = (price * platformFee) / FIXED_POINT;
            IERC20(auctionInfo.paymentToken).safeTransfer(
                auctionInfo.seller,
                price - fee
            );
            IERC20(auctionInfo.paymentToken).safeTransfer(treasury, fee);
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

        _setAuctionId(_auctionId, auctionInfo.seller, false);
        emit FinishAuction(_auctionId);
    }

    /// @inheritdoc IChronosMarketPlace
    function placeBid(
        uint256 _auctionId,
        uint256 _bidPrice
    ) external override whenNotPaused {
        address bidder = msg.sender;
        uint256 currentTime = block.timestamp;
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

        if (auctionInfo.highestBidder != address(0)) {
            IERC20(auctionInfo.paymentToken).safeTransfer(
                auctionInfo.highestBidder,
                auctionInfo.highestBidPrice
            );
        }

        IERC20(auctionInfo.paymentToken).safeTransferFrom(
            bidder,
            address(this),
            _bidPrice
        );

        auctionInfo.highestBidder = bidder;
        auctionInfo.highestBidPrice = _bidPrice;

        emit PlaceBid(
            bidder,
            _auctionId,
            _bidPrice
        );
    }

    /// Offer

    /// @inheritdoc IChronosMarketPlace
    function makeOffer(
        address _owner,
        address _nft,
        uint256 _tokenId,
        address _paymentToken,
        uint256 _offerPrice
    ) external override whenNotPaused {
        require(isChronosNft(_nft), Errors.NOT_CHRONOS_NFT);
        require(allowedTokens[_paymentToken], Errors.INVALID_TOKEN);
        require(
            IERC721(_nft).ownerOf(_tokenId) == _owner,
            Errors.INVALID_TOKEN_ID
        );
        address offeror = msg.sender;
        require(
            IERC20(_paymentToken).allowance(offeror, address(this)) >=
                _offerPrice,
            Errors.NOT_ENOUGH_ALLOWANCE
        );
        availableOfferIds.add(offerId);

        userOfferIds[_owner][_nft].add(offerId);

        offerInfos[offerId++] = OfferInfo(
            _owner,
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
            _paymentToken,
            _nft,
            _tokenId,
            _offerPrice
        );
    }

    /// @inheritdoc IChronosMarketPlace
    function getAvailableOffers(
        address _owner,
        address _nft
    ) external view override returns (OfferInfo[] memory, uint256[] memory) {
        uint256 length = userOfferIds[_owner][_nft].length();
        OfferInfo[] memory availableOffers = new OfferInfo[](length);
        uint256[] memory availableIds = userOfferIds[_owner][_nft].values();
        if (length == 0) {
            return (availableOffers, availableIds);
        }

        for (uint256 i = 0; i < length; i++) {
            uint256 id = availableIds[i];
            availableOffers[i] = offerInfos[id];
        }

        return (availableOffers, availableIds);
    }

    /// @inheritdoc IChronosMarketPlace
    function acceptOffer(uint256 _offerId) external override {
        address sender = msg.sender;
        OfferInfo memory offerInfo = offerInfos[_offerId];
        require(
            availableOfferIds.contains(_offerId),
            Errors.NOT_EXISTED_OFFERID
        );
        require(
            IERC721(offerInfo.nft).ownerOf(offerInfo.tokenId) == sender,
            Errors.NO_PERMISSION
        );

        uint256 price = offerInfo.offerPrice;
        uint256 fee = (price * platformFee) / FIXED_POINT;
        IERC20(offerInfo.paymentToken).safeTransfer(sender, price - fee);
        IERC20(offerInfo.paymentToken).safeTransfer(treasury, fee);

        IERC721(offerInfo.nft).safeTransferFrom(
            sender,
            offerInfo.offeror,
            offerInfo.tokenId
        );

        _removeAllOfferIds(offerInfo.owner, offerInfo.nft);

        emit AcceptOffer(_offerId);
    }

    function _removeAllOfferIds(address _owner, address _nft) internal {
        uint256[] memory values = userOfferIds[_owner][_nft].values();
        uint256 length = values.length;
        for (uint256 i = 0; i < length; i++) {
            uint256 value = values[i];
            userOfferIds[_owner][_nft].remove(value);
            availableOfferIds.remove(value);
        }
    }

    /// @inheritdoc IChronosMarketPlace
    function cancelOffer(uint256 _offerId) external override {
        address sender = msg.sender;
        OfferInfo storage offerInfo = offerInfos[_offerId];
        require(
            availableOfferIds.contains(_offerId),
            Errors.NOT_EXISTED_OFFERID
        );
        require(offerInfo.offeror == sender, Errors.NO_PERMISSION);

        IERC20(offerInfo.paymentToken).safeTransfer(
            sender,
            offerInfo.offerPrice
        );
        availableOfferIds.remove(_offerId);
        userOfferIds[offerInfo.owner][offerInfo.nft].remove(_offerId);
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
}
