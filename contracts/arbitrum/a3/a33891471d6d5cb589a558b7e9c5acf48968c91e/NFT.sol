// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "./Ownable.sol";
import "./ERC721.sol";
import "./Counters.sol";
import "./ERC721URIStorage.sol";
import "./ReentrancyGuard.sol";
import "./IERC2981.sol";

interface IBaseIncomeStream {
    function getIncomeStreamContracts(address _erc721, uint256 _tokenId)
        external
        view
        returns (address[] memory);
}

struct RoyaltyBeneficiary {
    address payable beneficiary; // beneficiary address
    uint256 priceIncreasePercent; // royalty for price increase
    uint256 salePricePercent; // royalty for sale price
}

struct NFTInformation {
    uint256 NFTID; // NFT ID
    uint256 lastPrice; // last price
    uint256 minimumPriceIncrease; // percentage value using for calculate increasing value each new purchase
    address creator; // NFT's creator address
    address payable currentOwner; // current NFT's onwer address
    bool isBuyingAvailable; // is buying available status
    bool isOwnershipRoyalty; // is ownership royalty status
    bool enabledOffer; // Allow owner to have right to match offers to refuse sale
    uint256 totalSales; // total sales
}

struct Offer {
    uint256 NFTID;
    address buyer;
    uint256 bidAmount; // wei
    uint256 startTime; //start time of the offer
    uint256 endTime; // end time of the offer
    bool isActive;
    address incomeStreamAdmin;
}

