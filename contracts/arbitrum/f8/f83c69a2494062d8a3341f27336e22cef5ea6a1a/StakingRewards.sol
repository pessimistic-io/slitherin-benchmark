// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "./Initializable.sol";
import "./IERC20.sol";
import "./IManekiNeko.sol";

contract StakingRewards is Initializable {

    uint8 public constant KIND_STAKING = 1;
    
    IERC20 public stakingToken;
    IManekiNeko manekineko;

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
    // User address => rewardPerTokenStored
    mapping(address => uint) public userRewardPerTokenPaid;
    // User address => rewards to be claimed
    mapping(address => uint) public rewards;

    // Total staked
    uint public totalSupply;
    // User address => staked amount
    mapping(address => uint) public balanceOf;
    mapping(address => uint256[]) public timeCanWithdraw;
    mapping(address => uint256[]) public amountCanWithdraw;
    event Staking(address from_user, uint256 amount);
    event UnStaking(address from_user, uint256 amount);
    event Withdraw(address from_user, uint256 amount);


    function initialize(address _stakingToken, uint _duration, address _manekineko) public initializer {
        owner = msg.sender;
        stakingToken = IERC20(_stakingToken);
        timeLockToken = 7 days;
        duration = _duration;
        manekineko = IManekiNeko(_manekineko);
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
        balanceOf[msg.sender] += _amount;
        totalSupply += _amount;
        emit Staking(msg.sender, _amount);
    }

    function unstake(uint _amount) external updateReward(msg.sender) {
        require(_amount > 0, "amount = 0");

        balanceOf[msg.sender] -= _amount;
        totalSupply -= _amount;
        timeCanWithdraw[msg.sender].push(block.timestamp + timeLockToken);
        amountCanWithdraw[msg.sender].push(_amount);
        emit UnStaking(msg.sender, _amount);
    }

    function withdraw(uint _index) external {
        require(timeCanWithdraw[msg.sender][_index] < block.timestamp, "Can not withdraw now!");
        require(amountCanWithdraw[msg.sender][_index] > 0, "Withdrawed !");
        uint amount = amountCanWithdraw[msg.sender][_index];
        amountCanWithdraw[msg.sender][_index] = 0;
        stakingToken.transfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
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
            manekineko.claimTokenomic(KIND_STAKING, msg.sender, reward);
        }
    }

    function setRewardsDuration(uint _duration) external onlyOwner {
        require(finishAt < block.timestamp, "reward duration not finished");
        duration = _duration;
    }

    function setTimeLockToken(uint256 _timeLockToken) external onlyOwner {
        timeLockToken = _timeLockToken;
    }

    function setTimeCanWithdraw(address _address, uint256 _index, uint256 _timeWithdraw) external onlyOwner {
        timeCanWithdraw[_address][_index] = _timeWithdraw;
    }

    function getTimeCanWithdrawLength(address _user) public view returns (uint){
        return timeCanWithdraw[_user].length;
    }

    function getAmountCanWithdrawLength(address _user) public view returns (uint){
        return amountCanWithdraw[_user].length;
    }

    function getTotalAmountWaitingWithdraw(address _user) public view returns (uint){
        uint totalAmount = 0;
        for (uint i=0; i< amountCanWithdraw[_user].length; i++) {
            totalAmount+= amountCanWithdraw[_user][i];
        }
        return totalAmount;
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

        finishAt = block.timestamp + duration;
        updatedAt = block.timestamp;
    }

    function _min(uint x, uint y) private pure returns (uint) {
        return x <= y ? x : y;
    }
}
