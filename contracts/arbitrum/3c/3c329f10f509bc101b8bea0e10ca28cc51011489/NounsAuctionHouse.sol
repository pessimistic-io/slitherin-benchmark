// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import { Pausable } from "./Pausable.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { Ownable } from "./Ownable.sol";
import { IERC20 } from "./IERC20.sol";
import { INounsAuctionHouse } from "./INounsAuctionHouse.sol";
import { INounsToken } from "./INounsToken.sol";
import { IWETH } from "./IWETH.sol";

contract NounsAuctionHouse is INounsAuctionHouse, Pausable, ReentrancyGuard, Ownable {
    // The address of the WETH contract
    address public weth;

    // The minimum amount of time left in an auction after a new bid is created
    uint256 public timeBuffer;

    // The minimum price accepted in an auction
    uint256 public reservePrice;

    // The minimum percentage difference between the last bid amount and the current bid
    uint8 public minBidIncrementPercentage;

    // The duration of a single auction
    uint256 public duration;

    // Auction Type -> Collection Address
    mapping(uint16 => address) public auctionedCollectionAddress;

    // The active auction
    // INounsAuctionHouse.Auction public auction;

    // Auction List
    mapping(uint256 => INounsAuctionHouse.Auction) public auctionList;

    uint256 public auctionIdTracker;
    uint16 public auctionTypeTracker;

    /**
     * @notice Initialize the auction house and base contracts,
     * populate configuration values, and pause the contract.
     * @dev This function can only be called once.
     */
    constructor (
        address _weth,
        uint256 _timeBuffer,
        uint256 _reservePrice,
        uint8 _minBidIncrementPercentage,
        uint256 _duration
    ) {
        weth = _weth;
        timeBuffer = _timeBuffer;
        reservePrice = _reservePrice;
        minBidIncrementPercentage = _minBidIncrementPercentage;
        duration = _duration;
    }

    /**
     * @notice Settle the current auction, mint a new Noun, and put it up for auction.
     */
    function settleCurrentAndCreateNewAuction(uint256 _auctionId, uint16 _auctionType) external nonReentrant whenNotPaused {
        _settleAuction(_auctionId);
        _createAuction(_auctionType);
    }

    /**
     * @notice Settle the current auction.
     * @dev This function can only be called when the contract is paused.
     */
    function settleAuction(uint256 _auctionId) external nonReentrant {
        _settleAuction(_auctionId);
    }

    function createAuction(uint16 _auctionType) external nonReentrant whenNotPaused onlyOwner {
        _createAuction(_auctionType);
    }

    /**
     * @notice Create a bid for a Noun, with a given amount.
     * @dev This contract only accepts payment in ETH.
     */
    function createBid(uint256 _auctionId) external payable override nonReentrant {
        INounsAuctionHouse.Auction memory _auction = auctionList[_auctionId];

        require(_auctionId < auctionIdTracker, 'Not available auction');
        require(block.timestamp < _auction.endTime, 'Auction expired');
        require(msg.value >= reservePrice, 'Must send at least reservePrice');
        require(
            msg.value >= _auction.amount + ((_auction.amount * minBidIncrementPercentage) / 100),
            'Must send more than last bid by minBidIncrementPercentage amount'
        );

        address payable lastBidder = _auction.bidder;

        // Refund the last bidder, if applicable
        if (lastBidder != address(0)) {
            _safeTransferETHWithFallback(lastBidder, _auction.amount);
        }

        auctionList[_auctionId].amount = msg.value;
        auctionList[_auctionId].bidder = payable(msg.sender);

        // Extend the auction if the bid was received within `timeBuffer` of the auction end time
        bool extended = _auction.endTime - block.timestamp < timeBuffer;
        if (extended) {
            auctionList[_auctionId].endTime = _auction.endTime = block.timestamp + timeBuffer;
        }

        emit AuctionBid(_auctionId, msg.sender, msg.value, extended);

        if (extended) {
            emit AuctionExtended(_auctionId, _auction.endTime);
        }
    }

    /**
     * @notice Pause the Nouns auction house.
     * @dev This function can only be called by the owner when the
     * contract is unpaused. While no new auctions can be started when paused,
     * anyone can settle an ongoing auction.
     */
    function pause() external override onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the Nouns auction house.
     * @dev This function can only be called by the owner when the
     * contract is paused. If required, this function will start a new auction.
     */
    function unpause() external override onlyOwner {
        _unpause();

        // if (auction.startTime == 0 || auction.settled) {
        //     _createAuction();
        // }
    }

    /**
     * @notice Set the auction time buffer.
     * @dev Only callable by the owner.
     */
    function setTimeBuffer(uint256 _timeBuffer) external override onlyOwner {
        timeBuffer = _timeBuffer;

        emit AuctionTimeBufferUpdated(_timeBuffer);
    }

    /**
     * @notice Set the auction reserve price.
     * @dev Only callable by the owner.
     */
    function setReservePrice(uint256 _reservePrice) external override onlyOwner {
        reservePrice = _reservePrice;

        emit AuctionReservePriceUpdated(_reservePrice);
    }

    /**
     * @notice Set the auction minimum bid increment percentage.
     * @dev Only callable by the owner.
     */
    function setMinBidIncrementPercentage(uint8 _minBidIncrementPercentage) external override onlyOwner {
        minBidIncrementPercentage = _minBidIncrementPercentage;

        emit AuctionMinBidIncrementPercentageUpdated(_minBidIncrementPercentage);
    }

    /**
     * @notice Create an auction.
     * @dev Store the auction details in the `auction` state variable and emit an AuctionCreated event.
     * If the mint reverts, the minter was updated without pausing this contract first. To remedy this,
     * catch the revert and pause this contract.
     */
    function _createAuction(uint16 _auctionType) internal {
        require(auctionedCollectionAddress[_auctionType] != address(0), "Collection doesn't exist");
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + duration;

        auctionList[auctionIdTracker] = Auction({
            amount: 0,
            startTime: startTime,
            endTime: endTime,
            bidder: payable(0),
            settled: false,
            auctionType: _auctionType// weapon or character....
        });

        ++auctionIdTracker;

        emit AuctionCreated(auctionIdTracker - 1, startTime, endTime);
    }

    function addNewAuctionType(address collection) external onlyOwner {
        require(collection != address(0), "Address 0");
        auctionedCollectionAddress[auctionTypeTracker] = collection;
        ++auctionTypeTracker;
    }

    function removeAuctionType(uint16 auctionType) external onlyOwner {
        auctionedCollectionAddress[auctionType] = address(0);
    }

    /**
     * @notice Settle an auction, finalizing the bid and paying out to the owner.
     * @dev If there are no bids, the Noun is burned.
     */
    function _settleAuction(uint256 _auctionId) internal {
        INounsAuctionHouse.Auction memory _auction = auctionList[_auctionId];

        require(_auction.startTime != 0, "Auction hasn't begun");
        require(!_auction.settled, 'Auction has already been settled');
        require(block.timestamp >= _auction.endTime, "Auction hasn't completed");

        auctionList[_auctionId].settled = true;

        if (_auction.bidder == address(0)) {
            // BURN MECHANISM
            uint256 tokenId = INounsToken(auctionedCollectionAddress[_auction.auctionType]).mint();
            INounsToken(auctionedCollectionAddress[_auction.auctionType]).burn(tokenId);

        } else {
            // TODO: Need to support the ERC1155 item.
            INounsToken(auctionedCollectionAddress[_auction.auctionType]).mintTo(_auction.bidder);
        }

        if (_auction.amount > 0) {
            _safeTransferETHWithFallback(owner(), _auction.amount);
        }

        emit AuctionSettled(_auctionId, _auction.bidder, _auction.amount);
    }

    /**
     * @notice Transfer ETH. If the ETH transfer fails, wrap the ETH and try send it as WETH.
     */
    function _safeTransferETHWithFallback(address to, uint256 amount) internal {
        if (!_safeTransferETH(to, amount)) {
            IWETH(weth).deposit{ value: amount }();
            IERC20(weth).transfer(to, amount);
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
}
