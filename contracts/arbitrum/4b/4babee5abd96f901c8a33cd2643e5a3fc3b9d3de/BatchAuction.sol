// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";

abstract contract BatchAuction is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public admin;
    address public auctionTreasury;
    address public auctionToken;
    address public payToken;
    bool public finalized;
    uint128 public totalTokens;

    uint64 public startTime;
    uint64 public endTime;
    uint128 public minimumCeilingPrice;
    uint128 public ceilingPrice;
    uint128 public minPrice;
    uint128 public commitmentsTotal;

    mapping(address => uint256) public commitments;
    mapping(address => uint256) public claimed;

    constructor(
        address _auctionToken,
        address _payToken,
        uint128 _totalTokens,
        uint64 _startTime,
        uint64 _endTime,
        uint128 _minimumCeilingPrice,
        uint128 _ceilingPrice,
        uint128 _minPrice,
        address _admin,
        address _treasury
    ) {
        require(_endTime < 10000000000, "unix timestamp in seconds");
        require(_startTime >= block.timestamp, "start time < current time");
        require(_endTime > _startTime, "end time < start price");
        require(_totalTokens != 0, "total tokens = 0");
        require(_ceilingPrice > _minPrice, "ceiling price < minimum price");
        require(_ceilingPrice >= _minimumCeilingPrice, "ceiling price < minimum ceiling price");
        require(_treasury != address(0), "address = 0");
        require(_admin != address(0), "address = 0");
        require(IERC20Metadata(_auctionToken).decimals() == 18, "decimals != 18");

        startTime = _startTime;
        endTime = _endTime;
        totalTokens = _totalTokens;

        ceilingPrice = _ceilingPrice;
        minPrice = _minPrice;
        minimumCeilingPrice = _minimumCeilingPrice;

        auctionToken = _auctionToken;
        payToken = _payToken;
        auctionTreasury = _treasury;
        admin = _admin;
        emit AuctionDeployed(
            _auctionToken, _payToken, _totalTokens, _startTime, _endTime, _ceilingPrice, _minPrice, _admin, _treasury
        );
    }

    /**
     * @notice Calculates the average price of each token from all commitments.
     * @return Average token price.
     */
    function tokenPrice() public view returns (uint256) {
        return uint256(commitmentsTotal) * 1e18 / uint256(totalTokens);
    }

    /**
     * @notice How many tokens the user is able to claim.
     * @param _user Auction participant address.
     * @return _claimerCommitment User commitments reduced by already claimed tokens.
     */
    function tokensClaimable(address _user) public view virtual returns (uint256 _claimerCommitment) {
        if (commitments[_user] == 0) {
            return 0;
        }
        _claimerCommitment = uint256(commitments[_user]) * uint256(totalTokens) / uint256(commitmentsTotal);
        _claimerCommitment -= claimed[_user];

        uint256 unclaimedTokens = IERC20(auctionToken).balanceOf(address(this));
        if (_claimerCommitment > unclaimedTokens) {
            _claimerCommitment = unclaimedTokens;
        }
    }

    /**
     * @notice Calculates the amount able to be committed during an auction.
     * @param _commitment Commitment user would like to make.
     * @return Amount allowed to commit.
     */
    function calculateCommitment(uint256 _commitment) public view returns (uint256) {
        uint256 _maxCommitment = uint256(totalTokens) * uint256(ceilingPrice) / 1e18;
        if (commitmentsTotal + _commitment > _maxCommitment) {
            return _maxCommitment - commitmentsTotal;
        }
        return _commitment;
    }

    /**
     * @notice Checks if the auction is open.
     * @return True if current time is greater than startTime and less than endTime.
     */
    function isOpen() public view returns (bool) {
        return block.timestamp >= startTime && block.timestamp <= endTime;
    }

    /**
     * @notice Successful if tokens sold equals totalTokens.
     * @return True if tokenPrice is bigger or equal clearingPrice.
     */
    function auctionSuccessful() public view returns (bool) {
        return uint256(commitmentsTotal) >= (uint256(totalTokens) * uint256(minPrice) / 1e18) && commitmentsTotal > 0;
    }

    /**
     * @notice Checks if the auction has ended.
     * @return True if auction is successful or time has ended.
     */
    function auctionEnded() public view returns (bool) {
        return block.timestamp > endTime
            || uint256(commitmentsTotal) >= (uint256(totalTokens) * uint256(ceilingPrice) / 1e18);
    }

    /**
     * @return Returns true if 7 days have passed since the end of the auction
     */
    function finalizeTimeExpired() public view returns (bool) {
        return endTime + 7 days < block.timestamp;
    }

    function hasAdminRole(address _sender) public view returns (bool) {
        return _sender == admin;
    }

    // ===========================================
    //              USER FUNCTIONS
    // ===========================================

    /**
     * @notice Checks how much is user able to commit and processes that commitment.
     * @dev Users must approve contract prior to committing tokens to auction.
     * @param _from User ERC20 address.
     * @param _amount Amount of approved ERC20 tokens.
     */
    function commitTokens(address _from, uint256 _amount) public nonReentrant {
        uint256 _amountToTransfer = calculateCommitment(_amount);
        if (_amountToTransfer > 0) {
            IERC20(payToken).safeTransferFrom(msg.sender, address(this), _amountToTransfer);
            _addCommitment(_from, _amountToTransfer);

            if (auctionEnded() && auctionSuccessful()) {
                _finalizeSuccessfulAuctionFund();
                finalized = true;
                emit AuctionFinalized();
            }
        }
    }

    /**
     * @notice Updates commitment for this address and total commitment of the auction.
     * @param _addr Bidders address.
     * @param _commitment The amount to commit.
     */
    function _addCommitment(address _addr, uint256 _commitment) internal {
        require(block.timestamp >= startTime && block.timestamp <= endTime, "aution not live");
        require(!finalized, "auction finalized");
        require(_commitment <= type(uint128).max, "> max commitment");
        commitments[_addr] += _commitment;
        commitmentsTotal += uint128(_commitment);
        emit AddedCommitment(_addr, _commitment);
    }

    //--------------------------------------------------------
    // Finalize Auction
    //--------------------------------------------------------

    /**
     * @notice Cancel Auction
     * @dev Admin can cancel the auction before it starts
     */
    function cancelAuction() public nonReentrant {
        require(hasAdminRole(msg.sender), "!admin");
        require(!finalized, "auction finalized");
        require(commitmentsTotal == 0, "auction completed");
        finalized = true;
        _finalizeFailedAuctionFund();
        emit AuctionCancelled();
    }

    /**
     * @notice Auction finishes successfully above the reserve.
     * @dev Transfer contract funds to initialized wallet.
     */
    function finalize() public nonReentrant {
        require(hasAdminRole(msg.sender) || finalizeTimeExpired(), "!admin");
        require(!finalized, "auction finalized");
        require(auctionEnded(), "not finished");
        if (auctionSuccessful()) {
            _finalizeSuccessfulAuctionFund();
        } else {
            _finalizeFailedAuctionFund();
        }
        finalized = true;
        emit AuctionFinalized();
    }

    function transferAdmin(address _newAdmin) public {
        require(hasAdminRole(msg.sender), "!admin");
        require(_newAdmin != address(0), "address = 0");
        admin = _newAdmin;
        emit NewAdminSet(_newAdmin);
    }

    function withdrawTokens(address _to) public nonReentrant {
        if (auctionSuccessful()) {
            require(finalized, "!finalized");
            uint256 _claimableAmount = tokensClaimable(msg.sender);
            require(_claimableAmount > 0, "claimable = 0");
            claimed[msg.sender] = claimed[msg.sender] + _claimableAmount;
            _safeTransferToken(auctionToken, _to, _claimableAmount);
        } else {
            // Auction did not meet reserve price.
            // Return committed funds back to user.
            require(block.timestamp > endTime, "!finished");
            uint256 fundsCommitted = commitments[msg.sender];
            commitments[msg.sender] = 0; // Stop multiple withdrawals and free some gas
            _safeTransferToken(payToken, _to, fundsCommitted);
        }
    }

    /**
     * @notice Admin can set start and end time through this function.
     * @param _startTime Auction start time.
     * @param _endTime Auction end time.
     */
    function setAuctionTime(uint256 _startTime, uint256 _endTime) external {
        require(hasAdminRole(msg.sender), "!admin");
        require(_startTime < 10000000000, "unix timestamp in seconds");
        require(_endTime < 10000000000, "unix timestamp in seconds");
        require(_startTime >= block.timestamp, "start time < current time");
        require(_endTime > _startTime, "end time < start time");
        require(commitmentsTotal == 0, "auction started");

        startTime = uint64(_startTime);
        endTime = uint64(_endTime);

        emit AuctionTimeUpdated(_startTime, _endTime);
    }

    function setAuctionPrice(uint256 _ceilingPrice, uint256 _minPrice) external {
        require(hasAdminRole(msg.sender), "!admin");
        require(_ceilingPrice > _minPrice, "ceiling price < minimum price");
        require(_ceilingPrice >= minimumCeilingPrice, "ceiling price < minimum ceiling price");
        require(commitmentsTotal == 0, "auction started");

        ceilingPrice = uint128(_ceilingPrice);
        minPrice = uint128(_minPrice);

        emit AuctionPriceUpdated(_ceilingPrice, _minPrice);
    }

    /**
     * @notice Admin can set the auction treasury through this function.
     * @param _treasury Auction treasury is where funds will be sent.
     */
    function setAuctionTreasury(address _treasury) external {
        require(hasAdminRole(msg.sender), "!admin");
        require(_treasury != address(0), "address = 0");
        auctionTreasury = _treasury;
        emit AuctionTreasuryUpdated(_treasury);
    }

    function _safeTransferToken(address _token, address _to, uint256 _amount) internal {
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function _finalizeSuccessfulAuctionFund() internal virtual {
        _safeTransferToken(payToken, auctionTreasury, commitmentsTotal);
    }

    function _finalizeFailedAuctionFund() internal virtual {
        _safeTransferToken(auctionToken, auctionTreasury, totalTokens);
    }

    // EVENTS
    /// @notice Event for all auction data. Emmited on deployment.
    event AuctionDeployed(
        address indexed _auctionToken,
        address indexed _payToken,
        uint256 _totalTokens,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _startPrice,
        uint256 _minPrice,
        address _auctionAdmin,
        address _auctionTreasury
    );

    /// @notice Event for adding a commitment.
    event AddedCommitment(address _addr, uint256 _commitment);

    /// @notice Event for finalization of the auction.
    event AuctionFinalized();

    /// @notice Event for cancellation of the auction.
    event AuctionCancelled();

    /// @notice Event for updating new admin.
    event NewAdminSet(address _admin);

    event AuctionTimeUpdated(uint256 _startTime, uint256 _endTime);
    event AuctionPriceUpdated(uint256 _ceilingPrice, uint256 _minPrice);
    event AuctionTreasuryUpdated(address indexed _treasury);
}

