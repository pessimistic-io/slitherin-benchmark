// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;

import "./SafeMath.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./IRushAirdropDistributor.sol";
import "./ILocker.sol";
import "./IBEP20.sol";

import "./SafeToken.sol";

contract RushAirdropDistributor is IRushAirdropDistributor, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint256;
    using SafeToken for address;

    /* ========== CONSTANT VARIABLES ========== */

    uint256 public constant firstGravityRewardQuota = 1000000e18;
    uint256 public constant secondGravityRewardQuota = 1000000e18;
    uint256 public constant thirdGravityRewardQuota = 1000000e18;
    uint256 public constant fourthGravityRewardQuota = 1000000e18;
    uint256 public constant fifthGravityRewardQuota = 1000000e18;
    uint256 public constant totalRewardQuota = 5000000e18;

    /* ========== STATE VARIABLES ========== */

    uint256 public startReleaseTimestamp;
    uint256 public endReleaseTimestamp;

    address public airdropToken;
    address public locker;

    mapping(address => uint256) public lastUnlockTimestamp;

    mapping(address => bool) public firstGravityUsers;
    uint256 public firstGravityUserCount;

    mapping(address => bool) public secondGravityUsers;
    uint256 public secondGravityUserCount;

    mapping(address => bool) public thirdGravityUsers;
    uint256 public thirdGravityUserCount;

    mapping(address => bool) public fourthGravityUsers;
    uint256 public fourthGravityUserCount;

    mapping(address => bool) public fifthGravityUsers;
    uint256 public fifthGravityUserCount;

    mapping(address => uint256) public claimed;

    /* ========== INITIALIZER ========== */

    function initialize(
        address _airdropToken,
        address _locker,
        uint256 _startReleaseTimestamp,
        uint256 _endReleaseTimestamp
    ) external initializer {
        require(_airdropToken != address(0), "RushAirdropDistributor: airdropToken is zero address");
        require(_locker != address(0), "RushAirdropDistributor: locker is zero address");

        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

        airdropToken = _airdropToken;
        locker = _locker;

        startReleaseTimestamp = _startReleaseTimestamp;
        endReleaseTimestamp = _endReleaseTimestamp;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function depositAirdropToken(address _funder) external onlyOwner {
        airdropToken.safeTransferFrom(_funder, address(this), totalRewardQuota);
    }

    function withdrawAirdropToken() external onlyOwner {
        uint256 _airdropTokenBalance = IBEP20(airdropToken).balanceOf(address(this));
        airdropToken.safeTransfer(msg.sender, _airdropTokenBalance);
    }

    function setFirstGravityUser(address _user) external onlyOwner {
        if (firstGravityUsers[_user] == false) {
            firstGravityUsers[_user] = true;
            firstGravityUserCount = firstGravityUserCount.add(1);
        }
        if (lastUnlockTimestamp[_user] < startReleaseTimestamp) {
            lastUnlockTimestamp[_user] = startReleaseTimestamp;
        }
    }

    function setFirstGravityUsers(address[] calldata _users) external onlyOwner {
        uint256 _setCount = 0;
        for (uint256 i = 0; i < _users.length; i++) {
            if (firstGravityUsers[_users[i]] == false) {
                firstGravityUsers[_users[i]] = true;
                _setCount = _setCount.add(1);
            }
            if (lastUnlockTimestamp[_users[i]] < startReleaseTimestamp) {
                lastUnlockTimestamp[_users[i]] = startReleaseTimestamp;
            }
        }
        firstGravityUserCount = firstGravityUserCount.add(_setCount);
    }

    function removeFirstGravityUser(address _user) external onlyOwner {
        if (firstGravityUsers[_user]) {
            firstGravityUsers[_user] = false;
            firstGravityUserCount = firstGravityUserCount.sub(1);
        }
    }

    function setSecondGravityUser(address _user) external onlyOwner {
        if (secondGravityUsers[_user] == false) {
            secondGravityUsers[_user] = true;
            secondGravityUserCount = secondGravityUserCount.add(1);
        }
        if (lastUnlockTimestamp[_user] < startReleaseTimestamp) {
            lastUnlockTimestamp[_user] = startReleaseTimestamp;
        }
    }

    function setSecondGravityUsers(address[] calldata _users) external onlyOwner {
        uint256 _setCount = 0;
        for (uint256 i = 0; i < _users.length; i++) {
            if (secondGravityUsers[_users[i]] == false) {
                secondGravityUsers[_users[i]] = true;
                _setCount = _setCount.add(1);
            }
            if (lastUnlockTimestamp[_users[i]] < startReleaseTimestamp) {
                lastUnlockTimestamp[_users[i]] = startReleaseTimestamp;
            }
        }
        secondGravityUserCount = secondGravityUserCount.add(_setCount);
    }

    function removeSecondGravityUser(address _user) external onlyOwner {
        if (secondGravityUsers[_user]) {
            secondGravityUsers[_user] = false;
            secondGravityUserCount = secondGravityUserCount.sub(1);
        }
    }

    function setThirdGravityUser(address _user) external onlyOwner {
        if (thirdGravityUsers[_user] == false) {
            thirdGravityUsers[_user] = true;
            thirdGravityUserCount = thirdGravityUserCount.add(1);
        }
        if (lastUnlockTimestamp[_user] < startReleaseTimestamp) {
            lastUnlockTimestamp[_user] = startReleaseTimestamp;
        }
    }

    function setThirdGravityUsers(address[] calldata _users) external onlyOwner {
        uint256 _setCount = 0;
        for (uint256 i = 0; i < _users.length; i++) {
            if (thirdGravityUsers[_users[i]] == false) {
                thirdGravityUsers[_users[i]] = true;
                _setCount = _setCount.add(1);
            }
            if (lastUnlockTimestamp[_users[i]] < startReleaseTimestamp) {
                lastUnlockTimestamp[_users[i]] = startReleaseTimestamp;
            }
        }
        thirdGravityUserCount = thirdGravityUserCount.add(_setCount);
    }

    function removeThirdGravityUser(address _user) external onlyOwner {
        if (thirdGravityUsers[_user]) {
            thirdGravityUsers[_user] = false;
            thirdGravityUserCount = thirdGravityUserCount.sub(1);
        }
    }

    function setFourthGravityUser(address _user) external onlyOwner {
        if (fourthGravityUsers[_user] == false) {
            fourthGravityUsers[_user] = true;
            fourthGravityUserCount = fourthGravityUserCount.add(1);
        }
        if (lastUnlockTimestamp[_user] < startReleaseTimestamp) {
            lastUnlockTimestamp[_user] = startReleaseTimestamp;
        }
    }

    function setFourthGravityUsers(address[] calldata _users) external onlyOwner {
        uint256 _setCount = 0;
        for (uint256 i = 0; i < _users.length; i++) {
            if (fourthGravityUsers[_users[i]] == false) {
                fourthGravityUsers[_users[i]] = true;
                _setCount = _setCount.add(1);
            }
            if (lastUnlockTimestamp[_users[i]] < startReleaseTimestamp) {
                lastUnlockTimestamp[_users[i]] = startReleaseTimestamp;
            }
        }
        fourthGravityUserCount = fourthGravityUserCount.add(_setCount);
    }

    function removeFourthGravityUser(address _user) external onlyOwner {
        if (fourthGravityUsers[_user]) {
            fourthGravityUsers[_user] = false;
            fourthGravityUserCount = fourthGravityUserCount.sub(1);
        }
    }

    function setFifthGravityUser(address _user) external onlyOwner {
        if (fifthGravityUsers[_user] == false) {
            fifthGravityUsers[_user] = true;
            fifthGravityUserCount = fifthGravityUserCount.add(1);
        }
        if (lastUnlockTimestamp[_user] < startReleaseTimestamp) {
            lastUnlockTimestamp[_user] = startReleaseTimestamp;
        }
    }

    function setFifthGravityUsers(address[] calldata _users) external onlyOwner {
        uint256 _setCount = 0;
        for (uint256 i = 0; i < _users.length; i++) {
            if (fifthGravityUsers[_users[i]] == false) {
                fifthGravityUsers[_users[i]] = true;
                _setCount = _setCount.add(1);
            }
            if (lastUnlockTimestamp[_users[i]] < startReleaseTimestamp) {
                lastUnlockTimestamp[_users[i]] = startReleaseTimestamp;
            }
        }
        fifthGravityUserCount = fifthGravityUserCount.add(_setCount);
    }

    function removeFifthGravityUser(address _user) external onlyOwner {
        if (fifthGravityUsers[_user]) {
            fifthGravityUsers[_user] = false;
            fifthGravityUserCount = fifthGravityUserCount.sub(1);
        }
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function withdrawTokens() external override nonReentrant {
        uint256 _tokensToClaim = tokensClaimable(msg.sender);
        require(_tokensToClaim > 0, "RushAirdropDistributor: No tokens to claim");
        claimed[msg.sender] = claimed[msg.sender].add(_tokensToClaim);

        airdropToken.safeTransfer(msg.sender, _tokensToClaim);
        lastUnlockTimestamp[msg.sender] = block.timestamp;
    }

    function withdrawToLocker() external override nonReentrant {
        uint256 _tokensToLockable = tokensLockable(msg.sender);
        require(_tokensToLockable > 0, "RushAirdropDistributor: No tokens to Lock");
        require(ILocker(locker).expiryOf(msg.sender) == 0 || ILocker(locker).expiryOf(msg.sender) > after6Month(block.timestamp),
            "RushAirdropDistributor: locker lockup period less than 6 months");

        claimed[msg.sender] = claimed[msg.sender].add(_tokensToLockable);

        airdropToken.safeApprove(locker, _tokensToLockable);
        ILocker(locker).depositBehalf(msg.sender, _tokensToLockable, after6Month(block.timestamp));
        airdropToken.safeApprove(locker, 0);
    }

    /* ========== VIEWS ========== */

    function tokensClaimable(address _user) public view returns (uint256 claimableAmount) {
        claimableAmount = 0;

        if (firstGravityUsers[_user]) {
            claimableAmount = claimableAmount.add(getFirstGravityReward());
        }

        if (secondGravityUsers[_user]) {
            claimableAmount = claimableAmount.add(getSecondGravityReward());
        }

        if (thirdGravityUsers[_user]) {
            claimableAmount = claimableAmount.add(getThirdGravityReward());
        }

        if (fourthGravityUsers[_user]) {
            claimableAmount = claimableAmount.add(getFourthGravityReward());
        }

        if (fifthGravityUsers[_user]) {
            claimableAmount = claimableAmount.add(getFifthGravityReward());
        }

        claimableAmount = claimableAmount.sub(claimed[_user]);
        claimableAmount = _canUnlockAmount(_user, claimableAmount);

        uint256 unclaimedTokens = IBEP20(airdropToken).balanceOf(address(this));

        if (claimableAmount > unclaimedTokens) {
            claimableAmount = unclaimedTokens;
        }
    }

    function tokensLockable(address _user) public view returns (uint256 lockableAmount) {
        lockableAmount = 0;

        if (firstGravityUsers[_user]) {
            lockableAmount = lockableAmount.add(getFirstGravityReward());
        }

        if (secondGravityUsers[_user]) {
            lockableAmount = lockableAmount.add(getSecondGravityReward());
        }

        if (thirdGravityUsers[_user]) {
            lockableAmount = lockableAmount.add(getThirdGravityReward());
        }

        if (fourthGravityUsers[_user]) {
            lockableAmount = lockableAmount.add(getFourthGravityReward());
        }

        if (fifthGravityUsers[_user]) {
            lockableAmount = lockableAmount.add(getFifthGravityReward());
        }

        lockableAmount = lockableAmount.sub(claimed[_user]);

        uint256 unclaimedTokens = IBEP20(airdropToken).balanceOf(address(this));

        if (lockableAmount > unclaimedTokens) {
            lockableAmount = unclaimedTokens;
        }
    }

    function getFirstGravityReward() public view returns (uint256 _rewardAmount) {
        if (firstGravityUserCount == 0) {
            return 0;
        }
        return firstGravityRewardQuota.div(firstGravityUserCount);
    }

    function getSecondGravityReward() public view returns (uint256 _rewardAmount) {
        if (secondGravityUserCount == 0) {
            return 0;
        }
        return secondGravityRewardQuota.div(secondGravityUserCount);
    }

    function getThirdGravityReward() public view returns (uint256 _rewardAmount) {
        if (thirdGravityUserCount == 0) {
            return 0;
        }
        return thirdGravityRewardQuota.div(thirdGravityUserCount);
    }

    function getFourthGravityReward() public view returns (uint256 _rewardAmount) {
        if (fourthGravityUserCount == 0) {
            return 0;
        }
        return fourthGravityRewardQuota.div(fourthGravityUserCount);
    }

    function getFifthGravityReward() public view returns (uint256 _rewardAmount) {
        if (fifthGravityUserCount == 0) {
            return 0;
        }
        return fifthGravityRewardQuota.div(fifthGravityUserCount);
    }

    function after6Month(uint256 timestamp) public pure returns (uint) {
        timestamp = timestamp + 180 days;
        return ((timestamp.add(1 weeks) / 1 weeks) * 1 weeks);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _canUnlockAmount(address _user, uint256 _unclaimedTokenAmount) private view returns (uint) {
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

