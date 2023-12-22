// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;

import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeMath.sol";

import "./SafeToken.sol";

import "./IVesting.sol";
import "./IBEP20.sol";

contract Vesting is IVesting, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint256;
    using SafeToken for address;

    /* ========== CONSTANTS ============= */

    uint256 private constant VESTING_AMOUNT = 100000000e18;
    uint256 private constant TOTAL_SHARE = 1e18;

    /* ========== STATE VARIABLES ========== */

    address public GRV;

    mapping(address => uint256) public lastUnlockTimestamp;
    mapping(address => uint256) public claimed;

    mapping(address => uint256) public userShare;

    uint256 public startReleaseTimestamp;
    uint256 public endReleaseTimestamp;

    /* ========== INITIALIZER ========== */

    function initialize(address _GRV, uint256 _startReleaseTimestamp, uint256 _endReleaseTimestamp) external initializer {
        require(_startReleaseTimestamp > block.timestamp, "Vesting: invalid startReleaseTimestamp");
        require(_endReleaseTimestamp > _startReleaseTimestamp, "Vesting: invalid endReleaseTimestamp");

        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

        GRV = _GRV;
        startReleaseTimestamp = _startReleaseTimestamp;
        endReleaseTimestamp = _endReleaseTimestamp;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function depositToken() external onlyOwner {
        GRV.safeTransferFrom(msg.sender, address(this), VESTING_AMOUNT);
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 tokenBalance = IBEP20(GRV).balanceOf(address(this));
        GRV.safeTransfer(msg.sender, tokenBalance);
    }

    function setUserShare(address[] calldata _users, uint256[] calldata _userShares) external onlyOwner {
        require(_users.length == _userShares.length, "Vesting: invalid userShares length");
        for (uint256 i = 0; i < _userShares.length; i++) {
            userShare[_users[i]] = _userShares[i];
            if (lastUnlockTimestamp[_users[i]] < startReleaseTimestamp) {
                lastUnlockTimestamp[_users[i]] = startReleaseTimestamp;
            }
        }
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function withdrawTokens() external override nonReentrant {
        uint256 _tokensToClaim = tokensClaimable(msg.sender);
        require(_tokensToClaim > 0, "Vesting: No tokens to claim");
        claimed[msg.sender] = claimed[msg.sender].add(_tokensToClaim);

        GRV.safeTransfer(msg.sender, _tokensToClaim);
        lastUnlockTimestamp[msg.sender] = block.timestamp;
    }

    /* ========== VIEWS ========== */

    function tokensClaimable(address _user) public view override returns (uint256 claimableAmount) {
        if (userShare[_user] == 0) {
            return 0;
        }
        uint256 unclaimedTokens = IBEP20(GRV).balanceOf(address(this));
        claimableAmount = _getTokenAmount(_user);
        claimableAmount = claimableAmount.sub(claimed[_user]);

        claimableAmount = _canUnlockAmount(_user, claimableAmount);

        if (claimableAmount > unclaimedTokens) {
            claimableAmount = unclaimedTokens;
        }
    }

    function tokensLockable(address _user) public view override returns (uint256 lockableAmount) {
        if (userShare[_user] == 0) {
            return 0;
        }
        uint256 unclaimedTokens = IBEP20(GRV).balanceOf(address(this));
        lockableAmount = _getTokenAmount(_user);
        lockableAmount = lockableAmount.sub(claimed[_user]);

        if (lockableAmount > unclaimedTokens) {
            lockableAmount = unclaimedTokens;
        }
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _allocationOf(address _user) private view returns (uint256) {
        if (TOTAL_SHARE == 0) {
            return 0;
        } else {
            return userShare[_user].mul(1e18).div(TOTAL_SHARE);
        }
    }

    function _getTokenAmount(address _user) private view returns (uint256) {
        if (TOTAL_SHARE == 0) {
            return 0;
        }
        return VESTING_AMOUNT.mul(_allocationOf(_user)).div(1e18);
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

