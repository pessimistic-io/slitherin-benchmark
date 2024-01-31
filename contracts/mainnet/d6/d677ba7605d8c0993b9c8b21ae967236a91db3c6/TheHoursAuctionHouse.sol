// SPDX-License-Identifier: GPL-3.0

/// @title The Hours AuctionHouse
/// @author Lawrence X Rogers
// LICENSE
// TheHoursAuctionHouse.sol is a modified version of the Nouns DAO Auction House
// https://github.com/NounsDAO/Nouns-monorepo/blob/master/packages/nouns-contracts/contracts/NounsAuctionHouse.sol
// which is a modified version of Zora's AuctionHouse.sol:
// https://github.com/ourzora/auction-house/blob/54a12ec1a6cf562e49f0a4917990474b11350a2d/contracts/AuctionHouse.sol
//
// NounsAuctionHouse.sol source code Copyright Nons DAO licensed under the GPL-3.0 license.
// AuctionHouse.sol source code Copyright Zora licensed under the GPL-3.0 license.

pragma solidity ^0.8.19;

import {Pausable} from "./Pausable.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Ownable} from "./Ownable.sol";
import {IERC20} from "./IERC20.sol";
import {MerkleProofLib} from "./MerkleProofLib.sol";
import {ITheHoursAuctionHouse} from "./ITheHoursAuctionHouse.sol";
import {ITheHours} from "./ITheHours.sol";
import "./AutomationCompatible.sol";
import "./console.sol";

