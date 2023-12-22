// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.19;

import "./Math.sol";
import "./SafeERC20.sol";
import "./OwnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";

contract StakingYieldPool is UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 public rewardToken;
    IERC20 public stakingToken;
    uint256 public duration;

    uint256 public periodFinish;
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public historicalRewards;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    mapping(address => uint256) public balanceOf;
    uint public totalSupply;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    mapping(address => bool) public manager;

    constructor() initializer {}

    function initialize(IERC20 stakingToken_, IERC20 reward_, uint256 duration_) external initializer {
        __Ownable_init();
        duration = duration_;
        rewardToken = reward_;
        stakingToken = stakingToken_;
    }

    function setManager(address _manager, bool _status) external onlyOwner {
        manager[_manager] = _status;
    }

    function updateReward(address account) internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / totalSupply;
    }

    function earned(address account) public view returns (uint256) {
        return (balanceOf[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18 + rewards[account];
    }

    function stake(uint256 amount) external {
        require(amount > 0, "Cannot stake 0");
        updateReward(msg.sender);
        uint previousBalance = stakingToken.balanceOf(address(this));
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        // fee-on-transfer
        amount = stakingToken.balanceOf(address(this)) - previousBalance;
        totalSupply += amount;
        balanceOf[msg.sender] += amount;
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public {
        require(amount > 0, "Cannot withdraw 0");
        updateReward(msg.sender);
        totalSupply -= amount;
        balanceOf[msg.sender] -= amount;
        // don't think about fees because we are transfering out
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public {
        updateReward(msg.sender);
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external {
        withdraw(balanceOf[msg.sender]);
        getReward();
    }

    function notifyRewardAmount(uint256 _reward) external {
        require(manager[msg.sender], "!authorized");
        updateReward(address(0));
        historicalRewards += _reward;
        if (block.timestamp >= periodFinish) {
            rewardRate = _reward / duration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (_reward + leftover) / duration;
        }

        uint balance = rewardToken.balanceOf(address(this));
        require(rewardRate <= balance / duration, "Provided reward too high");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + duration;
        emit RewardAdded(_reward);
    }

    function setRewardDuartion(uint256 _duration) external onlyOwner {
        duration = _duration;
    }

    function recoverToken(address[] calldata tokens) external onlyOwner {
        unchecked {
            for (uint8 i; i < tokens.length; i++) {
                IERC20(tokens[i]).safeTransfer(msg.sender, IERC20(tokens[i]).balanceOf(address(this)));
            }
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

