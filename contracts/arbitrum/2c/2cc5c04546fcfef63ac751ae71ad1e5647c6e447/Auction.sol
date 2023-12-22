// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {IPriceOracle} from "./IARBRegistrarController.sol";
import {Ownable} from "./Ownable.sol";
import {StringUtils} from "./StringUtils.sol";
import {BaseRegistrarImplementation} from "./BaseRegistrarImplementation.sol";

error InvalidLabel(string label);
error NotEnoughQuota();
error BidAmountTooLow(uint minBidAmount);
error AuctionHardDeadlinePassed();
error AuctionNotEnded();
error AuctionEnded();
error AuctionNotStarted();
error AuctionStarted();
error AuctionWinnerCannotWithdraw();
error CannotWithdrawZeroAmount();
error DomainNotAvailable(string label);

contract Auction is Ownable {
    using StringUtils for *;

    uint256 public constant MIN_REGISTRATION_DURATION = 365 days;

    // TokenAuctionStatus stores the state of an auction.
    struct TokenAuctionStatus {
        // the label string.
        string label;
        // the current highest bidder.
        address winner;
        // current endTime.
        uint endTime;
        // the number of amount bidded by users, when withdraw
        // the value will be reset to 0.
        mapping(address => uint) userFunds;
    }

    // UserStatus stores user's available quota and enumerable bids.
    struct UserStatus {
        // user address to the available quota the user has for bidding on new domains.
        uint8 quota;
        // list tokenIDs that he has bidded.
        uint256[] bids;
        // map user to the tokenIDs that he has bidded.
        mapping(uint256 => bool) bided;
    }

    // pair of amount and tokenID.
    struct TopBid {
        uint256 tokenID;
        uint256 bid;
    }

    // pair of amount and label.
    struct TopBidView {
        string label;
        uint256 bid;
    }

    struct UserBidsView {
        string label;
        uint256 tokenID;
        address winner;
        uint256 highestBid;
        uint256 userBid;
    }

    // deps
    IPriceOracle public immutable prices;

    // static
    // TBD: arbitrum time
    // https://github.com/OffchainLabs/arbitrum/blob/master/docs/Time_in_Arbitrum.md
    uint public immutable startTime;
    uint public immutable initialEndTime;
    uint public immutable hardEndTime;
    uint public immutable extendDuration; //in second
    BaseRegistrarImplementation immutable base;

    ////// state
    // map user address to his auction status.
    mapping(address => UserStatus) public userStatus;
    //// map token ID to its auction status
    mapping(uint256 => TokenAuctionStatus) public auctionStatus;
    // Top ten bidded domains.
    TopBid[10] public topBids;
    // The total amount that the auction contract owner can withdraw.
    // Withdraw can only happen after hardEndTime and the value will be reset to 0, after withdraw.
    uint256 public ownerCanWithdraw;

    event Bid(uint tokenID, string label, address bidder, uint bid);

    constructor(
        BaseRegistrarImplementation _base,
        IPriceOracle _prices,
        uint _startTime,
        uint _initialEndTime,
        uint _hardEndTime,
        uint _extendDuration
    ) {
        require(_startTime < _initialEndTime);
        require(_initialEndTime < _hardEndTime);
        require(_startTime > block.timestamp);
        require(_extendDuration > 0);

        base = _base;
        prices = _prices;
        startTime = _startTime;
        initialEndTime = _initialEndTime;
        hardEndTime = _hardEndTime;
        extendDuration = _extendDuration;
    }
    
    // place a bid on @p label, total bid amount will be aggregated, returns the new bid value.
    function placeBid(
        string calldata label
    ) public payable onlyAfterStart onlyBeforeHardEnd returns (uint) {
        // reject payments of 0 ETH
        if (msg.value <= 0) {
            revert BidAmountTooLow(1);
        }

        uint256 tokenID = uint256(keccak256(bytes(label)));

        // consume quota
        _consumeQuota(msg.sender, tokenID);

        // verify label and initialize auction status if this is the first bid.
        _initAuctionStatus(tokenID, label);
        TokenAuctionStatus storage status = auctionStatus[tokenID];

        // per-label endtime check
        if (block.timestamp > status.endTime) {
            revert AuctionEnded();
        }

        // verify amount and update auction status
        uint newBid = status.userFunds[msg.sender] + msg.value;
        uint minBid = nextBidFloorPrice(tokenID, label);
        if (newBid < minBid) {
            revert BidAmountTooLow(minBid);
        }
        address prevWinner = status.winner;
        uint prevHighestBid = status.userFunds[prevWinner];
        // does not matter if new winner is the same or not.
        status.winner = msg.sender;
        status.userFunds[msg.sender] = newBid;
        ownerCanWithdraw += (newBid - prevHighestBid);

        // extend end time if necessary, but do not exceed hardEndTime.
        if (status.endTime - block.timestamp <= extendDuration) {
            status.endTime = block.timestamp + extendDuration;
            if (status.endTime > hardEndTime) {
                status.endTime = hardEndTime; // probably not necessary but not bad to keep.
            }
        }

        // update top ten bid
        _updateTopBids(tokenID, newBid);
        emit Bid(tokenID, label, msg.sender, newBid);
        return newBid;
    }

    function available(string calldata name) public view returns (bool) {
        bytes32 label = keccak256(bytes(name));
        return base.available(uint256(label));
    }

    function _updateTopBids(uint256 tokenID, uint256 newBid) private {
        // rank0 to rank9 will be used.
        uint8 rank = 10;
        // deduplication check
        bool update = false;
        uint8 endIndex = 9;
        for (; rank > 0; rank--) {
            // optimization: most bids won't make it to top 10.
            if (newBid < topBids[rank - 1].bid) {
                break;
            }
            if (!update && topBids[rank - 1].tokenID == tokenID) {
                update = true;
                endIndex = rank - 1;
            }
        }

        if (rank < 10) {
            for (uint8 j = endIndex; j > rank; j--) {
                topBids[j] = topBids[j - 1];
            }
            topBids[rank].tokenID = tokenID;
            topBids[rank].bid = newBid;
        }
    }

    // withdraw fund bidded on @p label, if not the winner.
    function withdraw(string calldata label) public returns (uint) {
        uint256 tokenID = uint256(keccak256(bytes(label)));
        TokenAuctionStatus storage status = auctionStatus[tokenID];
        if (status.winner == msg.sender) {
            revert AuctionWinnerCannotWithdraw();
        }
        uint amount = status.userFunds[msg.sender];
        status.userFunds[msg.sender] = 0;
        if (amount == 0) {
            revert CannotWithdrawZeroAmount();
        }

        // send the funds
        payable(msg.sender).transfer(amount);
        return amount;
    }

    function winnerOf(uint256 tokenID) public view returns (address) {
        return auctionStatus[tokenID].winner;
    }

    // contract owner withdraw all winner amount.
    function ownerWithdraw() public onlyOwner onlyAfterHardEnd {
        uint amount = ownerCanWithdraw;
        ownerCanWithdraw = 0;
        if (amount == 0) {
            revert CannotWithdrawZeroAmount();
        }
        payable(msg.sender).transfer(amount);
    }

    function hardWithdraw() public onlyOwner onlyAfterHardEnd {
        require (block.timestamp > hardEndTime + 14 days);
        uint amount = address(this).balance;
        payable(msg.sender).transfer(amount);
    }

    // set user quota, only possible before auction starts.
    function setUserQuota(
        address user,
        uint8 quota
    ) public onlyOwner onlyBeforeStart {
        UserStatus storage us = userStatus[user];
        us.quota = quota;
    }
    
    function setUserQuotas(
        address[] calldata users,
        uint8[] calldata quotas
    ) public onlyOwner onlyBeforeStart {
        require(users.length == quotas.length);
        for (uint i = 0; i < users.length; i++) {
            setUserQuota(users[i], quotas[i]);
        }
    }

    // Each bid to a new tokenID will consume a quota.
    // When the quota drops to 0, users can’t bid for a new domain.
    function _consumeQuota(address user, uint256 tokenID) private {
        // user has bidded on this tokenID before, no more quota required.
        if (userStatus[user].bided[tokenID]) {
            return;
        }
        UserStatus storage us = userStatus[user];
        if (userStatus[user].quota < 1) {
            revert NotEnoughQuota();
        }
        us.quota -= 1;
        us.bided[tokenID] = true;
        us.bids.push(tokenID);
    }

    // initialize auction status label and endtime, if not initialized yet.
    // It will also check @p lable validity, revert if invalid.
    function _initAuctionStatus(
        uint256 tokenID,
        string calldata label
    ) private {
        if (!valid(label)) {
            revert InvalidLabel(label);
        }
        if (!available(label)) {
            revert DomainNotAvailable(label);
        }
        TokenAuctionStatus storage status = auctionStatus[tokenID];
        // auction of @p label is already initialialzed, just return.
        if (status.endTime != 0) {
            return;
        }
        status.label = label;
        status.endTime = initialEndTime;
    }

    // returns the min bid price for @p tokenID.
    // If there's already a bid on @p TokenID, price = (lastBid * 105%).
    // otherwise, the min bid price will be the 1-year registration fee.
    function nextBidFloorPrice(
        uint256 tokenID,
        string calldata name
    ) public view returns (uint) {
        TokenAuctionStatus storage status = auctionStatus[tokenID];
        if (status.winner != address(0)) {
            // If any user bids, min bid is set at 105% of the top bid.
            uint currentHighest = status.userFunds[status.winner];
            return (currentHighest / 100) * 105;
        } else {
            IPriceOracle.Price memory price = prices.price(
                name,
                0,
                MIN_REGISTRATION_DURATION
            );
            return price.base;
        }
    }

    //a token's top bid
    function topBid(uint256 tokenID) public view returns (uint256) {
        return auctionStatus[tokenID].userFunds[auctionStatus[tokenID].winner];
    }

    function userBidsView(
        address user
    ) public view returns (UserBidsView[5] memory rv) {
        for (uint i = 0; i < userStatus[user].bids.length; i++) {
            uint256 tokenID = userStatus[user].bids[i];
            rv[i] = (
                UserBidsView(
                    auctionStatus[tokenID].label,
                    tokenID,
                    auctionStatus[tokenID].winner,
                    topBid(tokenID),
                    auctionStatus[tokenID].userFunds[user]
                )
            );
        }
    }

    function topBidsView() public view returns (TopBidView[10] memory rv) {
        for (uint i = 0; i < topBids.length; i++) {
            rv[i] = (
                TopBidView(
                    auctionStatus[topBids[i].tokenID].label,
                    topBids[i].bid
                )
            );
        }
    }

    // returns true if the name is valid.
    function valid(string calldata name) public pure returns (bool) {
        // check unicode rune count, if rune count is >=3, byte length must be >=3.
        if (name.strlen() < 3) {
            return false;
        }
        bytes memory nb = bytes(name);
        // zero width for /u200b /u200c /u200d and U+FEFF
        for (uint256 i; i < nb.length - 2; i++) {
            if (bytes1(nb[i]) == 0xe2 && bytes1(nb[i + 1]) == 0x80) {
                if (
                    bytes1(nb[i + 2]) == 0x8b ||
                    bytes1(nb[i + 2]) == 0x8c ||
                    bytes1(nb[i + 2]) == 0x8d
                ) {
                    return false;
                }
            } else if (bytes1(nb[i]) == 0xef) {
                if (bytes1(nb[i + 1]) == 0xbb && bytes1(nb[i + 2]) == 0xbf)
                    return false;
            }
        }
        return true;
    }

    // returns true if @p user is the winner of auction on @p tokenID.
    function isWinner(
        address user,
        uint256 tokenID
    ) public view returns (bool) {
        return auctionStatus[tokenID].winner == user;
    }

    // returns the number of quota that the @p user can use in phase 2.
    function phase2Quota(address user) public view returns (uint8) {
        UserStatus storage us = userStatus[user];
        uint8 quota = us.quota;
        for (uint8 i = 0; i < us.bids.length; i++) {
            if (!isWinner(user, us.bids[i])) {
                quota++;
            }
        }
        return quota;
    }

    function min(uint a, uint b) private pure returns (uint) {
        if (a < b) return a;
        return b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    modifier onlyBeforeStart() {
        if (block.timestamp >= startTime) {
            revert AuctionStarted();
        }
        _;
    }

    modifier onlyAfterStart() {
        if (block.timestamp < startTime) {
            revert AuctionNotStarted();
        }
        _;
    }

    modifier onlyBeforeHardEnd() {
        if (block.timestamp > hardEndTime) {
            revert AuctionHardDeadlinePassed();
        }
        _;
    }

    modifier onlyAfterHardEnd() {
        if (block.timestamp <= hardEndTime) {
            revert AuctionNotEnded();
        }
        _;
    }
}

