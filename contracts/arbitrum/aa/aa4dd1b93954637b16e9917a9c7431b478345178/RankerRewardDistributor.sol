// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeMath.sol";

import "./IRankerRewardDistributor.sol";
import "./ILocker.sol";
import "./IBEP20.sol";

import "./SafeToken.sol";

contract RankerRewardDistributor is IRankerRewardDistributor, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint256;
    using SafeToken for address;

    /* ========== CONSTANT VARIABLES ========== */

    uint256 public constant totalRewardAmount = 2000000e18;
    uint256 public constant firstSectionReward = 250000e18;
    uint256 public constant secondSectionReward = 125000e18;
    uint256 public constant thirdSectionReward = 50000e18;
    uint256 public constant fourthSectionReward = 30000e18;
    uint256 public constant fifthSectionReward = 10625e18;
    uint256 public constant sixthSectionReward = 5625e18;

    /* ========== STATE VARIABLES ========== */

    mapping(address => uint256) public lastUnlockTimestamp;
    mapping(address => uint256) public claimed;

    mapping(address => uint256) public userRank;

    uint256 public startReleaseTimestamp;
    uint256 public endReleaseTimestamp;

    address public rewardToken;
    address public locker;

    /* ========== INITIALIZER ========== */
    function initialize(
        address _rewardToken,
        address _locker,
        uint256 _startReleaseTimestamp,
        uint256 _endReleaseTimestamp
    ) external initializer {
        require(_rewardToken != address(0), "RankerRewardDistributor: rewardToken is zero address");
        require(_startReleaseTimestamp > block.timestamp, "RankerRewardDistributor: invalid startReleaseTimestamp");
        require(_endReleaseTimestamp > _startReleaseTimestamp, "RankerRewardDistributor: invalid endReleaseTimestamp");

        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

        rewardToken = _rewardToken;
        locker = _locker;

        startReleaseTimestamp = _startReleaseTimestamp;
        endReleaseTimestamp = _endReleaseTimestamp;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function depositRewardToken() external onlyOwner {
        rewardToken.safeTransferFrom(msg.sender, address(this), totalRewardAmount);
    }

    function withdrawRewardToken() external onlyOwner {
        uint256 _rewardTokenBalance = IBEP20(rewardToken).balanceOf(address(this));
        rewardToken.safeTransfer(msg.sender, _rewardTokenBalance);
    }

    function setUserRanks(address[] calldata _users, uint256[] calldata _ranks) external onlyOwner {
        require(_users.length == _ranks.length, "RankerRewardDistributor: invalid ranks length");
        for (uint256 i = 0; i < _users.length; i++) {
            userRank[_users[i]] = _ranks[i];
            if (lastUnlockTimestamp[_users[i]] < startReleaseTimestamp) {
                lastUnlockTimestamp[_users[i]] = startReleaseTimestamp;
            }
        }
    }

    function setLocker(address _locker) external onlyOwner {
        require(_locker != address(0), "GrvPresale: locker is the zero address");
        locker = _locker;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function withdrawTokens() external override nonReentrant {
        uint256 _tokensToClaim = tokensClaimable(msg.sender);
        require(_tokensToClaim > 0, "RankerRewardDistributor: No tokens to claim");
        claimed[msg.sender] = claimed[msg.sender].add(_tokensToClaim);

        rewardToken.safeTransfer(msg.sender, _tokensToClaim);
        lastUnlockTimestamp[msg.sender] = block.timestamp;
    }

    function withdrawToLocker() external override nonReentrant {
        uint256 _tokensToLockable = tokensLockable(msg.sender);
        require(_tokensToLockable > 0, "RankerRewardDistributor: No tokens to Lock");
        require(ILocker(locker).expiryOf(msg.sender) == 0 ||
                ILocker(locker).expiryOf(msg.sender) > after6Month(block.timestamp),
                "RankerRewardDistributor: locker lockup period less than 6 months");

        claimed[msg.sender] = claimed[msg.sender].add(_tokensToLockable);
        rewardToken.safeApprove(locker, _tokensToLockable);
        ILocker(locker).depositBehalf(msg.sender, _tokensToLockable, after6Month(block.timestamp));
        rewardToken.safeApprove(locker, 0);
    }

    /* ========== VIEWS ========== */

    function tokensClaimable(address _user) public view override returns (uint256 claimableAmount) {
        if (userRank[_user] == 0) {
            return 0;
        }
        uint256 unclaimedTokens = IBEP20(rewardToken).balanceOf(address(this));
        claimableAmount = getTokenAmount(_user);
        claimableAmount = claimableAmount.sub(claimed[_user]);

        claimableAmount = _canUnlockAmount(_user, claimableAmount);

        if (claimableAmount > unclaimedTokens) {
            claimableAmount = unclaimedTokens;
        }
    }

    function tokensLockable(address _user) public view override returns (uint256 lockableAmount) {
        if (userRank[_user] == 0) {
            return 0;
        }
        uint256 unclaimedTokens = IBEP20(rewardToken).balanceOf(address(this));
        lockableAmount = getTokenAmount(_user);
        lockableAmount = lockableAmount.sub(claimed[_user]);

        if (lockableAmount > unclaimedTokens) {
            lockableAmount = unclaimedTokens;
        }
    }

    function getTokenAmount(address _user) public view override returns (uint256) {
        if (userRank[_user] == 1) {
            return firstSectionReward;
        } else if (userRank[_user] == 2 || userRank[_user] == 3) {
            return secondSectionReward;
        } else if (userRank[_user] >= 4 && userRank[_user] <= 10) {
            return thirdSectionReward;
        } else if (userRank[_user] >= 11 && userRank[_user] <= 30) {
            return fourthSectionReward;
        } else if (userRank[_user] >= 31 && userRank[_user] <= 70) {
            return fifthSectionReward;
        } else if (userRank[_user] >= 71 && userRank[_user] <= 100) {
            return sixthSectionReward;
        } else {
            return 0;
        }
    }

    function after6Month(uint256 timestamp) public pure returns (uint) {
        timestamp = timestamp + 180 days;
        return ((timestamp.add(1 weeks) / 1 weeks) * 1 weeks);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

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
}
