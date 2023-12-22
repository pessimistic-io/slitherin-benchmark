// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;

import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeMath.sol";

import "./IGenesisRewardDistributor.sol";
import "./ILocker.sol";
import "./IBEP20.sol";

import "./SafeToken.sol";

contract GenesisRewardDistributor is IGenesisRewardDistributor, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint256;
    using SafeToken for address;

    uint256 public constant totalRewardAmount = 5000000e18;

    /* ========== STATE VARIABLES ========== */

    mapping(address => uint256) public lastUnlockTimestamp;
    mapping(address => uint256) public claimed;

    mapping(address => uint256) public userLiquidity;
    uint256 public tvl;

    uint256 public startReleaseTimestamp;
    uint256 public endReleaseTimestamp;

    address public airdropToken;
    address public locker;

    /* ========== INITIALIZER ========== */

    function initialize(
        address _airdropToken,
        address _locker,
        uint256 _startReleaseTimestamp,
        uint256 _endReleaseTimestamp
    ) external initializer {
        require(_airdropToken != address(0), "GenesisRewardDistributor: airdropToken is zero address");
        require(_startReleaseTimestamp > block.timestamp, "GenesisRewardDistributor: invalid startReleaseTimestamp");
        require(_endReleaseTimestamp > _startReleaseTimestamp, "GenesisRewardDistributor: invalid endReleaseTimestamp");

        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

        airdropToken = _airdropToken;
        locker = _locker;

        startReleaseTimestamp = _startReleaseTimestamp;
        endReleaseTimestamp = _endReleaseTimestamp;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function depositAirdropToken(address _funder) external onlyOwner {
        airdropToken.safeTransferFrom(_funder, address(this), totalRewardAmount);
    }

    function withdrawAirdropToken() external onlyOwner {
        uint256 _airdropTokenBalance = IBEP20(airdropToken).balanceOf(address(this));
        airdropToken.safeTransfer(msg.sender, _airdropTokenBalance);
    }

    function setTvl(uint256 _tvl) external onlyOwner {
        require(_tvl > 0, "GenesisRewardDistributor: invalid tvl");
        tvl = _tvl;
    }

    function setUserLiquidityInfos(address[] calldata _users, uint256[] calldata _liquidityInfos) external onlyOwner {
        require(_users.length == _liquidityInfos.length, "GenesisRewardDistributor: invalid liquidityInfos length");
        for (uint256 i = 0; i < _users.length; i++) {
            userLiquidity[_users[i]] = _liquidityInfos[i];
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
        require(_tokensToClaim > 0, "GenesisRewardDistributor: No tokens to claim");
        claimed[msg.sender] = claimed[msg.sender].add(_tokensToClaim);

        airdropToken.safeTransfer(msg.sender, _tokensToClaim);
        lastUnlockTimestamp[msg.sender] = block.timestamp;
    }

    function withdrawToLocker() external override nonReentrant {
        uint256 _tokensToLockable = tokensLockable(msg.sender);
        require(_tokensToLockable > 0, "GenesisRewardDistributor: No tokens to Lock");
        require(ILocker(locker).expiryOf(msg.sender) == 0 || ILocker(locker).expiryOf(msg.sender) > after6Month(block.timestamp),
            "GenesisRewardDistributor: locker lockup period less than 6 months");

        claimed[msg.sender] = claimed[msg.sender].add(_tokensToLockable);
        airdropToken.safeApprove(locker, _tokensToLockable);
        ILocker(locker).depositBehalf(msg.sender, _tokensToLockable, after6Month(block.timestamp));
        airdropToken.safeApprove(locker, 0);
    }

    /* ========== VIEWS ========== */

    function tokensClaimable(address _user) public view override returns (uint256 claimableAmount) {
        if (userLiquidity[_user] == 0) {
            return 0;
        }
        uint256 unclaimedTokens = IBEP20(airdropToken).balanceOf(address(this));
        claimableAmount = _getTokenAmount(_user);
        claimableAmount = claimableAmount.sub(claimed[_user]);

        claimableAmount = _canUnlockAmount(_user, claimableAmount);

        if (claimableAmount > unclaimedTokens) {
            claimableAmount = unclaimedTokens;
        }
    }

    function tokensLockable(address _user) public view override returns (uint256 lockableAmount) {
        if (userLiquidity[_user] == 0) {
            return 0;
        }
        uint256 unclaimedTokens = IBEP20(airdropToken).balanceOf(address(this));
        lockableAmount = _getTokenAmount(_user);
        lockableAmount = lockableAmount.sub(claimed[_user]);

        if (lockableAmount > unclaimedTokens) {
            lockableAmount = unclaimedTokens;
        }
    }

    function after6Month(uint256 timestamp) public pure returns (uint) {
        timestamp = timestamp + 180 days;
        return ((timestamp.add(1 weeks) / 1 weeks) * 1 weeks);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _allocationOf(address _user) private view returns (uint256) {
        if (tvl == 0) {
            return 0;
        } else {
            return userLiquidity[_user].mul(1e18).div(tvl);
        }
    }

    function _getTokenAmount(address _user) private view returns (uint256) {
        if (tvl == 0) {
            return 0;
        }
        return totalRewardAmount.mul(_allocationOf(_user)).div(1e18);
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

}

