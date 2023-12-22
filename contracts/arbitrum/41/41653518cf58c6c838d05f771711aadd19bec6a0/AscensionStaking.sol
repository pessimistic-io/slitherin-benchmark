// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./AscensionStakedToken.sol";

/*
    :::      ::::::::   ::::::::  :::::::::: ::::    :::  :::::::: ::::::::::: ::::::::  ::::    :::
  :+: :+:   :+:    :+: :+:    :+: :+:        :+:+:   :+: :+:    :+:    :+:    :+:    :+: :+:+:   :+:
 +:+   +:+  +:+        +:+        +:+        :+:+:+  +:+ +:+           +:+    +:+    +:+ :+:+:+  +:+
+#++:++#++: +#++:++#++ +#+        +#++:++#   +#+ +:+ +#+ +#++:++#++    +#+    +#+    +:+ +#+ +:+ +#+
+#+     +#+        +#+ +#+        +#+        +#+  +#+#+#        +#+    +#+    +#+    +#+ +#+  +#+#+#
#+#     #+# #+#    #+# #+#    #+# #+#        #+#   #+#+# #+#    #+#    #+#    #+#    #+# #+#   #+#+#
###     ###  ########   ########  ########## ###    ####  ######## ########### ########  ###    ####
:::::::::  :::::::::   :::::::: ::::::::::: ::::::::   ::::::::   ::::::::  :::
:+:    :+: :+:    :+: :+:    :+:    :+:    :+:    :+: :+:    :+: :+:    :+: :+:
+:+    +:+ +:+    +:+ +:+    +:+    +:+    +:+    +:+ +:+        +:+    +:+ +:+
+#++:++#+  +#++:++#:  +#+    +:+    +#+    +#+    +:+ +#+        +#+    +:+ +#+
+#+        +#+    +#+ +#+    +#+    +#+    +#+    +#+ +#+        +#+    +#+ +#+
#+#        #+#    #+# #+#    #+#    #+#    #+#    #+# #+#    #+# #+#    #+# #+#
###        ###    ###  ########     ###     ########   ########   ########  ##########
 */

//copied and modified from Synthetix https://github.com/Synthetixio/synthetix/blob/develop/contracts/StakingRewards.sol
contract AscensionStaking is Ownable, ReentrancyGuard {
    /* ========== STATE VARIABLES ========== */
    IERC20 public immutable token; //the governance token
    AscensionStakedToken public immutable sToken; //sToken represents the tokens users have staked in the pool

    bool public paused; //restricts stake function when paused, users can still withdraw
    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public periodFinish;
    uint256 public rewardsDuration = 365 days;
    uint256 public totalStaked;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) private balances;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _token, address _sToken) {
        token = IERC20(_token);
        sToken = AscensionStakedToken(_sToken);
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address _account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();

        if (_account != address(0)) {
            //update rewards for account
            rewards[_account] = earned(_account);
            //update userRewardPerTokenPaid for account
            userRewardPerTokenPaid[_account] = rewardPerTokenStored;
        }

        _;
    }

    /* ========== FUNCTIONS ========== */

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            (((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * PRECISION_FACTOR) / totalStaked);
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function earned(address _account) public view returns (uint256) {
        return
            ((balances[_account] * (rewardPerToken() - userRewardPerTokenPaid[_account])) / PRECISION_FACTOR) +
            rewards[_account];
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate * rewardsDuration;
    }

    function stake(uint256 _amount) public nonReentrant updateReward(msg.sender) {
        require(_amount > 0, "Cannot stake 0");
        require(!paused, "Staking is currently disabled");
        totalStaked += _amount;
        balances[msg.sender] += _amount;
        token.transferFrom(msg.sender, address(this), _amount);
        sToken.mint(msg.sender, _amount);
        emit Staked(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) public nonReentrant updateReward(msg.sender) {
        require(_amount > 0, "Cannot withdraw 0");
        totalStaked -= _amount;
        balances[msg.sender] -= _amount;
        token.transfer(msg.sender, _amount);
        sToken.burn(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            token.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external {
        withdraw(balances[msg.sender]);
        getReward();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setReward(uint256 _reward) external onlyOwner updateReward(address(0)) {
        if (block.timestamp >= periodFinish) {
            rewardRate = _reward / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (_reward + leftover) / rewardsDuration;
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = token.balanceOf(address(this)) - totalStaked;
        require(rewardRate <= balance / rewardsDuration, "Provided reward too high");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
        emit RewardAdded(_reward);
    }

    // recover wrong tokens
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(token), "Cannot withdraw the staking token");
        IERC20(tokenAddress).transfer(msg.sender, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        require(
            block.timestamp > periodFinish,
            "Previous rewards period must be complete before changing the duration for the new period"
        );
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    function setPaused(bool _state) external onlyOwner {
        paused = _state;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);
}

