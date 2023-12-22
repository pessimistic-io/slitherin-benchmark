// SPDX-License-Identifier: MIT

pragma solidity^0.8.16;

import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

contract StakingPool is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 private immutable tokenContract;

    mapping(address => uint256) public amountStaked;
    mapping(address => uint256) public stakingReward;
    mapping(address => uint256) public timeOfStaking;

    uint256 public distributionInterval = 7 days;
    uint256 public totalAmountStaked;
    uint256 public timeOfLastDistribution;

    uint256 public totalStakingReward;

    bool public isLive = false;

    address[] private stakers;

    event Deposit(address indexed user, uint256 amount, uint256 timestamp);
    event Withdrawal(address indexed user, uint256 amount, uint256 timestamp);
    event Claim(address indexed user, uint256 amount, uint256 timestamp);
    event DistributedReward(uint256 amount, uint256 timestamp);

    constructor(address _token) {
        tokenContract = IERC20(_token);
    }

    modifier _isLive() {
        require(isLive,"Contract is not live");
        _;
    }

    function deposit(uint256 _amount) external _isLive {
        address caller = msg.sender;
        uint256 blockTime;
        require(_amount > 0 && _amount <= tokenContract.balanceOf(caller), "Insufficient token balance");
        tokenContract.safeTransfer(address(this), _amount);
        amountStaked[caller] += _amount;
        timeOfStaking[caller] = blockTime;
        totalAmountStaked += _amount;
        stakers.push(caller);

        emit Deposit(caller, _amount, blockTime);
    }

    function setTotalStakingReward(uint256 _amount) external onlyOwner{
        totalStakingReward += _amount;
    }

    function setDisInterval(uint256 _duration) external onlyOwner {
        distributionInterval = _duration * 1 days;
    }

    function withdraw() external _isLive nonReentrant() {
        address caller = msg.sender;
        uint256 userAmountStaked = amountStaked[caller];
        require(userAmountStaked > 0, "You have no staked tokens to withdraw");
        uint256 userReward = stakingReward[caller];
        
        uint256 amountToWithdraw;
        if(userReward > 0) {
            amountToWithdraw = userReward.add(userAmountStaked);
        } else {
            amountToWithdraw = userAmountStaked;
        }
        amountStaked[caller] = 0;
        timeOfStaking[caller] = 0;
        stakingReward[caller] = 0;

        tokenContract.safeTransfer(caller, amountToWithdraw);
        emit Withdrawal(caller, amountToWithdraw, block.timestamp);
    }


    function claimReward() external _isLive nonReentrant() {
        uint256 userReward = stakingReward[msg.sender];
        require(userReward > 0, "You have no reward to claim yet");

        stakingReward[msg.sender] = 0;

        tokenContract.safeTransfer(msg.sender, userReward);
        emit Claim(msg.sender, userReward, block.timestamp);
    }

    function distributeReward() external onlyOwner {
        uint256 interval = distributionInterval;
        uint256 blockTime = block.timestamp;
        require(timeOfLastDistribution + blockTime >= interval, "Wait for 7 days");
        uint256 totalRewardBeforeDis = totalStakingReward;

        for(uint256 i = 0; i < stakers.length; i++) {
            address user = stakers[i];
            uint256 userAmount = amountStaked[user]; 
            uint256 userTime = timeOfStaking[user];
            uint256 userReward = ((userAmount.div(totalAmountStaked)).mul(totalRewardBeforeDis)).mul(userTime.div(interval));
            timeOfStaking[user] = blockTime;
            stakingReward[user] += userReward;
        }

        timeOfLastDistribution = blockTime;
        totalStakingReward = 0;
        emit DistributedReward(totalRewardBeforeDis, blockTime);
    }

    function withdrawTokens() external onlyOwner nonReentrant() {
        uint256 balance = tokenContract.balanceOf(address(this));
        require(balance > 0, "No tokens to withdraw");
        tokenContract.safeTransfer(msg.sender, balance);
    }

}
