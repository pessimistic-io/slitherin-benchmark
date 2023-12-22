// SPDX-License-Identifier: MIT

pragma solidity =0.8.10;

import "./IStaking.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

contract Staking is IStaking, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    uint256 public fixedAPY;
    uint public immutable stakingDuration;
    uint public startTime;
    uint public endTime;
    uint private _totalStaked;
    uint internal _precision = 1E6;

    mapping(address => uint) private _staked;
    mapping(address => uint) private _rewardsToClaim;
    mapping(address => uint) private _userStartTime;

    constructor(address _token, uint256 _fixedAPY) {
        stakingDuration = 365 days;
        token = IERC20(_token);
        fixedAPY = _fixedAPY;
    }

    function initialize() external override onlyOwner {
        require(startTime == 0, "Staking has already started");
        startTime = block.timestamp;
        endTime = block.timestamp + stakingDuration;
        emit StartStaking(startTime, endTime);
    }

    function deposit(uint amount) external override {
        require(
            endTime == 0 || endTime > block.timestamp,
            "Staking period ended"
        );
        require(amount > 0, "Amount must be greater than 0");

        if (_userStartTime[_msgSender()] == 0) {
            _userStartTime[_msgSender()] = block.timestamp;
        }

        _updateRewards();

        _staked[_msgSender()] += amount;
        _totalStaked += amount;
        token.safeTransferFrom(_msgSender(), address(this), amount);
        emit Deposit(_msgSender(), amount);
    }

    function withdraw() external override {
        _updateRewards();
        if (_rewardsToClaim[_msgSender()] > 0) {
            _claimRewards();
        }

        _userStartTime[_msgSender()] = 0;
        _totalStaked -= _staked[_msgSender()];
        uint stakedBalance = _staked[_msgSender()];
        _staked[_msgSender()] = 0;
        token.safeTransfer(_msgSender(), stakedBalance);

        emit Withdraw(_msgSender(), stakedBalance);
    }

    function claimRewards() external override {
        _claimRewards();
    }

    function amountStaked(address user) external view override returns (uint) {
        return _staked[user];
    }

    function totalDeposited() external view override returns (uint) {
        return _totalStaked;
    }

    function rewardOf(address user) external view override returns (uint) {
        return _calculateRewards(user);
    }

    function updateFixedAPY(uint256 _fixedAPY) external onlyOwner {
        require(_fixedAPY > 0, "Fixed APY must be greater than 0");
        fixedAPY = _fixedAPY;
    }

    function withdrawLeftOver() external onlyOwner {
        uint contractBalance = token.balanceOf(address(this));
        uint leftOver = contractBalance - (_totalStaked);
        require(leftOver > 0, "No left over to withdraw");
        token.safeTransfer(owner(), leftOver);
    }

    function _calculateRewards(address user) internal view returns (uint) {
        if (startTime == 0 || _staked[user] == 0) {
            return 0;
        }

        return
            (((_staked[user] * fixedAPY) * _elapsedTimeRatio(user)) /
                (_precision * 100)) + _rewardsToClaim[user];
    }

    function _elapsedTimeRatio(address user) internal view returns (uint) {
        bool early = startTime > _userStartTime[user];
        uint _startTime;
        if (endTime > block.timestamp) {
            _startTime = early ? startTime : _userStartTime[user];
            uint timeRemaining = stakingDuration -
                (block.timestamp - startTime);
            return
                (_precision * (stakingDuration - timeRemaining)) /
                stakingDuration;
        }
        _startTime = early
            ? 0
            : stakingDuration - (endTime - _userStartTime[user]);
        return (_precision * (stakingDuration - startTime)) / stakingDuration;
    }

    function _claimRewards() private {
        _updateRewards();

        uint rewardsToClaim = _rewardsToClaim[_msgSender()];
        require(rewardsToClaim > 0, "Nothing to claim");

        _rewardsToClaim[_msgSender()] = 0;
        _safeRewardsTransfer(_msgSender(), rewardsToClaim);
        emit Claim(_msgSender(), rewardsToClaim);
    }

    function _updateRewards() private {
        _rewardsToClaim[_msgSender()] = _calculateRewards(_msgSender());
        _userStartTime[_msgSender()] = (block.timestamp >= endTime)
            ? endTime
            : block.timestamp;
    }

    function _safeRewardsTransfer(address to, uint256 amount) internal {
        uint256 contractBalance = token.balanceOf(address(this));
        if (contractBalance > _totalStaked) {
            uint256 _remainingRewards = contractBalance - _totalStaked;
            if (amount > _remainingRewards) {
                token.safeTransfer(to, _remainingRewards);
            } else {
                token.transfer(to, amount);
            }
        }
    }
}

