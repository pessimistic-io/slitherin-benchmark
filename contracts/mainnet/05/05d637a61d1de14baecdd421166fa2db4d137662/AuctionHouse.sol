// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Ownable} from "./Ownable.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {SafeMath} from "./SafeMath.sol";
import {Math} from "./Math.sol";
import {Counters} from "./Counters.sol";
import {ERC1155Holder} from "./ERC1155Holder.sol";
import {ERC721Holder} from "./ERC721Holder.sol";
import {IERC165} from "./IERC165.sol";
import {IERC721} from "./IERC721.sol";
import {IERC1155} from "./IERC1155.sol";
import {Auction, Asset, AuctionStatus, AuctionType} from "./AuctionStructs.sol";
import {IWhitelistRegistry} from "./IWhitelistRegistry.sol";

contract AuctionHouse is Ownable, ReentrancyGuard, ERC721Holder, ERC1155Holder {
    using SafeMath for uint256;
    using Math for uint256;
    using Counters for Counters.Counter;
    // ERC721 interfaceID
    bytes4 public constant INTERFACE_ID_ERC721 = 0x80ac58cd;
    // ERC1155 interfaceID
    bytes4 public constant INTERFACE_ID_ERC1155 = 0xd9b67a26;

    address public protocolFeeRecipient;
    uint256 public protocolFee;
    uint256 public penaltyFee;
    uint256 public maxLotSize;
    bool public allowListings = false;
    bool public isBeta = true;

    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => Asset[]) public assets;

    Counters.Counter public totalAuctionCount;
    Counters.Counter public totalBidCount;

    address private whitelistRegistry;

    event AuctionCreated(uint256 indexed auctionId, address indexed seller);
    event AuctionCancelled(uint256 indexed auctionId);
    event AuctionReverted(uint256 indexed auctionId);
    event AuctionSettled(
        uint256 indexed auctionId,
        address indexed seller,
        address indexed buyer,
        uint256 price
    );
    event AuctionUpdated(uint256 indexed auctionId);
    event BidCreated(
        uint256 indexed auctionId,
        address indexed bidder,
        address indexed seller,
        uint256 price,
        bool reserveMet
    );

    error InvalidBid();

    modifier openAuction(uint256 auctionId) {
        require(
            auctions[auctionId].status == AuctionStatus.ACTIVE,
            "Auction is not open"
        );
        _;
    }

    modifier nonExpiredAuction(uint256 auctionId) {
        require(
            auctions[auctionId].endDate >= block.timestamp,
            "Auction already expired"
        );
        _;
    }

    modifier expiredAuction(uint256 auctionId) {
        require(
            auctions[auctionId].endDate < block.timestamp,
            "Auction has not expired yet"
        );
        _;
    }

    modifier onlySeller(uint256 auctionId) {
        require(msg.sender == auctions[auctionId].seller, "Not seller");
        _;
    }

    modifier notSeller(uint256 auctionId) {
        require(
            msg.sender != auctions[auctionId].seller,
            "Cannot be called by seller"
        );
        _;
    }

    modifier nonContract() {
        require(msg.sender == tx.origin, "Cannot be called by contract");
        _;
    }

    modifier canList() {
        require(
            !isBeta ||
                IWhitelistRegistry(whitelistRegistry).checkWhitelistStatus(
                    msg.sender
                ) ==
                true,
            "Not whitelisted"
        );
        _;
    }

    constructor(
        address _protocolFeeRecipient,
        address _whitelistRegistry,
        uint256 _protocolFee,
        uint256 _penaltyFee,
        uint256 _maxLotSize
    ) {
        protocolFeeRecipient = _protocolFeeRecipient;
        whitelistRegistry = _whitelistRegistry;
        protocolFee = _protocolFee;
        penaltyFee = _penaltyFee;
        maxLotSize = _maxLotSize;
    }

    /**
     * @notice Creates an auction
     * @dev client should group all ERC1155 with the same ids in one asset struct and update qty as needed
     * @param _assets assets to include in the auction lot (tokenAddress, tokenId, qty)
     * @param _startingPrice starting auction price. First bid must be greater than this value
     * @param _reservePrice lowest price seller is willing to sell at.
     * @param _startDate scheduled startDate. To start immediately set a value that is less than or equal to the current timestamp
     * @param _endDate scheduled endDate. Must be greater than the startDate and the current block timestamp
     */
    function createAuction(
        Asset[] calldata _assets,
        uint256 _startingPrice,
        uint256 _reservePrice,
        uint256 _minBidThreshold,
        uint256 _startDate,
        uint256 _endDate,
        bool _isExtendedType
    ) public canList nonContract returns (uint256 auctionId) {
        require(
            _endDate > block.timestamp,
            "Auction end date cannot be set in the past"
        );
        require(_endDate > _startDate, "Start date greater than end date");
        require(allowListings, "Auction creation paused");
        require(_assets.length <= maxLotSize, "Max lot size exceeded");
        require(_assets.length >= 1, "Auction must containt at least 1 asset");
        totalAuctionCount.increment();
        auctionId = totalAuctionCount.current();

        for (uint256 i; i < _assets.length; i++) {
            Asset calldata targetAsset = _assets[i];
            Asset memory newAsset = Asset(
                targetAsset.tokenAddress,
                targetAsset.tokenId,
                targetAsset.qty
            );
            assets[auctionId].push(newAsset);
        }

        auctions[auctionId] = Auction(
            auctionId,
            _startingPrice,
            _reservePrice,
            _minBidThreshold,
            msg.sender,
            Math.max(_startDate, block.timestamp),
            _endDate,
            _startingPrice,
            address(0),
            AuctionStatus.ACTIVE,
            _isExtendedType ? AuctionType.EXTENDED : AuctionType.ABSOLUTE
        );
        _transferAssets(_assets, msg.sender, address(this));
        emit AuctionCreated(auctionId, msg.sender);
        return auctionId;
    }

    /**
     * @notice Creates bid tied to a specific auction. Bid amount will be the value of msg.value
     * @param _auctionId auctionId
     * @return bidId ID of the newly created bid
     */
    function createBid(
        uint256 _auctionId
    )
        public
        payable
        nonReentrant
        nonContract
        openAuction(_auctionId)
        notSeller(_auctionId)
        nonExpiredAuction(_auctionId)
        returns (uint256 bidId)
    {
        Auction storage auction = auctions[_auctionId];

        // opening bid check
        if (auction.topBidder == address(0)) {
            if (msg.value < auction.startingPrice) {
                revert InvalidBid();
            }
        } else {
            // non-opening bid check
            if (auction.minBidThreshold == 0 && msg.value <= auction.topBid) {
                revert InvalidBid();
            } else if (
                auction.minBidThreshold > 0 &&
                auction.topBid.add(auction.minBidThreshold) > msg.value
            ) {
                revert InvalidBid();
            }
        }

        bool reserveMet = msg.value > auction.reservePrice;

        if (auction.topBidder != address(0)) {
            payable(auction.topBidder).transfer(auction.topBid);
        }

        auction.topBid = msg.value;
        auction.topBidder = msg.sender;

        if (auction.auctionType == AuctionType.EXTENDED)
            _extendAuction(_auctionId);

        emit BidCreated(
            _auctionId,
            msg.sender,
            auction.seller,
            msg.value,
            reserveMet
        );
        return bidId;
    }

    function increaseBid(uint256 _auctionId) public payable {
        Auction storage auction = auctions[_auctionId];

        require(msg.sender == auction.topBidder, "Not top bidder");
        require(msg.value > 0, "New bid must be greater than preivous");
        require(
            auction.status == AuctionStatus.ACTIVE &&
                auction.endDate >= block.timestamp,
            "Auction is not active"
        );
        if (msg.value == 0 || msg.value < auction.minBidThreshold) {
            revert InvalidBid();
        }
        auction.topBid = auction.topBid.add(msg.value);
        if (auction.auctionType == AuctionType.EXTENDED)
            _extendAuction(_auctionId);

        emit BidCreated(
            _auctionId,
            msg.sender,
            auction.seller,
            auction.topBid,
            (auction.topBid > auction.reservePrice)
        );
    }

    /**
     * @notice Cancels an auction and pays out penalty (if applicable)
     * @dev Only callable by seller. If bid exists, seller will need to pay a penalty which will go to the curent top bidder
     * @param _auctionId ID of the auction to cancel
     */
    function cancelAuction(
        uint256 _auctionId
    )
        public
        payable
        nonReentrant
        nonExpiredAuction(_auctionId)
        openAuction(_auctionId)
        onlySeller(_auctionId)
    {
        Auction storage auction = auctions[_auctionId];
        Asset[] memory _assets = assets[_auctionId];

        uint256 penalty = _calculatePenaltyFees(auction.topBid);

        if (auction.topBidder != address(0) && auction.topBid > 0) {
            require(msg.value >= penalty, "Incorrect penalty fee");
            payable(auction.topBidder).transfer(penalty.add(auction.topBid));
            if (msg.value.sub(penalty) > 0) {
                payable(msg.sender).transfer(msg.value.sub(penalty));
            }
        }

        auction.status = AuctionStatus.CANCELLED;
        auction.endDate = block.timestamp;
        _transferAssets(_assets, address(this), auction.seller);
        emit AuctionCancelled(_auctionId);
    }

    /**
     * @notice For seller to change the reserve price.
     * @dev Only callable by seller. New reserve price must be lower than previous reserve.
     * @param _auctionId ID of the auction to change reserve price for
     * @param _reservePrice new reserve price
     */
    function changeReservePrice(
        uint256 _auctionId,
        uint256 _reservePrice
    ) public onlySeller(_auctionId) openAuction(_auctionId) {
        Auction storage auction = auctions[_auctionId];
        require(
            _reservePrice < auction.reservePrice,
            "New reserve price too high"
        );
        auction.reservePrice = _reservePrice;
        emit AuctionUpdated(_auctionId);
    }

    /**
     * @notice Callable by anyone to settle auctions
     * @dev This function is used as both redeem and claim. Function handles all necessary payouts and transfers
     * @param _auctionId ID of the auction to settle
     */
    function settleAuction(
        uint256 _auctionId
    )
        public
        payable
        nonReentrant
        openAuction(_auctionId)
        expiredAuction(_auctionId)
    {
        Auction storage auction = auctions[_auctionId];

        if (auction.topBidder != address(0)) {
            if (auction.topBid >= auction.reservePrice) {
                uint256 protocolFeeValue = _calculateProtocolFees(
                    auction.topBid
                );
                payable(protocolFeeRecipient).transfer(protocolFeeValue);
                payable(auction.seller).transfer(
                    auction.topBid.sub(protocolFeeValue)
                );
                _transferAuctionAssets(
                    _auctionId,
                    address(this),
                    auction.topBidder
                );
            } else {
                // return funds to top bidder;
                payable(auction.topBidder).transfer(auction.topBid);
                // return assets to seller;
                _transferAssets(
                    assets[_auctionId],
                    address(this),
                    auction.seller
                );
            }
        } else {
            // return assets to seller
            _transferAuctionAssets(_auctionId, address(this), auction.seller);
        }

        auction.status = AuctionStatus.SETTLED;
        emit AuctionSettled(
            _auctionId,
            auction.seller,
            auction.topBidder,
            auction.topBid
        );
    }

    /**
     * @dev Internal function to handle bulk transfer of ERC721 and ERC1155 assets
     * @param _auctionId ID of the auction assets are tied to
     * @param _from address where the assets are currently held (seller or this contract)
     * @param _to address where assets should be sent to (seller, buyer, or this contract)
     */
    function _transferAuctionAssets(
        uint256 _auctionId,
        address _from,
        address _to
    ) internal {
        Asset[] memory _assets = assets[_auctionId];
        _transferAssets(_assets, _from, _to);
    }

    function _transferAssets(
        Asset[] memory _assets,
        address _from,
        address _to
    ) internal {
        uint256 numAssets = _assets.length;
        for (uint256 i; i < numAssets; i++) {
            Asset memory _asset = _assets[i];
            if (
                IERC165(_asset.tokenAddress).supportsInterface(
                    INTERFACE_ID_ERC1155
                )
            ) {
                IERC1155(_asset.tokenAddress).safeTransferFrom(
                    _from,
                    _to,
                    _asset.tokenId,
                    _asset.qty,
                    ""
                );
            } else if (
                IERC165(_asset.tokenAddress).supportsInterface(
                    INTERFACE_ID_ERC721
                )
            ) {
                IERC721(_asset.tokenAddress).safeTransferFrom(
                    _from,
                    _to,
                    _asset.tokenId
                );
            }
        }
    }

    function _calculateProtocolFees(
        uint256 amount
    ) internal view returns (uint256) {
        return ((protocolFee.mul(amount)).div(10000));
    }

    function _calculatePenaltyFees(
        uint256 amount
    ) internal view returns (uint256) {
        return ((penaltyFee.mul(amount)).div(10000));
    }

    function _extendAuction(uint256 _auctionId) internal {
        uint256 newEndDate = block.timestamp.add(5 minutes);
        auctions[_auctionId].endDate = Math.max(
            newEndDate,
            auctions[_auctionId].endDate
        );
    }

    /**
     * ============================ View functions ==========================
     */

    function getAuction(
        uint256 _auctionId
    ) public view returns (Auction memory) {
        Auction memory auction = auctions[_auctionId];
        require(
            _auctionId > 0 && auction.id == _auctionId,
            "Auction does not exist"
        );
        return auction;
    }

    function getHighestBid(
        uint256 _auctionId
    ) public view returns (uint256 bid, address bidder) {
        Auction memory auction = getAuction(_auctionId);
        require(_auctionId > 0 && auction.id != 0, "Auction does not exist");
        return (auction.topBid, auction.topBidder);
    }

    function getAuctionAssets(
        uint256 _auctionId
    ) public view returns (Asset[] memory) {
        Auction memory auction = getAuction(_auctionId);
        require(
            _auctionId > 0 && auction.id == _auctionId,
            "Auction does not exist"
        );
        return assets[_auctionId];
    }

    /**
     * ============================ Admin only functions ==========================
     */

    /**
     * @dev updates fee recipient address
     * @param _protocolFeeRecipient new few recipient address
     */
    function updateProtocolFeeRecipient(
        address _protocolFeeRecipient
    ) external onlyOwner {
        require(_protocolFeeRecipient != address(0), "Cannot be null address");
        protocolFeeRecipient = (_protocolFeeRecipient);
    }

    /**
     * @dev updates platform fee for settled auctions
     * @param _protocolFee percentage of fee 200 = 2%
     */
    function updateProtocolFee(uint256 _protocolFee) external onlyOwner {
        protocolFee = _protocolFee;
    }

    /**
     * @dev updates penalty fee for canceled auctions
     * @param _penaltyFee 200 = 2%
     */
    function updatePenaltyFee(uint256 _penaltyFee) external onlyOwner {
        penaltyFee = _penaltyFee;
    }

    /**
     * @dev toggles ability for auction creation
     * @param _allowListings if set to false nobody will be able to create auctions
     */

    function toggleAllowListings(bool _allowListings) external onlyOwner {
        allowListings = _allowListings;
    }

    /**
     * @dev flips beta mode for auction creation
     * @param _beta if set to to true only wallets listed in the wallet registry can create auctions
     */

    function toggleBeta(bool _beta) external onlyOwner {
        isBeta = _beta;
    }

    /**
     * @notice updates the maxLotSize
     * @dev this should be set low enough to ensure settlement and transfers of all assets stay well below the block limit
     * @param _maxLotSize max number of individual assets allowed to be included in an auction
     */
    function updateMaxLotSize(uint256 _maxLotSize) external onlyOwner {
        maxLotSize = _maxLotSize;
    }

    /**
     * @notice updates the whitelist registry contract address pointer
     * @param _registry address of whitelist registry contract
     */
    function updateWhitelistRegistry(address _registry) external onlyOwner {
        whitelistRegistry = _registry;
    }

    /**
     * @notice Reverts auction and returns bid funds to bidder and assets to seller.
     * @dev may be removed in the future. This should only be used in the rare instances where seller is intending to do something malicous or misleading
     * Example: Asset getting flagged by Opensea during the auction when bidders were expecting an unmarked asset.
     * @param _auctionId ID of auction
     */
    function revertAuction(
        uint256 _auctionId
    ) external onlyOwner nonExpiredAuction(_auctionId) openAuction(_auctionId) {
        Auction storage auction = auctions[_auctionId];
        if (auction.topBidder != address(0) && auction.topBid > 0) {
            payable(auction.topBidder).transfer(auction.topBid);
        }
        auction.status = AuctionStatus.CANCELLED;
        auction.endDate = block.timestamp;
        _transferAuctionAssets(_auctionId, address(this), auction.seller);
        emit AuctionReverted(_auctionId);
    }
}

