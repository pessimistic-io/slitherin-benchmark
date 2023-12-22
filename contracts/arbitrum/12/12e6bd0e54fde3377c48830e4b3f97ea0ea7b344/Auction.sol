// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import {Math} from "./Math.sol";
import {ERC20} from "./ERC20.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

struct Bidder {
    address _bidderAddress;
    uint256 _tokenAmount;
    uint256 _pricePerToken;
    uint256 _amountPaid;
}

struct Round {
    uint256 _roundTimestamp;
    uint256 _currentRound;
    Bidder _roundCurrentWinner;
}

error NoBid();
error LowBid();
error NotOwner();
error BidExists();
error AuctionEnded();
error InvalidStart();
error BidderIs0Address();
error ExceedsMaxPerRound();
error InsufficientBalance();

contract Auction {
    using Math for uint256;
    using SafeERC20 for IERC20;

    event BidderWinner(uint256 round_, Bidder bidder_);
    event Bidded(address bidder_, uint256 requestedAmount_, uint256 pricePerToken_);

    uint256 public constant MINIMUM_PRICE_PER_TOKEN = 1000;
    uint256 public constant MINIMUM_TOKEN_AMOUNT = 1 * 10 ** 15;
    uint256 public constant MAX_TOKENS_PER_ROUND = 1_000_000 * 10 ** 18;
    address public immutable USDC_ADDRESS = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    address public immutable CHAMELEON_ADDRESS = address(0x14BC09B277Eea6E14B5EEDD275D404FC07F0C4E4);

    uint256 private _claimedBids;
    address private immutable _owner;
    uint256 private constant _HOUR = 3600;

    bool public ended;
    Round public getRoundData;

    // Needed to update roundCurrentWinner when the {currentWinner} gives up before the round ends or a new round beggins.
    address[] private _roundBidders;
    mapping(address _bidder => Bidder _bidderData) public bidders;
    mapping(uint256 _roundId => Bidder _bidderWinner) public bidderWinner;

    constructor() {
        _owner = msg.sender;
        getRoundData._currentRound = 1;
        getRoundData._roundTimestamp = block.timestamp;
    }

    /* 
     * Bids in the current round. Triggers a new round if the timestamp is correspondent to the start of another round.
     *
     * Requirements:
     *
     * -> Auction must not have ended.
     * -> Bidder cannot have a placed bid. It must cancel it first.
     * -> {requestedAmount} <= {MAX_TOKENS_PER_ROUND}.
     * -> {pricePerToken} >= {MINIMUM_PRICE_PER_TOKEN}
     * -> {requestedAmount} >= {MINIMUM_TOKEN_AMOUNT}.
     * -> This contract Chameleon Token balance must be equal or bigger than the requested amount.
     *
     * Will trigger a new round if {now} > {roundTimestamp} + _HOUR,
     * but only after the current bidder has been taken in consideration, allowing an address to win a round if it bids in a round that has ended but there are no bidders.
     *
     */
    function bid(uint256 requestedAmount_, uint256 pricePerToken_) external returns (bool) {
        address bidder_ = msg.sender;
        _validateBid(bidder_, requestedAmount_, pricePerToken_);

        if (_isNewRound() && getRoundData._roundCurrentWinner._bidderAddress != address(0)) _triggerNewRound();

        uint256 amountToPay_ = _computePrice(requestedAmount_, pricePerToken_);
        SafeERC20.safeTransferFrom(IERC20(USDC_ADDRESS), bidder_, address(this), amountToPay_);
        _addBider(bidder_, requestedAmount_, pricePerToken_, amountToPay_);

        if (_isNewRound()) _triggerNewRound();

        emit Bidded(bidder_, requestedAmount_, pricePerToken_);
        return true;
    }

    /*
     * Cancels an address bid.
     *
     * Does not trigger a new round. Will update the new round winner.
     *
     * Requirements:
     *
     * -> Address must have a bid.
     *
     */
    function cancelBid() external returns (bool) {
        address sender = msg.sender;
        Bidder memory bidder = bidders[sender];

        if (bidder._bidderAddress == address(0)) {
            revert NoBid();
        }

        uint256 bidderAmount = bidder._amountPaid;

        delete bidders[sender];

        // Check if bidder was the winner and update the winner if it was.
        if (getRoundData._roundCurrentWinner._bidderAddress == sender) {
            Bidder memory emptyBidder;
            getRoundData._roundCurrentWinner = emptyBidder;
            _updateRoundCurrentWinner();
        }

        SafeERC20.safeTransfer(IERC20(USDC_ADDRESS), sender, bidderAmount);
        return true;
    }

    function _computePrice(uint256 requestedAmount_, uint256 pricePerToken_) private pure returns (uint256) {
        return requestedAmount_.mulDiv(pricePerToken_, 10 ** 18, Math.Rounding.Up);
    }

    function _addBider(address bidder_, uint256 requestedAmount_, uint256 pricePerToken_, uint256 amountPaid_)
        private
    {
        Bidder memory newBidder_ = Bidder(bidder_, requestedAmount_, pricePerToken_, amountPaid_);
        bidders[bidder_] = newBidder_;
        if (newBidder_._pricePerToken > getRoundData._roundCurrentWinner._pricePerToken) {
            getRoundData._roundCurrentWinner = newBidder_;
        }
        _roundBidders.push(bidder_);
    }

    /*
     * Checks if the placed bid is valid.
     *
     * Check bid() function to see the requirements.
     */
    function _validateBid(address bidder_, uint256 requestedAmount_, uint256 pricePerToken_) private view {
        if (ended) revert AuctionEnded();
        if (requestedAmount_ < MINIMUM_TOKEN_AMOUNT) revert LowBid();
        if (pricePerToken_ < MINIMUM_PRICE_PER_TOKEN) revert LowBid();
        if (bidders[bidder_]._bidderAddress != address(0)) revert BidExists();
        if (requestedAmount_ > MAX_TOKENS_PER_ROUND) {
            revert ExceedsMaxPerRound();
        }
        if (IERC20(CHAMELEON_ADDRESS).balanceOf(address(this)) < requestedAmount_) revert InsufficientBalance();
    }

    // Checks if it's time for a new round.
    function _isNewRound() private view returns (bool) {
        return block.timestamp > getRoundData._roundTimestamp + _HOUR && !ended;
    }

    /*
     * Triggers a new round, indexing the round winner of the previous round.
     * The winning address now has the option to claim the tokens of the winning bid.
     *
     * This function is only called by bid, when a new round starts, so all requirements have been checked.
     *
     */
    function _triggerNewRound() private {
        bidderWinner[getRoundData._currentRound] = getRoundData._roundCurrentWinner;
        // Update structures and variables.
        ++getRoundData._currentRound;
        Bidder memory emptyBidder_;
        getRoundData._roundCurrentWinner = emptyBidder_;
        getRoundData._roundTimestamp = block.timestamp;

        delete bidders[
            bidderWinner[getRoundData._currentRound - 1]._bidderAddress
        ];
        _updateRoundCurrentWinner();

        address winner = bidderWinner[getRoundData._currentRound - 1]._bidderAddress;
        uint256 amountToPay_ = bidderWinner[getRoundData._currentRound - 1]._tokenAmount;
        uint256 pricePerToken_ = bidderWinner[getRoundData._currentRound - 1]._pricePerToken;
        _processWinningTransfer(winner, amountToPay_, pricePerToken_);
        emit BidderWinner(getRoundData._currentRound - 1, bidderWinner[getRoundData._currentRound - 1]);
    }

    function _processWinningTransfer(address winner_, uint256 amountToPay_, uint256 pricePerToken_) private {
        IERC20 chameleonToken_ = IERC20(CHAMELEON_ADDRESS);
        uint256 auctionBalance_ = chameleonToken_.balanceOf(address(this));

        if (amountToPay_ > auctionBalance_) {
            uint256 toReturn_ = _computePrice(amountToPay_ - auctionBalance_, pricePerToken_);
            // Update data structure and end auction
            bidderWinner[getRoundData._currentRound - 1]._amountPaid -= toReturn_;
            ended = true;

            SafeERC20.safeTransfer(chameleonToken_, winner_, auctionBalance_);
            SafeERC20.safeTransfer(IERC20(USDC_ADDRESS), winner_, toReturn_);
        } else {
            SafeERC20.safeTransfer(chameleonToken_, winner_, amountToPay_);
        }
    }

    // Updates the current highest bidder.
    function _updateRoundCurrentWinner() private {
        address maxBidder_;
        uint256 _roundBiddersLength = _roundBidders.length;
        for (uint256 i; i < _roundBiddersLength;) {
            address bidder_ = _roundBidders[i];
            if (bidders[bidder_]._pricePerToken > getRoundData._roundCurrentWinner._pricePerToken) {
                maxBidder_ = bidder_;
            }
            unchecked {
                ++i;
            }
        }
        getRoundData._roundCurrentWinner = bidders[maxBidder_];
    }

    // In case _roundBidders gets too big.
    function cleanRoundBidders() external isOwner {
        uint256 counter;
        address[] memory haveBids;
        uint256 _biddersLength = _roundBidders.length;
        for (uint256 i; i < _biddersLength;) {
            address bidderAddress_ = _roundBidders[i];
            if (bidders[bidderAddress_]._bidderAddress != address(0)) {
                haveBids[counter] = bidderAddress_;
                unchecked {
                    ++counter;
                }
            }
            unchecked {
                ++i;
            }
        }
        _roundBidders = haveBids;
    }

    // Withraw all winning bids up to the current round, that haven't been withdrawn yet
    function withdrawWinnerBids() external isOwner returns (bool) {
        uint256 amountToClaim_;
        uint256 _numberRounds = getRoundData._currentRound;
        for (uint256 i = _claimedBids + 1; i < _numberRounds;) {
            amountToClaim_ += bidderWinner[i]._amountPaid;
            unchecked {
                ++i;
            }
        }
        _claimedBids = getRoundData._currentRound - 1;
        SafeERC20.safeTransfer(IERC20(USDC_ADDRESS), _owner, amountToClaim_);
        return true;
    }

    // Withdraws Chameleon Tokens from the vault.
    function withdrawTokens(uint256 amount) external isOwner returns (bool) {
        IERC20 chameleonToken = IERC20(CHAMELEON_ADDRESS);
        SafeERC20.safeTransfer(chameleonToken, _owner, amount);
        return true;
    }

    modifier isOwner() {
        if (msg.sender != _owner) {
            revert NotOwner();
        }
        _;
    }
}