// NFT contract
contract ExitAndUtility is
    ERC721,
    IERC2981,
    ERC721URIStorage,
    Ownable,
    ReentrancyGuard
{
    using Strings for uint256;

    using Counters for Counters.Counter;
    Counters.Counter private supply;

    uint256 private constant SUPPORT_PERCENTAGE_DECIMALS = 10**18;
    uint256 private expireOfferTime = 2 days;
    bool private paused = false;
    uint256 public constant version = 1;
    // mapping NFTID to struct NFTInformation
    mapping(uint256 => NFTInformation) private NFTSInformation;

    // mapping NFTID to struct RoyaltyBeneficiary
    mapping(uint256 => mapping(uint256 => RoyaltyBeneficiary))
        private royaltyBeneficiaries;

    mapping(uint256 => Offer) public offers;

    event LogCreateNFT(uint256 indexed _tokenId, address indexed _from);
    event LogPriceHistory(
        uint256 indexed _tokenId,
        address indexed _seller,
        uint256 _price,
        uint256 _timestamp
    );
    event LogBuyNFT(
        uint256 indexed _tokenId,
        address indexed _seller,
        address indexed _buyer,
        uint256 _price
    );
    event LogOfferNFT(
        uint256 indexed _tokenId,
        address indexed _seller,
        address indexed _buyer,
        uint256 _price
    );

    event LogSetExpireOfferTime(address indexed _caller, uint256 _time);
    event LogEnableForceBuy(uint256 indexed _tokenId, address indexed _caller);

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _uri,
        uint256 _price,
        uint256 _minimumPriceIncrease,
        bool _isOwnershipRoyalty,
        uint256 _priceIncreasePercent,
        uint256 _salePricePercent,
        address _beneficiary,
        bool _isBuyingAvailable,
        bool _enabledOffer
    ) ERC721(_name, _symbol) {
        create(
            _uri,
            _price,
            _minimumPriceIncrease,
            _isOwnershipRoyalty,
            _priceIncreasePercent,
            _salePricePercent,
            address(_beneficiary),
            _isBuyingAvailable,
            _enabledOffer
        );
    }

    // Modifier check contract not pause
    modifier whenNotPaused() {
        require(!paused, "CONTRACT_PAUSED!");
        _;
    }
    // Modifier check contract not pause
    modifier whenNotZeroAddress(address _user) {
        require(_user != address(0), "NOT_A_ZERO_ADDRESS!");
        _;
    }

    /// @dev Function create NFT
    /// @param _uri Metadata NFT uri (json uri)
    /// @param _price NFT price(wei)
    /// @param _minimumPriceIncrease Minimum Price Increase Percentage
    /// @param _isOwnershipRoyalty ownership royalty status(true/false)
    /// @param _priceIncreasePercent Price increasing percent
    /// @param _salePricePercent Sale Price percent
    /// @param _enabledOffer Allow owner to have right to match offers to refuse sale
    /// @param _beneficiary beneficiary address
    function create(
        string memory _uri,
        uint256 _price,
        uint256 _minimumPriceIncrease,
        bool _isOwnershipRoyalty,
        uint256 _priceIncreasePercent,
        uint256 _salePricePercent,
        address _beneficiary,
        bool _isBuyingAvailable,
        bool _enabledOffer
    ) public whenNotPaused whenNotZeroAddress(_beneficiary) returns (uint256) {
        require(
            _priceIncreasePercent + _salePricePercent <= 50,
            "ROYALTY_MUST_BE_LESS_OR_EQUAL_50_PERCENTAGE"
        );
        if (_isBuyingAvailable) {
            require(_price > 0, "PRICE_MUST_BE_GREATER_THAN_ZERO");
        }
        // next NFT ID will be  currentSupply + 1
        uint256 NFTID = supply.current() + 1;
        address currentCreator = _beneficiary;
        if (NFTID > 1) {
            currentCreator == msg.sender;
        }

        // set NFT Information
        NFTSInformation[NFTID] = NFTInformation(
            NFTID,
            _price,
            _minimumPriceIncrease,
            currentCreator,
            payable(_beneficiary),
            _isBuyingAvailable,
            _isOwnershipRoyalty,
            _enabledOffer,
            0
        );
        // set royalty beneficiaries for owner (first user)
        if (_isBuyingAvailable) {
            royaltyBeneficiaries[NFTID][0] = RoyaltyBeneficiary(
                payable(_beneficiary),
                _priceIncreasePercent * SUPPORT_PERCENTAGE_DECIMALS,
                _salePricePercent * SUPPORT_PERCENTAGE_DECIMALS
            );
        }

        // increase current supply
        supply.increment();
        emit LogCreateNFT(NFTID, currentCreator);
        emit LogPriceHistory(NFTID, currentCreator, _price, block.timestamp);
        // mint a new NFT and beneficiary is owner of that NFT
        _safeMint(_beneficiary, NFTID);
        // set metadata uri to that NFT
        _setTokenURI(NFTID, _uri);
        return NFTID;
    }

    /// @dev Function enable force buy NFT
    /// @param _tokenId NFT ID
    /// @param _price NFT price(wei)
    /// @param _minimumPriceIncrease Minimum Price Increase Percentage
    /// @param _isOwnershipRoyalty ownership royalty status(true/false)
    /// @param _priceIncreasePercent Price increasing percent
    /// @param _salePricePercent Sale Price percent
    /// @param _enabledOffer Allow owner to have right to match offers to refuse sale
    function enableForceBuy(
        uint256 _tokenId,
        uint256 _price,
        uint256 _minimumPriceIncrease,
        bool _isOwnershipRoyalty,
        uint256 _priceIncreasePercent,
        uint256 _salePricePercent,
        bool _enabledOffer
    ) public whenNotPaused returns (uint256) {
        require(
            _priceIncreasePercent + _salePricePercent <= 50,
            "ROYALTY_MUST_BE_LESS_OR_EQUAL_50_PERCENTAGE"
        );
        require(_price > 0, "PRICE_MUST_BE_GREATER_THAN_ZERO");
        // require only NFT's owner do this method
        require(msg.sender == ownerOf(_tokenId), "ONLY_NFT_OWNER");

        NFTInformation memory currentNFT = getNFTInformation(_tokenId);
        require(!currentNFT.isBuyingAvailable, "NFT_ALREADY_ENABLE_FORCE_BUY");

        // set NFT Information
        NFTSInformation[_tokenId] = NFTInformation(
            _tokenId,
            _price,
            _minimumPriceIncrease,
            currentNFT.creator,
            payable(currentNFT.currentOwner),
            true,
            _isOwnershipRoyalty,
            _enabledOffer,
            0
        );
        // set royalty beneficiaries for owner (first user)
        royaltyBeneficiaries[_tokenId][0] = RoyaltyBeneficiary(
            payable(currentNFT.currentOwner),
            _priceIncreasePercent * SUPPORT_PERCENTAGE_DECIMALS,
            _salePricePercent * SUPPORT_PERCENTAGE_DECIMALS
        );
        emit LogPriceHistory(_tokenId, msg.sender, _price, block.timestamp);
        emit LogEnableForceBuy(_tokenId, msg.sender);
        return _tokenId;
    }

    /// @dev Function check all current tokenId of the _owner address.
    /// @param _owner Address wallet that want to get.
    function walletOfOwner(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        uint256 totalToken = totalSupply();
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        uint256 currentIndex = 0;
        for (uint256 i = 1; i <= totalToken; i++) {
            if (ownerOf(i) == _owner) {
                tokenIds[currentIndex++] = uint256(i);
            }
        }
        return tokenIds;
    }

    /// @dev Function return metadate uri of a token ID.
    /// @param _tokenId token ID.
    function tokenURI(uint256 _tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(_tokenId);
    }

    /// @dev Function set metadata uri of a token ID.
    /// @param _tokenId token ID.
    /// @param _tokenURI token uri
    function setTokenURI(uint256 _tokenId, string memory _tokenURI)
        public
        whenNotPaused
    {
        require(msg.sender == ownerOf(_tokenId), "ONLY_NFT_OWNER");
        super._setTokenURI(_tokenId, _tokenURI);
    }

    /// @dev Function burn NFT by token ID.
    /// @param _tokenId token ID.
    function _burn(uint256 _tokenId)
        internal
        override(ERC721, ERC721URIStorage)
    {
        super._burn(_tokenId);
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view override {
        require(msg.sender == super.ownerOf(1), "ONLY_APP_OWNER");
    }

    /// @dev Function pause status
    /// @param _status status(true/false).
    function setPaused(bool _status) public onlyOwner {
        paused = _status;
    }

    /// @dev Function get pause status
    function getPaused() public view returns (bool) {
        return paused;
    }

    /// @dev Function set expire time offer
    /// @param _time time expire offer. (second)
    function setExpireOfferTime(uint256 _time) public onlyOwner {
        expireOfferTime = _time;
        emit LogSetExpireOfferTime(msg.sender, _time);
    }

    /// @dev Function get expire time offer
    function getExpireOfferTime() public view returns (uint256) {
        return expireOfferTime;
    }

    // Modifier check token exists by token ID
    modifier whenTokenExists(uint256 _tokenId) {
        require(_exists(_tokenId), "INVALID_TOKEN");
        _;
    }

    // Modifier check valid index in royaltyBeneficiaries
    modifier whenValidIndex(uint256 _tokenId, uint256 _index) {
        require(
            NFTSInformation[_tokenId].totalSales >= _index,
            "INVALID_INDEX"
        );
        _;
    }

    /// @dev Function get support percentage decimals
    function supportPercentageDecimals() public pure returns (uint256) {
        return SUPPORT_PERCENTAGE_DECIMALS;
    }

    /// @dev Function get NFT information by tokenId
    /// @param _tokenId token ID.
    function getNFTInformation(uint256 _tokenId)
        public
        view
        whenTokenExists(_tokenId)
        returns (NFTInformation memory)
    {
        return NFTSInformation[_tokenId];
    }

    /// @dev Function get royalty Beneficiary
    /// @param _tokenId token ID.
    /// @param _index index need to get in royaltyBeneficiaries
    function getRoyaltyBeneficiary(uint256 _tokenId, uint256 _index)
        public
        view
        whenTokenExists(_tokenId)
        whenValidIndex(_tokenId, _index)
        returns (RoyaltyBeneficiary memory)
    {
        return royaltyBeneficiaries[_tokenId][_index];
    }

    /// @dev Function get royalty Beneficiaries
    /// @param _tokenId token ID.
    function getRoyaltyBeneficiaries(uint256 _tokenId)
        public
        view
        whenTokenExists(_tokenId)
        returns (RoyaltyBeneficiary[] memory)
    {
        NFTInformation memory currentNFT = getNFTInformation(_tokenId);
        RoyaltyBeneficiary[] memory lists = new RoyaltyBeneficiary[](
            currentNFT.totalSales + 1
        );
        for (uint256 i = 0; i <= currentNFT.totalSales; i++) {
            lists[i] = royaltyBeneficiaries[_tokenId][i];
        }
        return lists;
    }

    /// @dev Function get offer of an NFT
    /// @param _tokenId token ID.
    function getOffer(uint256 _tokenId)
        public
        view
        whenTokenExists(_tokenId)
        returns (Offer memory)
    {
        return offers[_tokenId];
    }

    /// @dev Function set  NFT information
    /// @param _tokenId token ID.
    /// @param _newPrice new price.
    /// @param _owner new owner.
    /// @param _totalSales new total Sales.
    function setNFTInformation(
        uint256 _tokenId,
        uint256 _newPrice,
        address _owner,
        uint256 _totalSales
    ) private whenTokenExists(_tokenId) whenNotZeroAddress(_owner) {
        NFTSInformation[_tokenId].lastPrice = _newPrice;
        NFTSInformation[_tokenId].currentOwner = payable(_owner);
        NFTSInformation[_tokenId].totalSales = _totalSales;
    }

    /// @dev Function set royalty Beneficiaries
    /// @param _tokenId token ID.
    /// @param _index index need to get in royaltyBeneficiaries
    /// @param _beneficiary new beneficiary.
    /// @param _priceIncreasePercent Percent of price increase.
    /// @param _salePricePercent Percent of sale price.
    function setRoyaltyBeneficiary(
        uint256 _tokenId,
        uint256 _index,
        address payable _beneficiary,
        uint256 _priceIncreasePercent,
        uint256 _salePricePercent
    ) private whenTokenExists(_tokenId) whenNotZeroAddress(_beneficiary) {
        royaltyBeneficiaries[_tokenId][_index].beneficiary = payable(
            _beneficiary
        );
        royaltyBeneficiaries[_tokenId][_index]
            .priceIncreasePercent = _priceIncreasePercent;
        royaltyBeneficiaries[_tokenId][_index]
            .salePricePercent = _salePricePercent;
    }

    /// @dev Function get total supply
    function totalSupply() public view returns (uint256) {
        return supply.current();
    }

    /// @dev Function with draw eth in contract balance
    function withdraw() public nonReentrant onlyOwner {
        // This will transfer the remaining contract balance to the owner.
        // Do not remove this otherwise you will not be able to withdraw the funds.
        // =============================================================================
        (bool os, ) = payable(super.ownerOf(1)).call{
            value: address(this).balance
        }("");
        require(os);
        // =============================================================================
    }

    /// @dev Function get Royalty  by NFT ID and index
    /// @param _tokenId token ID.
    /// @param _index token index
    function getRoyalty(uint256 _tokenId, uint256 _index)
        public
        view
        returns (RoyaltyBeneficiary memory)
    {
        return royaltyBeneficiaries[_tokenId][_index];
    }

    /// @dev Function get NFT admin address
    function appAdmin() public view returns (address payable) {
        return payable(NFTSInformation[1].currentOwner);
    }

    /// @dev Function get income stream addresses of maestro nft.
    /// @param _baseIncomeStream Base income stream contract address.
    function incomeStreamContracts(address _baseIncomeStream)
        private
        view
        returns (address[] memory)
    {
        return
            IBaseIncomeStream(_baseIncomeStream).getIncomeStreamContracts(
                address(this),
                1
            );
    }

    /// @dev Function seller update nft price.
    /// @param _tokenId token ID.
    /// @param _newPrice New price.
    function updatePrice(uint256 _tokenId, uint256 _newPrice)
        public
        whenNotPaused
    {
        require(_newPrice >= 0, "INVALID_PRICE");
        Offer memory offer = offers[_tokenId];
        require(msg.sender == ownerOf(_tokenId) && !offer.isActive, "ONLY_NFT_OWNER_PERFORM_THIS_ACTION");
        NFTSInformation[_tokenId].lastPrice = _newPrice;
        emit LogPriceHistory(_tokenId, msg.sender, _newPrice, block.timestamp);
    }

    /// @dev Function create purchase.
    /// @param _tokenId token ID.
    /// @param _baseIncomeStream contract address of Base income sctream contract.
    /// @param _appAdminIncomeStream contract address of income sctream contract attached to Base income sctream.
    function createPurchase(
        uint256 _tokenId,
        address _baseIncomeStream,
        address _appAdminIncomeStream
    ) public payable whenNotPaused {
        NFTInformation memory currentNFT = getNFTInformation(_tokenId);
        require(
            NFTSInformation[_tokenId].isBuyingAvailable,
            "METHOD_NOT_AVAILABLE"
        );
        Offer memory offer = offers[_tokenId];
        uint256 currentAmount = currentNFT.lastPrice;
        if (offer.isActive) {
            require(offer.endTime > block.timestamp, "TIME_END");
            currentAmount = offer.bidAmount;
        }
        uint256 minOffer = (currentAmount *
            (100 + currentNFT.minimumPriceIncrease)) / 100;
        // There are 2 cases seller can buy the same price with nft price
        // 1. When enable offer for the nft, seller can purchase a same price with NFT price
        // 2. Seller buy the first time
        if (msg.sender == ownerOf(_tokenId)) {
            if (currentNFT.enabledOffer || currentNFT.totalSales == 0) {
                minOffer = currentAmount;
            }
        }
        require(msg.value >= minOffer, "INVALID_AMOUNT");
        address[] memory incomeStreamAddresses = incomeStreamContracts(
            _baseIncomeStream
        );
        require(
            incomeStreamAddresses.length > 0,
            "INVALID_BASE_INCOME_STREAM_ADDRESS"
        );
        require(
            incomeStreamAddresses[0] == _appAdminIncomeStream,
            "INVALID_APP_INCOME_STREAM_ADDRESS"
        );
        offers[_tokenId] = Offer(
            _tokenId,
            msg.sender,
            msg.value,
            block.timestamp,
            block.timestamp + expireOfferTime,
            true,
            _appAdminIncomeStream
        );
        // only do this action when the NFT enable offer
        if (currentNFT.enabledOffer) {
            emit LogOfferNFT(
                _tokenId,
                ownerOf(_tokenId),
                msg.sender,
                msg.value
            );
        }

        if (msg.sender == ownerOf(_tokenId) || !currentNFT.enabledOffer) {
            forceBuy(_tokenId, msg.value, msg.sender);
        }
        if (currentNFT.enabledOffer || offer.isActive) {
            (bool sentPreviousBuyer, ) = payable(offer.buyer).call{
                value: offer.bidAmount
            }("");
            require(sentPreviousBuyer, "FAILED_SEND_PAYMENT_PREVIOUS_BUYER");
        }
    }

    /// @dev Function confirm offer.
    /// @param _tokenId token ID.
    function confirmPurchase(uint256 _tokenId) public whenNotPaused {
        require(
            NFTSInformation[_tokenId].isBuyingAvailable,
            "METHOD_NOT_AVAILABLE"
        );
        Offer memory offer = offers[_tokenId];
        require(offer.isActive, "OFFER_NOT_ACTIVE");
        require(offer.endTime < block.timestamp, "OFFER_NOT_END_YET");
        forceBuy(_tokenId, offer.bidAmount, offer.buyer);
    }

    /// @dev Function calculate royalty
    /// @param _royalty royalty of beneficiaries.
    /// @param _nftPrice current nft price.
    /// @param _buyingPirce buying price.
    function calculateRoyaltyPrice(
        RoyaltyBeneficiary memory _royalty,
        uint256 _nftPrice,
        uint256 _buyingPirce
    ) private pure returns (uint256) {
        if (
            _royalty.salePricePercent > 0 && _royalty.priceIncreasePercent > 0
        ) {
            return
                ((_buyingPirce - _nftPrice) * _royalty.priceIncreasePercent) /
                (100 * supportPercentageDecimals()) +
                (_buyingPirce * _royalty.salePricePercent) /
                (100 * supportPercentageDecimals());
        } else if (_royalty.priceIncreasePercent > 0) {
            return
                ((_buyingPirce - _nftPrice) * _royalty.priceIncreasePercent) /
                (100 * supportPercentageDecimals());
        } else if (_royalty.salePricePercent > 0) {
            return
                (_buyingPirce * _royalty.salePricePercent) /
                (100 * supportPercentageDecimals());
        } else {
            return 0;
        }
    }

    /// @dev Function execute buying .
    /// @param _tokenId token ID.
    /// @param _buyingPrice buying amount.
    /// @param _buyer address of buyer.
    function forceBuy(
        uint256 _tokenId,
        uint256 _buyingPrice,
        address _buyer
    ) private {
        NFTInformation memory currentNFT = getNFTInformation(_tokenId);
        Offer memory offer = offers[_tokenId];
        setNFTInformation(
            _tokenId,
            _buyingPrice,
            _buyer,
            currentNFT.totalSales + 1
        );
        if (_tokenId == 1) {
            // update first NFT beneficiary
            royaltyBeneficiaries[1][0].beneficiary = payable(_buyer);
            // transfer ownership to new owner
            super._transferOwnership(_buyer);
        }
        // transfer token from current owner to buyer
        super._transfer(currentNFT.currentOwner, _buyer, _tokenId);
        if (offer.isActive) {
            delete offers[_tokenId];
        }
        if (currentNFT.isOwnershipRoyalty) {
            // finalRoyalty is store last Royalty
            RoyaltyBeneficiary memory finalRoyalty = RoyaltyBeneficiary(
                payable(address(this)),
                0,
                0
            );

            // check if this is the first purchase
            if (currentNFT.totalSales == 0) {
                finalRoyalty = getRoyalty(_tokenId, 0);
                // add current buyer to royalty beneficiary mapping, Royalty will be a half of final beneficiary
                setRoyaltyBeneficiary(
                    _tokenId,
                    currentNFT.totalSales + 1,
                    payable(_buyer),
                    finalRoyalty.priceIncreasePercent / 2,
                    finalRoyalty.salePricePercent / 2
                );
                // transfer all ether from buyer waller to current NFT's owner wallet
                bool sentAwardFirstBeneficiary = false;
                (sentAwardFirstBeneficiary, ) = currentNFT.currentOwner.call{
                    value: _buyingPrice
                }("");
                require(sentAwardFirstBeneficiary, "FAILED_SEND_PAYMENT_OWNER");
            } else {
                // total award to beneficiaries
                uint256 totalAwardToBeneficiaries = 0;
                for (uint256 i = 0; i <= currentNFT.totalSales; i++) {
                    // get current royalty beneficiaries list information
                    RoyaltyBeneficiary
                        memory currentRoyaltyBeneficiary = getRoyaltyBeneficiary(
                            _tokenId,
                            i
                        );
                    // store current royalty to finalRoyalty variables
                    finalRoyalty = currentRoyaltyBeneficiary;
                    if (i < currentNFT.totalSales) {
                        // calculate for Beneficiary's i
                        uint256 awardToBeneficiary = calculateRoyaltyPrice(
                            finalRoyalty,
                            currentNFT.lastPrice,
                            _buyingPrice
                        );
                        if (awardToBeneficiary > 1) {
                            // transfer calculate ether from buyer waller to  Beneficiary's i
                            bool sentAwardCurrentBeneficiary = false;
                            (
                                sentAwardCurrentBeneficiary,

                            ) = currentRoyaltyBeneficiary.beneficiary.call{
                                value: awardToBeneficiary
                            }("");
                            require(
                                sentAwardCurrentBeneficiary,
                                "FAILED_SEND_PAYMENT_BENEFICIARY"
                            );
                            // add awardToBeneficiary to totalAwardToBeneficiaries
                            totalAwardToBeneficiaries += awardToBeneficiary;
                        } else {
                            break;
                        }
                    }
                }
                uint256 appFee = calculateRoyaltyPrice(
                    finalRoyalty,
                    currentNFT.lastPrice,
                    _buyingPrice
                );
                // add current buyer to royalty beneficiary mapping, Royalty will be a half of final beneficiary
                setRoyaltyBeneficiary(
                    _tokenId,
                    currentNFT.totalSales + 1,
                    payable(_buyer),
                    finalRoyalty.priceIncreasePercent / 2,
                    finalRoyalty.salePricePercent / 2
                );
                // transfer to Income stream admin address
                if (appFee > 1) {
                    bool sentAdmin = false;
                    (sentAdmin, ) = payable(offer.incomeStreamAdmin).call{
                        value: appFee
                    }("");
                    require(sentAdmin, "FAILED_SEND_PAYMENT_ADMIN");
                }

                // transfer remaining ether from buyer to seller
                bool sentOwner = false;
                (sentOwner, ) = currentNFT.currentOwner.call{
                    value: _buyingPrice - totalAwardToBeneficiaries - appFee
                }("");
                require(sentOwner, "FAILED_SEND_PAYMENT_OWNER");
            }
        } else {
            uint256 appFee = 0;
            uint256 firstSellerAdward = 0;
            if (currentNFT.totalSales > 0) {
                // get current royalty beneficiaries list information
                RoyaltyBeneficiary
                    memory currentRoyaltyBeneficiary = getRoyaltyBeneficiary(
                        _tokenId,
                        0
                    );
                // store current royalty to finalRoyalty variables
                RoyaltyBeneficiary
                    memory firstRoyalty = currentRoyaltyBeneficiary;
                firstSellerAdward = calculateRoyaltyPrice(
                    firstRoyalty,
                    currentNFT.lastPrice,
                    _buyingPrice
                );

                appFee = firstSellerAdward / 2;

                // transfer to first seller
                (bool sentFirstSeller, ) = currentRoyaltyBeneficiary
                    .beneficiary
                    .call{value: firstSellerAdward}("");
                require(sentFirstSeller, "FAILED_SEND_PAYMENT_FIRST_SELLER");
                // transfer to NFT admin address
                if (appFee > 1) {
                    bool sentAdmin = false;
                    (sentAdmin, ) = payable(offer.incomeStreamAdmin).call{
                        value: appFee
                    }("");
                    require(sentAdmin, "FAILED_SEND_PAYMENT_ADMIN");
                }
            }
            // transfer all ether from buyer to seller
            bool sentOwner = false;
            (sentOwner, ) = currentNFT.currentOwner.call{
                value: _buyingPrice - appFee - firstSellerAdward
            }("");
            require(sentOwner, "FAILED_SEND_PAYMENT_OWNER");
        }

        // call event
        emit LogBuyNFT(_tokenId, currentNFT.currentOwner, _buyer, _buyingPrice);
        emit LogPriceHistory(_tokenId, _buyer, _buyingPrice, block.timestamp);
    }

    /// @dev Function update first NFT (admin is owner)
    /// @param _newOwner address of new owner.
    function updateAdminNFT(address _newOwner)
        private
        whenNotZeroAddress(_newOwner)
    {
        // get current nft owner
        address currentOwner = NFTSInformation[1].currentOwner;
        // transfer nft form old owner to new owner
        super._transfer(currentOwner, _newOwner, 1);
        // update first NFT owner
        NFTSInformation[1].currentOwner = payable(_newOwner);
        // update first NFT beneficiary
        royaltyBeneficiaries[1][0].beneficiary = payable(_newOwner);
        // transfer ownership to new owner
        super._transferOwnership(_newOwner);
    }

    /// @dev Function update users'sNFT
    /// @param _tokenId token ID.
    /// @param _from current owner address.
    /// @param _to new owner.
    function updateUsersNFT(
        uint256 _tokenId,
        address _from,
        address _to
    ) private whenNotZeroAddress(_to) {
        // get current nft owner
        NFTInformation memory currentNFT = NFTSInformation[_tokenId];
        // get newest beneficiary
        RoyaltyBeneficiary
            memory currentRoyaltyBeneficiary = getRoyaltyBeneficiary(
                _tokenId,
                currentNFT.totalSales
            );
        require(
            currentRoyaltyBeneficiary.beneficiary == _from &&
                currentNFT.currentOwner == _from,
            "INVALID_NFT_OWNER"
        );
        // update new beneficiary
        royaltyBeneficiaries[_tokenId][currentNFT.totalSales]
            .beneficiary = payable(_to);
        // update new owner
        NFTSInformation[_tokenId].currentOwner = payable(_to);
    }

    /**
     * @dev Transfers ownership of the contract to a new account ("newOwner").
     * Can only be called by the current owner.
     */
    function transferOwnership(address _newOwner)
        public
        override
        onlyOwner
        whenNotZeroAddress(_newOwner)
    {
        updateAdminNFT(_newOwner);
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * "onlyOwner" functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public override onlyOwner {
        // prevent this function
        // do nothing
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public virtual override {
        require(
            super._isApprovedOrOwner(super._msgSender(), tokenId),
            "ERC721: caller is not token owner or approved"
        );
        if (tokenId == 1) {
            updateAdminNFT(to);
        } else {
            updateUsersNFT(tokenId, from, to);
            super._safeTransfer(from, to, tokenId, data);
        }
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public virtual override {
        safeTransferFrom(_from, _to, _tokenId, "");
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public virtual override {
        //solhint-disable-next-line max-line-length
        require(
            super._isApprovedOrOwner(super._msgSender(), _tokenId),
            "ERC721: caller is not token owner or approved"
        );
        if (_tokenId == 1) {
            updateAdminNFT(_to);
        } else {
            updateUsersNFT(_tokenId, _from, _to);
            super._transfer(_from, _to, _tokenId);
        }
    }

    function supportsInterface(bytes4 _interfaceId)
        public
        view
        override(ERC721, IERC165)
        returns (bool)
    {
        return
            _interfaceId == type(IERC2981).interfaceId ||
            _interfaceId == type(IERC721).interfaceId ||
            super.supportsInterface(_interfaceId);
    }

    /// @dev Function get royalty information
    /// @param _tokenId Nft ID.
    /// @param _price Nft price.
    function royaltyInfo(uint256 _tokenId, uint256 _price)
        external
        view
        override(IERC2981)
        returns (address receiver, uint256 royaltyAmount)
    {
        RoyaltyBeneficiary
            memory currentRoyaltyBeneficiary = getRoyaltyBeneficiary(
                _tokenId,
                0
            );
        NFTInformation memory currentNFT = getNFTInformation(_tokenId);

        receiver = currentRoyaltyBeneficiary.beneficiary;
        royaltyAmount = calculateRoyaltyPrice(
            currentRoyaltyBeneficiary,
            currentNFT.lastPrice,
            _price
        );
    }

    fallback() external payable {}

    receive() external payable {}
}

