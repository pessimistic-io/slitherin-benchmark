// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "./Initializable.sol";
import "./IERC20.sol";

contract StakingRewards is Initializable {
    IERC20 public stakingToken;
    IERC20 public rewardsToken;

    struct LockInfo {
        uint256 amount;
        uint256 timeUnlock;
    }

    address public owner;

    // Duration of rewards to be paid out (in seconds)
    uint public duration;
    // Timestamp of when the rewards finish
    uint public finishAt;
    // Minimum of last updated time and reward finish time
    uint public updatedAt;
    // Reward to be paid out per second
    uint public rewardRate;
    // Sum of (reward rate * dt * 1e18 / total supply)
    uint public rewardPerTokenStored;
    //Time lock token staking
    uint public timeLockToken;
    uint256 public lockRewardTime;
    uint256 public lockRewardPercent;
    //markup poolId
    uint public poolId;
    // User address => rewardPerTokenStored
    mapping(address => uint) public userRewardPerTokenPaid;
    // User address => rewards to be claimed
    mapping(address => uint) public rewards;

    // Total staked
    uint public totalSupply;
    // User address => staked amount
    mapping(address => uint) public balanceOf;
    mapping(address => LockInfo) public lockStakingInfo;
    mapping(address => LockInfo) public lockRewardInfo;
    event Staking(address from_user, uint256 amount, uint poolIdEvent);
    event UnStaking(address from_user, uint256 amount, uint poolIdEvent);
    event Withdraw(address from_user, uint256 amount, uint poolIdEvent);
    event CompoundReward(address from_user, uint256 amount, uint poolIdEvent);

    function initialize(address _stakingToken, address _rewardToken, uint _duration, uint _poolId) public initializer {
        owner = msg.sender;
        stakingToken = IERC20(_stakingToken);
        rewardsToken = IERC20(_rewardToken);
        timeLockToken = 90 days;
        lockRewardTime = 0;
        lockRewardPercent = 0;
        duration = _duration;
        poolId = _poolId;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not authorized");
        _;
    }

    modifier updateReward(address _account) {
        rewardPerTokenStored = rewardPerToken();
        updatedAt = lastTimeRewardApplicable();

        if (_account != address(0)) {
            rewards[_account] = earned(_account);
            userRewardPerTokenPaid[_account] = rewardPerTokenStored;
        }

        _;
    }

    function lastTimeRewardApplicable() public view returns (uint) {
        return _min(finishAt, block.timestamp);
    }

    function rewardPerToken() public view returns (uint) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }

        return
        rewardPerTokenStored +
        (rewardRate * (lastTimeRewardApplicable() - updatedAt) * 1e18) /
        totalSupply;
    }

    function stake(uint _amount) external updateReward(msg.sender) {
        require(_amount > 0, "amount = 0");
        stakingToken.transferFrom(msg.sender, address(this), _amount);
        if(balanceOf[msg.sender] == 0) {
            //if first stake
            lockRewardInfo[msg.sender].timeUnlock = block.timestamp + lockRewardTime;
        }
        balanceOf[msg.sender] += _amount;
        totalSupply += _amount;
        emit Staking(msg.sender, _amount, poolId);
    }

    function unstake(uint _amount) external updateReward(msg.sender) {
        require(_amount > 0, "amount = 0");

        balanceOf[msg.sender] -= _amount;
        totalSupply -= _amount;
        LockInfo storage lockStkInfo = lockStakingInfo[msg.sender];
        lockStkInfo.timeUnlock = block.timestamp + timeLockToken;
        lockStkInfo.amount += _amount;
        emit UnStaking(msg.sender, _amount, poolId);
    }

    function withdraw() external {
        LockInfo storage lockStkInfo = lockStakingInfo[msg.sender];
        require(lockStkInfo.timeUnlock < block.timestamp, "Can not withdraw now!");
        require(lockStkInfo.amount > 0, "Withdrawed !");
        
        uint amount = lockStkInfo.amount;
        lockStkInfo.amount = 0;
        stakingToken.transfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount, poolId);
    }

    function earned(address _account) public view returns (uint) {
        return
        ((balanceOf[_account] *
        (rewardPerToken() - userRewardPerTokenPaid[_account])) / 1e18) +
        rewards[_account];
    }

    function getReward() external updateReward(msg.sender) {
        uint reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            lockRewardInfo[msg.sender].amount += reward * lockRewardPercent / 100 ;
            rewardsToken.transfer(msg.sender, reward * (100-lockRewardPercent) / 100);
        }
    }

    function unlockReward() external {
        LockInfo storage rewardLock = lockRewardInfo[msg.sender];
        require(rewardLock.timeUnlock <= block.timestamp ,"Unlock time invalid!");
        require(rewardLock.amount > 0 ,"Amount is zero!");
        uint amount = rewardLock.amount;
        rewardLock.amount = 0;
        rewardsToken.transfer(msg.sender, amount);
    }

    function compoundReward() external updateReward(msg.sender) {
        uint reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            balanceOf[msg.sender] += reward;
            totalSupply += reward;
            emit CompoundReward(msg.sender, reward, poolId);
        }
    }

    function setRewardsDuration(uint _duration) external onlyOwner {
        require(finishAt < block.timestamp, "reward duration not finished");
        duration = _duration;
    }

    function setTimeLockToken(uint256 _timeLockToken) external onlyOwner {
        timeLockToken = _timeLockToken;
    }

    function notifyRewardAmount(uint _amount)
    external
    onlyOwner
    updateReward(address(0))
    {
        if (block.timestamp >= finishAt) {
            rewardRate = _amount / duration;
        } else {
            uint remainingRewards = (finishAt - block.timestamp) * rewardRate;
            rewardRate = (_amount + remainingRewards) / duration;
        }

//        require(rewardRate > 0, "reward rate = 0");
//        require(
//            rewardRate * duration <= rewardsToken.balanceOf(address(this)),
//            "reward amount > balance"
//        );

        finishAt = block.timestamp + duration;
        updatedAt = block.timestamp;
    }

    function _min(uint x, uint y) private pure returns (uint) {
        return x <= y ? x : y;
    }

    function setLockRewardTime(uint256 _lockRewardTime) external onlyOwner {
        lockRewardTime = _lockRewardTime;
    }

    function setLockRewardPercent(uint256 _lockRewardPercent) external onlyOwner {
        lockRewardPercent = _lockRewardPercent;
    }
}
