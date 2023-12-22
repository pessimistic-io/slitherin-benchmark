pragma solidity >=0.7.0 <0.9.0;

import "./IERC20.sol";
import "./SafeMath.sol";
import "./Pausable.sol";
import "./Ownable.sol";

contract PledgeRewardManager is Ownable, Pausable {
    using SafeMath for uint256;

    IERC20 public token;
    mapping(address => uint256) public rewards;

    event RewardCreated(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);

    constructor(IERC20 _token) {
        token = _token;
    }

    function createReward(
        address user,
        uint256 amount
    ) public whenNotPaused onlyOwner {
        require(user != address(0), "Invalid user address");
        require(amount > 0, "Reward amount must be greater than zero");
        rewards[user] = rewards[user].add(amount);
        emit RewardCreated(user, amount);
    }

    function claimReward(address userAddress) public whenNotPaused {
        require(
            userAddress == msg.sender,
            "You can only claim your own rewards"
        );

        uint256 rewardAmount = rewards[userAddress];
        require(rewardAmount > 0, "No rewards to claim");

        require(
            token.balanceOf(address(this)) >= rewardAmount,
            "Insufficient contract balance to fulfill the reward"
        );


        rewards[userAddress] = 0;

        
        token.transfer(userAddress, rewardAmount);
        emit RewardClaimed(userAddress, rewardAmount);
    }

    function rewardBalance(address user) public view returns (uint256) {
        return rewards[user];
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}

