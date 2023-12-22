// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeMath.sol";

import "./SafeToken.sol";

import "./IGrvPresale.sol";
import "./ILocker.sol";
import "./IBEP20.sol";

contract GrvPresale is IGrvPresale, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint256;
    using SafeToken for address;

    /* ========== CONSTANTS ============= */

    address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /* ========== STATE VARIABLES ========== */

    MarketInfo public override marketInfo;
    MarketStatus public override marketStatus;
    ILocker public locker;

    uint256 public override startReleaseTimestamp;
    uint256 public override endReleaseTimestamp;
    mapping(address => uint256) public lastUnlockTimestamp;

    address public override auctionToken;
    address public override paymentCurrency;
    address payable public treasury;

    mapping(address => uint256) public override commitments;
    mapping(address => uint256) public override claimed;
    mapping(address => string) public override nicknames;
    mapping(address => bool) public blacklist;

    /* ========== INITIALIZER ========== */

    function initialize(address _token, address _locker, uint256 _totalTokens, uint256 _startTime,
        uint256 _endTime, address _paymentCurrency, uint256 _minimumCommitmentAmount,
        uint256 _commitmentCap, address payable _treasury, uint256 _startReleaseTimestamp,
        uint256 _endReleaseTimestamp) external initializer {
        require(_startTime < 10000000000, "GrvPresale: enter an unix timestamp in seconds, not miliseconds");
        require(_endTime < 10000000000, "GrvPresale: enter an unix timestamp in seconds, not miliseconds");
        require(_startTime >= block.timestamp, "GrvPresale: start time is before current time");
        require(_endTime > _startTime, "GrvPresale: end time must be older than start time");
        require(_totalTokens > 0, "GrvPresale: total tokens must be greater than zero");
        require(_treasury != address(0), "GrvPresale: treasury is the zero address");
        require(_endReleaseTimestamp > _startReleaseTimestamp, "GrvPresale: endReleaseTimestamp < startReleaseTimestamp");

        require(IBEP20(_token).decimals() == 18, "GrvPresale: Token does not have 18 decimals");
        if (_paymentCurrency != ETH_ADDRESS) {
            require(IBEP20(_paymentCurrency).decimals() > 0, "GrvPresale: Payment currency is not ERC20");
        }

        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

        marketStatus.minimumCommitmentAmount = _minimumCommitmentAmount;

        marketInfo.startTime = _startTime;
        marketInfo.endTime = _endTime;
        marketInfo.totalTokens = _totalTokens;
        marketInfo.commitmentCap = _commitmentCap;

        auctionToken = _token;
        paymentCurrency = _paymentCurrency;
        treasury = _treasury;

        locker = ILocker(_locker);
        startReleaseTimestamp = _startReleaseTimestamp;
        endReleaseTimestamp = _endReleaseTimestamp;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function depositAuctionToken(address _funder) external onlyOwner {
        auctionToken.safeTransferFrom(_funder, address(this), marketInfo.totalTokens);
        emit AuctionTokenDeposited(marketInfo.totalTokens);
    }

    function finalize() external onlyOwner {
        require(!marketStatus.finalized, "GrvPresale: Auction has already finalized");
        require(block.timestamp > marketInfo.endTime, "GrvPresale: Auction has not finished yet");
        if (auctionSuccessful()) {
            // Successful auction
            // Transfer contributed tokens to treasury.
            _safeTokenPayment(paymentCurrency, treasury, marketStatus.commitmentsTotal);
        } else {
            // Failed auction
            // Return auction tokens back to treasury.
            auctionToken.safeTransfer(treasury, marketInfo.totalTokens);
        }
        marketStatus.finalized = true;
        emit AuctionFinalized();
    }

    function cancelAuction() external onlyOwner nonReentrant {
        MarketStatus storage status = marketStatus;
        require(!status.finalized, "GrvPresale: already finalized");
        require(status.commitmentsTotal == 0, "GrvPresale: Funds already raised");

        auctionToken.safeTransfer(treasury, marketInfo.totalTokens);
        status.finalized = true;
        emit AuctionCancelled();
    }

    function setAuctionTime(uint256 _startTime, uint256 _endTime) external onlyOwner {
        require(_startTime < 10000000000, "GrvPresale: enter an unix timestamp in seconds, not miliseconds");
        require(_endTime < 10000000000, "GrvPresale: enter an unix timestamp in seconds, not miliseconds");
        require(_startTime >= block.timestamp, "GrvPresale: start time is before current time");
        require(_endTime > _startTime, "GrvPresale: end time must be older than start price");

        require(marketStatus.commitmentsTotal == 0, "GrvPresale: auction cannot have already started");

        marketInfo.startTime = _startTime;
        marketInfo.endTime = _endTime;

        emit AuctionTimeUpdated(_startTime, _endTime);
    }

    function setAuctionPrice(uint256 _minimumCommitmentAmount) external onlyOwner {
        require(marketStatus.commitmentsTotal == 0, "GrvPresale: auction cannot have already started");
        marketStatus.minimumCommitmentAmount = _minimumCommitmentAmount;
        emit AuctionPriceUpdated(_minimumCommitmentAmount);
    }

    function setAuctionTreasury(address payable _treasury) external onlyOwner {
        require(_treasury != address(0), "GrvPresale: treasury is the zero address");
        treasury = _treasury;
        emit AuctionTreasuryUpdated(_treasury);
    }

    function setLocker(address _locker) external onlyOwner {
        require(_locker != address(0), "GrvPresale: locker is the zero address");
        locker = ILocker(_locker);
        emit LockerUpdated(_locker);
    }

    function setBlacklist(address _addr, bool isBlackUser) external onlyOwner {
        require(_addr != address(0), "GrvPresale: address is zero address");
        blacklist[_addr] = isBlackUser;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function commitETH(address payable _beneficiary) external payable override nonReentrant {
        require(paymentCurrency == ETH_ADDRESS, "GrvPresale: Payment currency is not ETH");
        require(msg.value > 0, "GrvPresale: value must be higher than 0");
        require(marketStatus.commitmentsTotal < marketInfo.commitmentCap, "GrvPresale: commitment cap full");

        _addCommitment(_beneficiary, msg.value);
        if (lastUnlockTimestamp[_beneficiary] < startReleaseTimestamp) {
            lastUnlockTimestamp[_beneficiary] = startReleaseTimestamp;
        }
        // Revert if commitmentsTotal exceeds the balance
        require(marketStatus.commitmentsTotal <= address(this).balance, "GrvPresale: The committed GRV exceeds the balance");
    }

    function commitTokens(uint256 _amount) external override nonReentrant {
        _commitTokensFrom(msg.sender, _amount);
    }

    function withdrawTokens(address payable beneficiary) external override nonReentrant {
        if (auctionSuccessful()) {
            require(marketStatus.finalized, "GrvPresale: not finalized");
            // Successful auction! Transfer claimed tokens.
            uint256 tokensToClaim = tokensClaimable(beneficiary);
            require(tokensToClaim > 0, "GrvPresale: No tokens to claim");
            claimed[beneficiary] = claimed[beneficiary].add(tokensToClaim);

            auctionToken.safeTransfer(beneficiary, tokensToClaim);
            lastUnlockTimestamp[beneficiary] = block.timestamp;
        } else {
            // auction did not meet reserve price
            // return committed funds back to user
            require(block.timestamp > marketInfo.endTime, "GrvPresale: Auction has not finished yet");
            uint256 fundsCommitted = commitments[beneficiary];
            require(fundsCommitted > 0, "GrvPresale: No funds committed");
            commitments[beneficiary] = 0; // Stop multiple withdrawals
            _safeTokenPayment(paymentCurrency, beneficiary, fundsCommitted);
        }
    }

    function withdrawToLocker() external override nonReentrant {
        require(marketStatus.finalized, "GrvPresale: not finalized");
        require(auctionSuccessful(), "GrvPresale: auction failed");
        uint256 tokensToLockable = tokensLockable(msg.sender);
        require(tokensToLockable > 0, "GrvPresale: No tokens to Lock");
        require(locker.expiryOf(msg.sender) == 0 || locker.expiryOf(msg.sender) > after6Month(block.timestamp),
            "GrvPresale: locker lockup period less than 6 months");

        claimed[msg.sender] = claimed[msg.sender].add(tokensToLockable);

        auctionToken.safeApprove(address(locker), tokensToLockable);
        locker.depositBehalf(msg.sender, tokensToLockable, after6Month(block.timestamp));
        auctionToken.safeApprove(address(locker), 0);
    }

    function setNickname(address _addr, string calldata _name) external override {
        require(_addr != address(0), "GrvPresale: address is zero address");
        require(blacklist[msg.sender] == false, "GrvPresale: Blacklist user");
        require(msg.sender == _addr || msg.sender == owner(), "GrvPresale: do not have permission to set a name");
        nicknames[_addr] = _name;
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _commitTokensFrom(address payable _from, uint256 _amount) private {
        require(paymentCurrency != ETH_ADDRESS, "GrvPresale: Payment currency is not a token");
        require(_amount > 0, "GrvPresale: Value must be higher than 0");
        require(marketStatus.commitmentsTotal < marketInfo.commitmentCap, "GrvPresale: commitment cap full");

        _safeTransferFrom(paymentCurrency, msg.sender, _amount);
        _addCommitment(_from, _amount);
        if (lastUnlockTimestamp[_from] < startReleaseTimestamp) {
            lastUnlockTimestamp[_from] = startReleaseTimestamp;
        }
    }

    function _addCommitment(address payable _addr, uint256 _commitment) private {
        require(block.timestamp >= marketInfo.startTime && block.timestamp <= marketInfo.endTime, "GrvPresale: outside auction hours");
        require(!marketStatus.finalized, "GrvPresale: has been finalized");

        if (_commitment.add(marketStatus.commitmentsTotal) > marketInfo.commitmentCap) {
            uint256 _canCommitmentAmount = marketInfo.commitmentCap.sub(marketStatus.commitmentsTotal);
            uint256 _refundAmount = _commitment.sub(_canCommitmentAmount);
            _commitment = _canCommitmentAmount;
            _safeTokenPayment(paymentCurrency, _addr, _refundAmount);
        }

        uint256 newCommitment = commitments[_addr].add(_commitment);
        commitments[_addr] = newCommitment;
        marketStatus.commitmentsTotal = marketStatus.commitmentsTotal.add(_commitment);
        emit AddedCommitment(_addr, _commitment);
    }

    // calculates amount of auction tokens for user to receive.
    function _getTokenAmount(uint256 amount) private view returns (uint256) {
        if (marketStatus.commitmentsTotal == 0) {
            return 0;
        }
        return _getAdjustedAmount(paymentCurrency, amount).mul(1e18).div(tokenPrice());
    }

    function _canUnlockAmount(address _user, uint256 _unclaimedTokenAmount) private view returns (uint256) {
        if (block.timestamp < startReleaseTimestamp) {
            return 0;
        } else if (block.timestamp >= endReleaseTimestamp) {
            return _unclaimedTokenAmount;
        } else {
            uint256 releasedTimestamp = block.timestamp.sub(lastUnlockTimestamp[_user]);
            uint256 timeLeft = endReleaseTimestamp.sub(lastUnlockTimestamp[_user]);
            return _unclaimedTokenAmount.mul(releasedTimestamp).div(timeLeft);
        }
    }

    /// @dev Helper function to handle both ETH and ERC20 payments
    function _safeTokenPayment(
        address _token,
        address payable _to,
        uint256 _amount
    ) internal {
        if (address(_token) == ETH_ADDRESS) {
            _safeTransferETH(_to,_amount );
        } else {
            _safeTransfer(_token, _to, _amount);
        }
    }

    function _safeTransferETH(address to, uint256 value) private {
        (bool success, ) = to.call{ value: value }(new bytes(0));
        require(success, "!safeTransferETH");
    }

    function _safeTransfer(
        address token,
        address to,
        uint256 amount
    ) internal virtual {
        (bool success, bytes memory data) =
        token.call(
        // 0xa9059cbb = bytes4(keccak256("transfer(address,uint256)"))
            abi.encodeWithSelector(0xa9059cbb, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool)))); // ERC20 Transfer failed
    }

    function _safeTransferFrom(address token, address from, uint256 amount) private {
        (bool success, bytes memory data) =
        token.call(
        // 0x23b872dd = bytes4(keccak256("transferFrom(address,address,uint256)"))
            abi.encodeWithSelector(0x23b872dd, from, address(this), amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _getAdjustedAmount(address token, uint256 amount) private view returns (uint256) {
        if (token == address(0)) {
            return amount;
        } else {
            uint256 defaultDecimal = 18;
            uint256 tokenDecimal = IBEP20(token).decimals();

            if (tokenDecimal == defaultDecimal) {
                return amount;
            } else if (tokenDecimal < defaultDecimal) {
                return amount * (10**(defaultDecimal - tokenDecimal));
            } else {
                return amount / (10**(tokenDecimal - defaultDecimal));
            }
        }
    }

    /* ========== VIEWS ========== */

    function after6Month(uint256 timestamp) public pure override returns (uint256) {
        timestamp = timestamp + 180 days;
        return ((timestamp.add(1 weeks) / 1 weeks) * 1 weeks);
    }

    function tokenPrice() public view override returns (uint256) {
        return _getAdjustedAmount(paymentCurrency, marketStatus.commitmentsTotal).mul(1e18).div(marketInfo.totalTokens);
    }

    function tokensClaimable(address _user) public view override returns (uint256 claimerCommitment) {
        if (commitments[_user] == 0) {
            return 0;
        }
        uint256 unclaimedTokens = IBEP20(auctionToken).balanceOf(address(this));
        claimerCommitment = _getTokenAmount(commitments[_user]);
        claimerCommitment = claimerCommitment.sub(claimed[_user]);

        claimerCommitment = _canUnlockAmount(_user, claimerCommitment);

        if (claimerCommitment > unclaimedTokens) {
            claimerCommitment = unclaimedTokens;
        }
    }

    function tokensLockable(address _user) public view override returns (uint256 claimerCommitment) {
        if (commitments[_user] == 0) {
            return 0;
        }
        uint256 unclaimedTokens = IBEP20(auctionToken).balanceOf(address(this));
        claimerCommitment = _getTokenAmount(commitments[_user]);
        claimerCommitment = claimerCommitment.sub(claimed[_user]);

        if (claimerCommitment > unclaimedTokens) {
            claimerCommitment = unclaimedTokens;
        }
    }

    function finalized() external view override returns (bool) {
        return marketStatus.finalized;
    }

    function auctionSuccessful() public view override returns (bool) {
        return marketStatus.commitmentsTotal >= marketStatus.minimumCommitmentAmount && marketStatus.commitmentsTotal > 0;
    }

    function auctionEnded() external view override returns (bool) {
        return block.timestamp > marketInfo.endTime;
    }

    function getBaseInformation() external view override returns (uint256 startTime, uint256 endTime, bool marketFinalized) {
        startTime = marketInfo.startTime;
        endTime = marketInfo.endTime;
        marketFinalized = marketStatus.finalized;
    }

    function getTotalTokens() external view override returns(uint256) {
        return marketInfo.totalTokens;
    }
}

