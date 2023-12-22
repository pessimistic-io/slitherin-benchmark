// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./SafeMathUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";

contract VelaDashOTCMarket is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function initialize() public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        feeBasisPoints = 3000; // 3%
        feeManager = msg.sender;
    }

    uint256 public feeBasisPoints;
    address public feeManager;
    uint256 internal constant BASIS_POINTS_DIVISOR = 100000;

    uint256 public lastOfferId;
    mapping(uint256 => OfferInfo) public offers;

    struct OfferInfo {
        uint256 bidAmount;
        uint256 bidAmount_original;
        IERC20Upgradeable bidAsset;
        uint256 takeAmount;
        IERC20Upgradeable takeAsset;
        address owner;
        uint64 timestamp;
    }

    modifier canBuy(uint256 id) {
        require(isActive(id), "Offer is not active");
        _;
    }

    modifier canCancel(uint256 id) {
        require(isActive(id), "Offer is not active");
        require(getOfferOwner(id) == msg.sender || owner() == msg.sender, "Only the owner can cancel");
        _;
    }

    // Make a new offer. Takes funds from the caller into market escrow.
    function _offer(
        IERC20Upgradeable bidAsset,
        uint256 bidAmount,
        IERC20Upgradeable takeAsset,
        uint256 takeAmount
    ) internal nonReentrant returns (uint256 id) {
        require(uint256(bidAmount) == bidAmount, "Pay amount too large");
        require(uint256(takeAmount) == takeAmount, "Buy amount too large");
        require(bidAmount > 0, "Pay amount must be greater than zero");
        require(address(bidAsset) != address(0), "Invalid pay token address");
        require(takeAmount > 0, "Buy amount must be greater than zero");
        require(address(takeAsset) != address(0), "Invalid buy token address");
        require(address(bidAsset) != address(takeAsset), "Tokens must be different");

        OfferInfo memory o;
        o.bidAmount = bidAmount;
        o.bidAmount_original = bidAmount;
        o.bidAsset = bidAsset;
        o.takeAmount = takeAmount;
        o.takeAsset = takeAsset;
        o.owner = msg.sender;
        o.timestamp = uint64(block.timestamp);
        id = _nextId();
        offers[id] = o;

        require(IERC20Upgradeable(bidAsset).transferFrom(msg.sender, address(this), bidAmount), "Transfer from owner failed");

        emit LogOfferId(id);

        emit LogOffer(
            bytes32(id),
            keccak256(abi.encodePacked(address(bidAsset), address(takeAsset))),
            msg.sender,
            bidAsset,
            takeAsset,
            uint256(bidAmount),
            uint256(takeAmount),
            uint64(block.timestamp)
        );
    }

    // Accept given `quantity` of an offer. Transfers funds from caller to
    // offer maker, and from market to caller.
    function _buy(uint256 id, uint256 quantity) internal canBuy(id) nonReentrant returns (bool) {
        OfferInfo memory o = offers[id];
        uint256 spend = quantity * o.takeAmount / o.bidAmount;

        // For backwards semantic compatibility.
        if (quantity == 0 || spend == 0 || quantity > o.bidAmount || spend > o.takeAmount) {
            return false;
        }

        offers[id].bidAmount = o.bidAmount - quantity;  // <- calculate what's left to sell
        offers[id].takeAmount = o.takeAmount - spend;   // <- calculate what's left to pay

        uint256 fee = _calculateFees(spend);

        if (fee != 0) {
            require(IERC20Upgradeable(o.takeAsset).transferFrom(msg.sender, feeManager, fee), "Transfer to feeManager failed");
        }
        
        require(IERC20Upgradeable(o.takeAsset).transferFrom(msg.sender, o.owner, spend - fee), "Transfer to owner failed");
        require(IERC20Upgradeable(o.bidAsset).transfer(msg.sender, quantity), "Transfer to buyer failed");

        emit LogOfferId(id);
        emit LogBuy(
            bytes32(id),
            keccak256(abi.encodePacked(o.bidAsset, o.takeAsset)),
            o.owner,
            o.bidAsset,
            o.takeAsset,
            msg.sender,
            uint256(quantity),
            uint256(spend - fee),
            uint64(block.timestamp)
        );
        emit LogTrade(quantity, address(o.bidAsset), spend, address(o.takeAsset));

        if (offers[id].bidAmount == 0) {
            delete offers[id];
        }

        return true;
    }

    function _calculateFees(uint256 amount) internal view returns (uint256) {
         if (feeBasisPoints == 0) {
            return 0;
        }

        return (amount * feeBasisPoints) / BASIS_POINTS_DIVISOR;
    }

    // Cancel an offer. Refunds offer maker.
    function _cancel(uint256 id) internal canCancel(id) nonReentrant returns (bool success) {
        // read-only offer. Modify an offer by directly accessing offers[id]
        OfferInfo memory o = offers[id];
        delete offers[id];

        require(IERC20Upgradeable(o.bidAsset).transfer(o.owner, o.bidAmount), "Transfer to owner failed");

        emit LogOfferId(id);
        emit LogCancel(
            bytes32(id),
            keccak256(abi.encodePacked(o.bidAsset, o.takeAsset)),
            o.owner,
            o.bidAsset,
            o.takeAsset,
            uint256(o.bidAmount),
            uint256(o.takeAmount),
            uint64(block.timestamp)
        );

        success = true;
    }

    function _nextId() internal returns (uint256) {
        lastOfferId++;
        return lastOfferId;
    }

    // ---- Public entrypoints ---- //

    // Offer has NOT been canceled by the user
    function isActive(uint256 id) public view returns (bool active) {
        return offers[id].timestamp > 0;
    }

    function getOfferOwner(uint256 id) public view returns (address owner) {
        return offers[id].owner;
    }

    function getOffer(
        uint256 id
    ) external view returns (uint64, address, IERC20Upgradeable, uint256, uint256, IERC20Upgradeable, uint256) {
        OfferInfo memory o = offers[id];
        return (o.timestamp, o.owner, o.bidAsset, o.bidAmount, o.bidAmount_original, o.takeAsset, o.takeAmount);
    }

    function getOfferIds() external view returns (uint256[] memory) {
        uint256 counter = 0;
        uint256 id;

        for (id = 1; id <= lastOfferId; ++id) {
            if (offers[id].timestamp > 0) counter++;
        }

        uint256[] memory offerIds = new uint256[](counter);
        counter = 0;

        for (id = 1; id <= lastOfferId; ++id) {
            if (offers[id].timestamp > 0) {
                offerIds[counter] = id;
                counter++;
            }
        }

        return offerIds;
    }

    function offer(
        IERC20Upgradeable bidAsset,
        uint256 bidAmount,
        IERC20Upgradeable takeAsset,
        uint256 takeAmount
    ) external returns (uint256 id) {
        return _offer(bidAsset, bidAmount, takeAsset, takeAmount);
    }

    function buy(uint256 id, uint256 maxTakeAmount) external {
        require(_buy(id, uint256(maxTakeAmount)), "Buy failed");
    }

    function cancel(uint256 id) external {
        require(_cancel(id), "Cancel failed");
    }

    // ---- admin functions ---- //

    function setFeeBasisPoints(uint256 _feeBasisPoints) external onlyOwner {
        require(_feeBasisPoints <= BASIS_POINTS_DIVISOR, "Above max");
        feeBasisPoints = _feeBasisPoints;
        emit SetFeeBasisPoints(_feeBasisPoints);
    }

    function setFeeManager(address _feeManager) external onlyOwner {
        feeManager = _feeManager;
        emit SetFeeManager(_feeManager);
    }

    event SetFeeBasisPoints(uint256 feeBasisPoints);

    event SetFeeManager(address indexed feeManager);

    event LogOfferId(uint indexed id);

    event LogTrade(uint bidAmount, address indexed bidAsset, uint takeAmount, address indexed takeAsset);

    event LogOffer(
        bytes32 indexed id,
        bytes32 indexed pair,
        address indexed maker,
        IERC20Upgradeable bidAsset,
        IERC20Upgradeable takeAsset,
        uint256 bidAmount,
        uint256 takeAmount,
        uint64 timestamp
    );

    event LogBuy(
        bytes32 id,
        bytes32 indexed pair,
        address indexed maker,
        IERC20Upgradeable bidAsset,
        IERC20Upgradeable takeAsset,
        address indexed taker,
        uint256 takeAmt,
        uint256 giveAmt,
        uint64 timestamp
    );

    event LogCancel(
        bytes32 indexed id,
        bytes32 indexed pair,
        address indexed maker,
        IERC20Upgradeable bidAsset,
        IERC20Upgradeable takeAsset,
        uint256 bidAmount,
        uint256 takeAmount,
        uint64 timestamp
    );
}

