// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";
import "./Ownable2StepUpgradeable.sol";

contract LodestarChef is Ownable2StepUpgradeable {
    uint256 private constant MUL_CONSTANT = 1e14;
    IERC20Upgradeable public stakingToken;
    IERC20Upgradeable public weth;
    bool public isInitialized;

    // Info of each user.
    struct UserInfo {
        uint96 amount; // Staking tokens the user has provided
        int128 wethRewardsDebt;
    }

    uint256 public wethPerSecond;
    uint128 public eccWethPerShare;
    uint96 private shares; // total staked
    uint32 public lastRewardSecond;

    mapping(address => UserInfo) public userInfo;

    function LodestarChef__init(address _stakingToken, address _weth, uint32 _rewardEmissionStart) internal {
        stakingToken = IERC20Upgradeable(_stakingToken);
        weth = IERC20Upgradeable(_weth);
        lastRewardSecond = _rewardEmissionStart;
    }

    function deposit(uint96 _amount) internal {
        _isEligibleSender();
        _deposit(msg.sender, _amount);
    }

    function withdraw(uint96 _amount) internal {
        _isEligibleSender();
        _withdraw(msg.sender, _amount);
    }

    function harvest() internal {
        _isEligibleSender();
        _harvest(msg.sender);
    }

    /**
     * Withdraw without caring about rewards. EMERGENCY ONLY.
     */
    function emergencyWithdraw() external {
        _isEligibleSender();
        UserInfo storage user = userInfo[msg.sender];

        uint96 _amount = user.amount;

        user.amount = 0;
        user.wethRewardsDebt = 0;

        if (shares >= _amount) {
            shares -= _amount;
        } else {
            shares = 0;
        }

        stakingToken.transfer(msg.sender, _amount);
        emit EmergencyWithdraw(msg.sender, _amount);
    }

    /**
    Keep reward variables up to date. Ran before every mutative function.
   */
    function updateShares() public {
        // if block.timestamp <= lastRewardSecond, already updated.
        if (block.timestamp <= lastRewardSecond) {
            return;
        }

        // if pool has no supply
        if (shares == 0) {
            lastRewardSecond = uint32(block.timestamp);
            return;
        }

        unchecked {
            eccWethPerShare += rewardPerShare(wethPerSecond);
        }

        lastRewardSecond = uint32(block.timestamp);
    }

    /** VIEWS */

    /**
    Calculates the reward per share since `lastRewardSecond` was updated
  */
    function rewardPerShare(uint256 _rewardRatePerSecond) public view returns (uint128) {
        // duration = block.timestamp - lastRewardSecond;
        // tokenReward = duration * _rewardRatePerSecond;
        // tokenRewardPerShare = (tokenReward * MUL_CONSTANT) / shares;

        unchecked {
            return uint128(((block.timestamp - lastRewardSecond) * _rewardRatePerSecond * MUL_CONSTANT) / shares);
        }
    }

    /**
    View function to see pending rewards on frontend
   */
    function pendingRewards(address _user) external view returns (uint256 _pendingweth) {
        uint256 _wethPS = eccWethPerShare;

        if (block.timestamp > lastRewardSecond && shares != 0) {
            _wethPS += rewardPerShare(wethPerSecond);
        }

        UserInfo memory user = userInfo[_user];

        _pendingweth = _calculatePending(user.wethRewardsDebt, _wethPS, user.amount);
    }

    /** PRIVATE */
    function _isEligibleSender() internal view {
        if (msg.sender != tx.origin) revert UNAUTHORIZED();
    }

    function _calculatePending(
        int128 _rewardDebt,
        uint256 _accPerShare, // Stay 256;
        uint96 _amount
    ) internal pure returns (uint128) {
        if (_rewardDebt < 0) {
            return uint128(_calculateRewardDebt(_accPerShare, _amount)) + uint128(-_rewardDebt);
        } else {
            return uint128(_calculateRewardDebt(_accPerShare, _amount)) - uint128(_rewardDebt);
        }
    }

    function _calculateRewardDebt(uint256 _eccWethPerShare, uint96 _amount) internal pure returns (uint256) {
        unchecked {
            return (_amount * _eccWethPerShare) / MUL_CONSTANT;
        }
    }

    function _safeTokenTransfer(IERC20Upgradeable _token, address _to, uint256 _amount) internal {
        uint256 bal = _token.balanceOf(address(this));

        if (_amount > bal) {
            _token.transfer(_to, bal);
        } else {
            _token.transfer(_to, _amount);
        }
    }

    function _deposit(address _user, uint96 _amount) private {
        UserInfo storage user = userInfo[_user];
        if (_amount == 0) revert DEPOSIT_ERROR();
        updateShares();

        uint256 _prev = stakingToken.balanceOf(address(this));

        unchecked {
            user.amount += _amount;
            shares += _amount;
        }

        user.wethRewardsDebt = user.wethRewardsDebt + int128(uint128(_calculateRewardDebt(eccWethPerShare, _amount)));

        stakingToken.transferFrom(_user, address(this), _amount);

        unchecked {
            if (_prev + _amount != stakingToken.balanceOf(address(this))) revert DEPOSIT_ERROR();
        }

        emit Deposit(_user, _amount);
    }

    function _withdraw(address _user, uint96 _amount) private {
        UserInfo storage user = userInfo[_user];
        if (user.amount < _amount || _amount == 0) revert WITHDRAW_ERROR();
        updateShares();

        unchecked {
            user.amount -= _amount;
            shares -= _amount;
        }

        user.wethRewardsDebt = user.wethRewardsDebt - int128(uint128(_calculateRewardDebt(eccWethPerShare, _amount)));

        stakingToken.transfer(_user, _amount);
        emit Withdraw(_user, _amount);
    }

    function _harvest(address _user) private {
        updateShares();
        UserInfo storage user = userInfo[_user];

        uint256 wethPending = _calculatePending(user.wethRewardsDebt, eccWethPerShare, user.amount);

        user.wethRewardsDebt = int128(uint128(_calculateRewardDebt(eccWethPerShare, user.amount)));

        _safeTokenTransfer(weth, _user, wethPending);

        emit Harvest(_user, wethPending);
    }

    /** OWNER FUNCTIONS */
    function setStartTime(uint32 _startTime) internal {
        lastRewardSecond = _startTime;
    }

    function setEmission(uint256 _wethPerSecond) internal {
        if (msg.sender == owner()) {
            wethPerSecond = _wethPerSecond;
        } else {
            revert UNAUTHORIZED();
        }
    }

    error DEPOSIT_ERROR();
    error WITHDRAW_ERROR();
    error UNAUTHORIZED();

    event Deposit(address indexed _user, uint256 _amount);
    event Withdraw(address indexed _user, uint256 _amount);
    event Harvest(address indexed _user, uint256 _amount);
    event EmergencyWithdraw(address indexed _user, uint256 _amount);
}

