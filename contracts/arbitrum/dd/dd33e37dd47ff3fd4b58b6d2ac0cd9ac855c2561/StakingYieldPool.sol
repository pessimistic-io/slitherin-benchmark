// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity =0.8.18;

import "./Math.sol";
import "./SafeERC20.sol";
import "./OwnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";

import "./IRewardTracker.sol";
import "./IMintableToken.sol";

contract StakingYieldPool is UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 public rewardToken;
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
    event UpdateStaked(address indexed user, uint256 oldAmount, uint256 newAmount);
    event RewardPaid(address indexed user, uint256 reward);

    address public basePool;
    address public manager;

    // IMintableToken public esAcid;
    // mapping(address => uint) public lastEsAcidBalance;

    constructor() initializer {}

    function initialize(address reward_, address basePool_/** , IMintableToken esAcid_*/) external initializer {
        __Ownable_init();
        duration = 30 days;
        rewardToken = IERC20(reward_);
        basePool = basePool_;
        // esAcid = esAcid_;
    }

    function setManager(address _manager) external onlyOwner {
        manager = _manager;
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

    function updateStaked(address _account, uint256 newAmount) external {
        require(msg.sender == address(basePool), "!authorized");
        getReward(_account);
        // _checkEsAcid(_account);

        uint oldStaked = balanceOf[_account];
        totalSupply -= oldStaked;
        newAmount = IRewardTracker(basePool).stakedAmount(_account);
        balanceOf[_account] = newAmount;
        totalSupply += newAmount;

        emit UpdateStaked(_account, oldStaked, newAmount);
    }

    // function _checkEsAcid(address _account) internal {
    //     if (lastEsAcidBalance[_account] == 0) {
    //         lastEsAcidBalance[_account] = esAcid.balanceOf(_account);
    //     } else {
    //         uint newBalance = esAcid.balanceOf(_account);
    //         if (newBalance > lastEsAcidBalance[_account]) { // claimed new esAcid
    //             uint diff = newBalance - lastEsAcidBalance[_account];
    //             uint esAcidBurn = diff * IRewardTracker(basePool).stakedAmount(_account) / IRewardTracker(basePool).boostedAmount(_account);
    //             esAcid.burn(_account, esAcidBurn);
    //         }
    //         lastEsAcidBalance[_account] = newBalance;
    //     }
    // }

    function getReward(address _account) internal {
        updateReward(_account);
        uint256 reward = earned(_account);
        if (reward > 0) {
            rewards[_account] = 0;
            rewardToken.safeTransfer(_account, reward);
            emit RewardPaid(_account, reward);
        }
    }

    function getRewardBasePool(address _account) external {
        require(msg.sender == address(basePool), "!authorized");
        getReward(_account);
    }

    function getReward() external {
        getReward(msg.sender);
    }

    function notifyRewardAmount(uint256 _reward) external {
        require(msg.sender == manager, "!authorized");
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

