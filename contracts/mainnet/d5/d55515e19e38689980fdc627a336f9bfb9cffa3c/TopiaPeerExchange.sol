// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./INFT.sol";
import "./IHUB.sol";
import "./IWETH.sol";
import "./IPYESwapRouter.sol";

contract TopiaPeerExchange is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // The Metatopia ERC721 token contracts
    INFT public GENESIS;
    INFT public ALPHA;
    INFT public RATS;

    // The address of the HUB contract
    IHUB public HUB;

    // The address of the WETH contract
    address public WETH;

    // The address of the TOPIA contract
    IERC20 public TOPIA;

    IPYESwapRouter public pyeSwapRouter;

    // The minimum percentage difference between the last offer amount and the current offer
    uint16 public minOfferIncrementPercentage;
    
    // The minimum listing and offer variables
    bool public useManualMinListPrice;
    uint256 public manualMinListPrice;
    uint16 public minListPercent;
    uint16 public minOfferPercent;

    // Restriction Bools
    bool public isPaused;
    bool public allListersAllowed = true;
    bool public allBuyersAllowed = true;
    bool public allOfferersAllowed = true;

    // The listing info
    struct Listing {
        // The address of the Lister
        address payable lister;
        // The current highest offer amount
        uint256 topiaAmount;
        // The Requested ETH for the listing
        uint256 requestedEth;
        // The time that the listing started
        uint256 startTime;
        // The time that the listing is scheduled to end
        uint256 endTime;
        // The address of the current highest offer
        address payable offerer;
        // The current offer below the requested ETH amount
        uint256 currentOffer;
        // The previous offer
        uint256 previousOffer;
        // The active offerId
        uint256 activeOfferId;
        // The number of offers placed
        uint16 numberOffers;
        // The statuses of the listing
        bool settled;
        bool canceled;
        bool failed;
    }
    mapping(uint256 => Listing) public listingId;
    uint256 private currentId = 1;
    uint256 private currentOfferId = 1;
    mapping(uint256 => uint256[]) public allListingOfferIds;

    struct Offers {
        address offerer;
        uint256 offerAmount;
        uint256 listingId;
        uint8 offerStatus; // 1 = active, 2 = outoffer, 3 = canceled, 4 = accepted
    }
    mapping(uint256 => Offers) public offerId;
    mapping(address => uint256[]) userOffers;
    uint256 public activeListingCount;

    uint16 public tax;
    address payable public taxWallet;

    modifier holdsNFTLister() {
        require(allListersAllowed || HUB.balanceOf(msg.sender) > 0 || GENESIS.balanceOf(msg.sender) > 0 || ALPHA.balanceOf(msg.sender) > 0 || RATS.balanceOf(msg.sender) > 0, "Must hold a Metatopia NFT");
        _;
    }

    modifier holdsNFTBuyer() {
        require(allBuyersAllowed || HUB.balanceOf(msg.sender) > 0 || GENESIS.balanceOf(msg.sender) > 0 || ALPHA.balanceOf(msg.sender) > 0 || RATS.balanceOf(msg.sender) > 0, "Must hold a Metatopia NFT");
        _;
    }

    modifier holdsNFTOfferer() {
        require(allOfferersAllowed || HUB.balanceOf(msg.sender) > 0 || GENESIS.balanceOf(msg.sender) > 0 || ALPHA.balanceOf(msg.sender) > 0 || RATS.balanceOf(msg.sender) > 0, "Must hold a Metatopia NFT");
        _;
    }

    modifier notPaused() {
        require(!isPaused, "Contract is Paused to new listings");
        _;
    }

    event ListingCreated(uint256 indexed ListingId, uint256 startTime, uint256 endTime, uint256 TopiaAmount, uint256 EthPrice);
    event OfferPlaced(uint256 indexed OfferId, uint256 indexed ListingId, address sender, uint256 value);
    event OfferCanceled(uint256 indexed OfferId, uint256 indexed ListingId, uint256 TimeStamp);
    event ListingSettled(uint256 indexed ListingId, address Buyer, address Seller, uint256 FinalAmount, uint256 TaxAmount, bool wasOffer, uint256 listedAmount);
    event ListingTimeBufferUpdated(uint256 timeBuffer);
    event ListingMinOfferIncrementPercentageUpdated(uint256 minOfferIncrementPercentage);
    event ListingRefunded(uint256 indexed ListingId, address Lister, uint256 TopiaRefundAmount, address Offerer, uint256 OffererRefundAmount, address Caller);
    event ListingCanceled(uint256 indexed ListingId, address Lister, uint256 TopiaAmount, uint256 TimeStamp);
    event Received(address indexed From, uint256 Amount);

    /**
     * @notice Initialize the listing house and base contracts,
     * populate configuration values, and pause the contract.
     * @dev This function can only be called once.
     */
    constructor(
        address _topia, 
        address _weth, 
        // address _genesis, 
        // address _alpha, 
        // address _hub, 
        address _router,
        uint16 _minOfferIncrementPercentage, 
        uint256 _minListPrice, 
        uint16 _minListPercent, 
        uint16 _minOfferPercent, 
        address payable _taxWallet, 
        uint16 _tax
    ) {
        TOPIA = IERC20(_topia);
        WETH = _weth;
        // GENESIS = INFT(_genesis);
        // ALPHA = INFT(_alpha);
        // HUB = IHUB(_hub);
        pyeSwapRouter = IPYESwapRouter(_router);
        minOfferIncrementPercentage = _minOfferIncrementPercentage;
        manualMinListPrice = _minListPrice;
        useManualMinListPrice = true;
        minListPercent = _minListPercent;
        minOfferPercent = _minOfferPercent;
        taxWallet = _taxWallet;
        tax = _tax;
    }

    /**
     * @notice Set the listing minimum offer increment percentage.
     * @dev Only callable by the owner.
     */
    function setMinOfferIncrementPercentage(uint16 _minOfferIncrementPercentage) external onlyOwner {
        minOfferIncrementPercentage = _minOfferIncrementPercentage;

        emit ListingMinOfferIncrementPercentageUpdated(_minOfferIncrementPercentage);
    }

    function setPaused(bool _flag) external onlyOwner {
        isPaused = _flag;
    }

    function setListersAllowed(bool _flag) external onlyOwner {
        allListersAllowed = _flag;
    }

    function setBuyersAllowed(bool _flag) external onlyOwner {
        allBuyersAllowed = _flag;
    }

    function setOfferersAllowed(bool _flag) external onlyOwner {
        allOfferersAllowed = _flag;
    }

    function setRatsContract(address _rats) external onlyOwner {
        RATS = INFT(_rats);
    }

    function setHubContract(address _hub) external onlyOwner {
        HUB = IHUB(_hub);
    }

    function setTax(address payable _taxWallet, uint16 _tax) external onlyOwner {
        taxWallet = _taxWallet;
        tax = _tax;
    }

    function setMinListPrice(uint256 _minListPrice) external onlyOwner {
        manualMinListPrice = _minListPrice;
    }

    function setUseManualMinListPrice(bool _flag) external onlyOwner {
        useManualMinListPrice = _flag;
    }

    function setMinListPercent(uint16 _percent) external onlyOwner {
        minListPercent = _percent;
    }

    function setMinOfferPercent(uint16 _percent) external onlyOwner {
        minOfferPercent = _percent;
    }

    function createListing(uint256 _topiaAmount, uint256 _requestedEth, uint256 _endTime) external notPaused holdsNFTLister nonReentrant {
        require((_requestedEth * 10**9) / _topiaAmount >= minListPrice(), "Listing Price too low");
        uint256 startTime = block.timestamp;
        uint256 _listingId = currentId++;

        listingId[_listingId].lister = payable(msg.sender);
        listingId[_listingId].topiaAmount = _topiaAmount;
        listingId[_listingId].requestedEth = _requestedEth;
        listingId[_listingId].startTime = startTime;
        listingId[_listingId].endTime = _endTime;
        activeListingCount++;

        TOPIA.safeTransferFrom(msg.sender, address(this), _topiaAmount);

        emit ListingCreated(_listingId, startTime, _endTime, _topiaAmount, _requestedEth);
    }

    function cancelListing(uint256 _id) external nonReentrant {
        require(msg.sender == listingId[_id].lister, "Only Lister can cancel");
        require(listingStatus(_id) == 1, "Listing is not active");
        listingId[_id].canceled = true;

        if(listingId[_id].offerer != address(0) && listingId[_id].currentOffer > 0) {
            _safeTransferETHWithFallback(listingId[_id].offerer, listingId[_id].currentOffer);
            listingId[_id].offerer = payable(address(0));
            listingId[_id].currentOffer = 0;
            offerId[listingId[_id].activeOfferId].offerStatus = 3;
        }
        activeListingCount--;
        TOPIA.safeTransfer(listingId[_id].lister, listingId[_id].topiaAmount);

        emit ListingCanceled(_id, listingId[_id].lister, listingId[_id].topiaAmount, block.timestamp);
        emit ListingRefunded(_id, listingId[_id].lister, listingId[_id].topiaAmount, listingId[_id].offerer, listingId[_id].currentOffer, msg.sender);
    }

    /**
     * @notice Create a offer for TOPIA, with a given ETH amount.
     * @dev This contract only accepts payment in ETH.
     */
    function createOffer(uint256 _id) external payable holdsNFTOfferer nonReentrant {
        require(listingStatus(_id) == 1, 'Topia Listing is not Active');
        require(block.timestamp < listingId[_id].endTime, 'Listing expired');
        require(msg.value <= listingId[_id].requestedEth, 'Must send less than requestedEth');
        require(msg.value >= listingId[_id].requestedEth * minOfferPercent / 10000, 'Must offer more than minimum offer amount');
        require(
            msg.value >= listingId[_id].currentOffer + ((listingId[_id].currentOffer * minOfferIncrementPercentage) / 10000),
            'Must send more than last offer by minOfferIncrementPercentage amount'
        );
        require(msg.sender != listingId[_id].lister, 'Lister not allowed to Offer');

        address payable lastOfferer = listingId[_id].offerer;
        uint256 _offerId = currentOfferId++;

        // Refund the last offerer, if applicable
        if (lastOfferer != address(0)) {
            _safeTransferETHWithFallback(lastOfferer, listingId[_id].currentOffer);  
            offerId[listingId[_id].activeOfferId].offerStatus = 2;
            listingId[_id].previousOffer = listingId[_id].currentOffer;
        }

        listingId[_id].currentOffer = msg.value;
        listingId[_id].offerer = payable(msg.sender);
        listingId[_id].activeOfferId = _offerId;
        listingId[_id].numberOffers++;
        allListingOfferIds[_id].push(_offerId);
        offerId[_offerId].offerer = msg.sender;
        offerId[_offerId].offerAmount = msg.value;
        offerId[_offerId].listingId = _id;
        offerId[_offerId].offerStatus = 1;
        userOffers[msg.sender].push(_offerId);

        emit OfferPlaced(_offerId, _id, msg.sender, msg.value);
    }

    function cancelOffer(uint256 _id, uint256 _offerId) external nonReentrant {
        require(offerId[_offerId].offerer == msg.sender, "Caller is not Offerer");
        require(offerId[_offerId].listingId == _id && listingId[_id].activeOfferId == _offerId, "IDs do not match");
        require(listingStatus(_id) == 1, "Topia Listing is not Active");
        require(offerId[_offerId].offerStatus == 1, "Offer is not active");

        _safeTransferETHWithFallback(payable(msg.sender), offerId[_offerId].offerAmount);
        offerId[listingId[_id].activeOfferId].offerStatus = 3;
        listingId[_id].currentOffer = listingId[_id].previousOffer;
        listingId[_id].offerer = payable(address(0));
        listingId[_id].activeOfferId = 0;

        emit OfferCanceled(_offerId, _id, block.timestamp);
    }

    /**
     * @notice Settle a listing to high offerer and paying out to the lister.
     */
    function acceptOffer(uint256 _id) external nonReentrant {
        require(msg.sender == listingId[_id].lister, "Only Lister can accept offer");
        require(listingStatus(_id) == 1, "Listing has already been settled or canceled");
        require(block.timestamp <= listingId[_id].endTime, "Listing has expired");
        require(listingId[_id].offerer != address(0), "No active Offerer");
        require(offerId[listingId[_id].activeOfferId].offerStatus == 1, "Offer is not active");

        listingId[_id].settled = true;
        activeListingCount--;

        uint256 taxAmount = listingId[_id].currentOffer * tax / 10000;
        uint256 finalEthAmount = listingId[_id].currentOffer - taxAmount;

        TOPIA.safeTransfer(listingId[_id].offerer, listingId[_id].topiaAmount);
        _safeTransferETHWithFallback(taxWallet, taxAmount);
        _safeTransferETHWithFallback(listingId[_id].lister, finalEthAmount);
        offerId[listingId[_id].activeOfferId].offerStatus = 4;

        emit ListingSettled(_id, listingId[_id].offerer, listingId[_id].lister, listingId[_id].currentOffer, taxAmount, true, listingId[_id].requestedEth);
    }

    function buyNow(uint256 _id) external payable holdsNFTBuyer nonReentrant {
        require(listingStatus(_id) == 1, 'Listing has already been settled or canceled');
        require(block.timestamp <= listingId[_id].endTime, 'Listing has expired');
        require(msg.value == listingId[_id].requestedEth, 'ETH Value must be equal to listing price');

        listingId[_id].settled = true;
        activeListingCount--;

        if(listingId[_id].offerer != address(0) && listingId[_id].currentOffer > 0) {
            _safeTransferETHWithFallback(listingId[_id].offerer, listingId[_id].currentOffer);
            offerId[listingId[_id].activeOfferId].offerStatus = 2;
        }

        uint256 taxAmount = listingId[_id].requestedEth * tax / 10000;
        uint256 finalEthAmount = listingId[_id].requestedEth - taxAmount;

        TOPIA.safeTransfer(msg.sender, listingId[_id].topiaAmount);
        _safeTransferETHWithFallback(taxWallet, taxAmount);
        _safeTransferETHWithFallback(listingId[_id].lister, finalEthAmount);

        emit ListingSettled(_id, listingId[_id].offerer, listingId[_id].lister, listingId[_id].requestedEth, taxAmount, false, listingId[_id].requestedEth);
    }

    function claimRefundOnExpire(uint256 _id) external nonReentrant {
        require(msg.sender == listingId[_id].lister || msg.sender == listingId[_id].offerer, 'Only Lister can accept offer');
        require(listingStatus(_id) == 3, 'Listing has not expired');
        listingId[_id].failed = true;
        activeListingCount--;

        if(listingId[_id].offerer != address(0) && listingId[_id].currentOffer > 0) {
            _safeTransferETHWithFallback(listingId[_id].offerer, listingId[_id].currentOffer);
            listingId[_id].offerer = payable(address(0));
            listingId[_id].currentOffer = 0;
        }
        TOPIA.safeTransfer(listingId[_id].lister, listingId[_id].topiaAmount);

        emit ListingRefunded(_id, listingId[_id].lister, listingId[_id].topiaAmount, listingId[_id].offerer, listingId[_id].currentOffer, msg.sender);
    }

    function listingStatus(uint256 _id) public view returns (uint8) {
        if (listingId[_id].canceled) {
        return 3; // CANCELED - Lister canceled
        }
        if ((block.timestamp > listingId[_id].endTime) && !listingId[_id].settled) {
        return 3; // FAILED - not sold by end time
        }
        if (listingId[_id].settled) {
        return 2; // SUCCESS - hardcap met
        }
        if ((block.timestamp <= listingId[_id].endTime) && !listingId[_id].settled) {
        return 1; // ACTIVE - deposits enabled
        }
        return 0; // QUEUED - awaiting start time
    }

    function getOffersByListingId(uint256 _id) external view returns (uint256[] memory offerIds) {
        uint256 length = allListingOfferIds[_id].length;
        offerIds = new uint256[](length);
        for(uint i = 0; i < length; i++) {
            offerIds[i] = allListingOfferIds[_id][i];
        }
    }

    function getOffersByUser(address _user) external view returns (uint256[] memory offerIds) {
        uint256 length = userOffers[_user].length;
        offerIds = new uint256[](length);
        for(uint i = 0; i < length; i++) {
            offerIds[i] = userOffers[_user][i];
        }
    }

    function getTotalOffersLength() external view returns (uint256) {
        return currentOfferId;
    }

    function getOffersLengthForListing(uint256 _id) external view returns (uint256) {
        return allListingOfferIds[_id].length;
    }

    function getOffersLengthForUser(address _user) external view returns (uint256) {
        return userOffers[_user].length;
    }

    function getOfferInfoByIndex(uint256 _offerId) external view returns (address _offerer, uint256 _offerAmount, uint256 _listingId, string memory _offerStatus) {
        _offerer = offerId[_offerId].offerer;
        _offerAmount = offerId[_offerId].offerAmount;
        _listingId = offerId[_offerId].listingId;
        if(offerId[_offerId].offerStatus == 1) {
            _offerStatus = 'active';
        } else if(offerId[_offerId].offerStatus == 2) {
            _offerStatus = 'outOffered';
        } else if(offerId[_offerId].offerStatus == 3) {
            _offerStatus = 'canceled';
        } else if(offerId[_offerId].offerStatus == 4) {
            _offerStatus = 'accepted';
        } else {
            _offerStatus = 'invalid OfferID';
        }
    }

    function getOfferStatus(uint256 _offerId) external view returns (string memory _offerStatus) {
        if(offerId[_offerId].offerStatus == 1) {
            _offerStatus = 'active';
        } else if(offerId[_offerId].offerStatus == 2) {
            _offerStatus = 'outoffer';
        } else if(offerId[_offerId].offerStatus == 3) {
            _offerStatus = 'canceled';
        } else if(offerId[_offerId].offerStatus == 4) {
            _offerStatus = 'accepted';
        } else {
            _offerStatus = 'invalid OfferID';
        }
    }

    function getAllActiveListings() external view returns (uint256[] memory _activeListings) {
        uint256 length = activeListingCount;
        _activeListings = new uint256[](length);
        uint256 z = 0;
        for(uint i = 1; i <= currentId; i++) {
            if(listingStatus(i) == 1) {
                _activeListings[z] = i;
                z++;
            } else {
                continue;
            }
        }
    }

    function getAllListings() external view returns (uint256[] memory listings, uint256[] memory status) {
        listings = new uint256[](currentId);
        status = new uint256[](currentId);
        for(uint i = 1; i < currentId; i++) {
            listings[i - 1] = i;
            status[i - 1] = listingStatus(i);
        }
    }

    function minListPrice() public view returns (uint256) {
        if(useManualMinListPrice) {
            return manualMinListPrice; 
        } else {
            address[] memory path = new address[](2);
            path[0] = address(TOPIA);
            path[1] = WETH;
            uint256 amountOut = 1 * 10**16;
            uint256[] memory amounts = pyeSwapRouter.getAmountsIn(1 * 10**16, path, 0);
            uint256 ethPerToken = (amountOut * 10**9) / amounts[0];
            return ethPerToken * minListPercent / 10000;
        }
    }

    /**
     * @notice Transfer ETH. If the ETH transfer fails, wrap the ETH and try send it as WETH.
     */
    function _safeTransferETHWithFallback(address to, uint256 amount) internal {
        if (!_safeTransferETH(to, amount)) {
            IWETH(WETH).deposit{ value: amount }();
            IERC20(WETH).transfer(to, amount);
        }
    }

    /**
     * @notice Transfer ETH and return the success status.
     * @dev This function only forwards 30,000 gas to the callee.
     */
    function _safeTransferETH(address to, uint256 value) internal returns (bool) {
        (bool success, ) = to.call{ value: value, gas: 30_000 }(new bytes(0));
        return success;
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}