contract TheHoursAuctionHouse is
    ITheHoursAuctionHouse,
    Pausable,
    ReentrancyGuard,
    Ownable,
    AutomationCompatibleInterface
{
    // The Jacksons ERC721 token contract
    ITheHours public immutable theHours;

    // The minimum amount of time left in an auction after a new bid is created
    uint256 public immutable timeBuffer;

    // The minimum price accepted in an auction
    uint256 public immutable reservePrice;

    // The minimum percentage difference between the last bid amount and the current bid
    uint8 public immutable minBidIncrementPercentage;

    // The duration of a single auction
    uint256 public immutable duration;

    // The active auction
    ITheHoursAuctionHouse.Auction public auction;

    // The merkle root for Jackson allowlist
    bytes32 public immutable allowlistMerkleRoot;

    constructor(
        ITheHours _theHours,
        uint256 _timeBuffer,
        uint256 _reservePrice,
        uint8 _minBidIncrementPercentage,
        uint256 _duration,
        bytes32 _allowlistMerkleRoot
    ) {
        _pause();

        theHours = _theHours;
        timeBuffer = _timeBuffer;
        reservePrice = _reservePrice;
        minBidIncrementPercentage = _minBidIncrementPercentage;
        duration = _duration;
        allowlistMerkleRoot = _allowlistMerkleRoot;
    }

    /**
     * @notice Settle the current auction, minting the Jackson, and create a new auction
     */
    function settleCurrentAndCreateNewAuction()
        public
        override
        nonReentrant
        whenNotPaused
    {
        _settleAuction();
        _createAuction();
    }

    /**
     * @notice Settle the current auction.
     * @dev This function can only be called when the contract is paused.
     */
    function settleAuction() external override whenPaused nonReentrant {
        _settleAuction();
    }

    /**
     * @notice Create a bid for a Jackson, with a given amount. The user can provide a proof for the allowlist
     * @dev This contract only accepts payment in ETH.
     */
    function createBid(
        uint256 hourId,
        bytes32 mintDetails,
        bool shouldCheckAllowlist,
        bytes32[] calldata proof
    ) external payable nonReentrant {
        ITheHoursAuctionHouse.Auction memory _auction = auction;

        if (shouldCheckAllowlist) {
            require(
                MerkleProofLib.verify(
                    proof,
                    allowlistMerkleRoot,
                    keccak256(abi.encodePacked(msg.sender))
                ),
                "Not in allowlist"
            );
            require(theHours.validateBid(mintDetails, true), "Invalid Bid");
        } else {
            require(theHours.validateBid(mintDetails, false), "Invalid Bid");
        }
        require(_auction.hourId == hourId, "Token not up for auction");
        require(block.timestamp < _auction.endTime, "Auction expired");
        require(msg.value >= reservePrice, "Must send at least reservePrice");
        require(
            msg.value >=
                _auction.amount +
                    ((_auction.amount * minBidIncrementPercentage) / 100),
            "Must send more than last bid by minBidIncrementPercentage amount"
        );

        address payable lastBidder = _auction.bidder;

        // Refund the last bidder, if applicable
        if (lastBidder != address(0)) {
            bool success = _safeTransferETH(lastBidder, _auction.amount);
            require(success);
        }

        auction.amount = msg.value;
        auction.bidder = payable(msg.sender);
        auction.mintDetails = mintDetails;

        // Extend the auction if the bid was received within `timeBuffer` of the auction end time
        bool extended = _auction.endTime - block.timestamp < timeBuffer;
        if (extended) {
            auction.endTime = _auction.endTime = block.timestamp + timeBuffer;
        }

        emit AuctionBid(
            _auction.hourId,
            msg.sender,
            msg.value,
            extended,
            mintDetails
        );

        if (extended) {
            emit AuctionExtended(_auction.hourId, _auction.endTime);
        }
    }

    /**
     * @notice Pause TheHours Auction House.
     * @dev This function can only be called by the owner when the
     * contract is unpaused. While no new auctions can be started when paused,
     * anyone can settle an ongoing auction.
     */
    function pause() external override onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the TheHours auction house.
     * @dev This function can only be called by the owner when the
     * contract is paused. If required, this function will start a new auction.
     */
    function unpause() external override onlyOwner {
        _unpause();

        if (auction.startTime == 0 || auction.settled) {
            _createAuction();
        }
    }

    /**
     * @notice Create an auction.
     * @dev Store the auction details in the `auction` state variable and emit an AuctionCreated event.
     */
    function _createAuction() internal {
        if (theHours.finished()) {
            _pause();
            return;
        }

        uint256 nextHourId = theHours.tokenCounter();
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + duration;

        auction = Auction({
            hourId: nextHourId,
            amount: 0,
            startTime: startTime,
            endTime: endTime,
            bidder: payable(owner()),// if no bid is placed, the token will get minted to the owner
            settled: false,
            mintDetails: 0
        });

        emit AuctionCreated(nextHourId, startTime, endTime);
    }

    /**
     * @notice Settle an auction, finalizing the bid and paying out to the owner.
     * @dev If there are no bids, the token is burned.
     */
    function _settleAuction() internal {
        ITheHoursAuctionHouse.Auction memory _auction = auction;

        require(_auction.startTime != 0, "Auction hasn't begun");
        require(!_auction.settled, "Auction has already been settled");
        require(
            block.timestamp >= _auction.endTime,
            "Auction hasn't completed"
        );

        auction.settled = true;

        theHours.mint(auction.mintDetails, _auction.bidder);

        emit AuctionSettled(
            _auction.hourId,
            _auction.bidder,
            _auction.amount,
            _auction.mintDetails
        );
    }

    /**
     * @notice Transfer ETH and return the success status.
     * @dev This function only forwards 30,000 gas to the callee.
     */
    function _safeTransferETH(address to, uint256 value)
        internal
        returns (bool)
    {
        (bool success, ) = to.call{value: value, gas: 30_000}(new bytes(0));
        return success;
    }

    function withdraw(address _to) public onlyOwner {
        _safeTransferETH(_to, address(this).balance);
    }

    function checkUpkeep(
        bytes calldata
    ) external override view returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = !paused() && block.timestamp >= auction.endTime;
        performData = abi.encode(true);
    }

    function performUpkeep(bytes calldata) external override {
        if (!paused() && block.timestamp >= auction.endTime && !theHours.finished()) {
            settleCurrentAndCreateNewAuction();
        }
    }
}

