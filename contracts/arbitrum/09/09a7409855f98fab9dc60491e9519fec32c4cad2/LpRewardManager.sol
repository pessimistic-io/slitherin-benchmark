pragma solidity >=0.7.0 <0.9.0;

import "./IERC20.sol";
import "./SafeMath.sol";
import "./Pausable.sol";
import "./Ownable.sol";

contract LpRewardManager is Ownable, Pausable {
    using SafeMath for uint256;

    IERC20 public token;
    mapping(address => uint256) public rewards;

    event RewardCreated(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);

    constructor(IERC20 _token) {
        token = _token;
    }

    function createReward(address user, uint256 amount) public whenNotPaused onlyOwner {
        require(token.balanceOf(address(this)) >= amount, "Not enough tokens in contract");
        rewards[user] = rewards[user].add(amount);
        emit RewardCreated(user, amount);
    }

    function claimReward(uint256 amount) public whenNotPaused {
        require(rewards[msg.sender] >= amount, "Not enough rewards to claim");
        uint256 previousBalance = rewards[msg.sender];
        rewards[msg.sender] = rewards[msg.sender].sub(amount);
        token.transfer(msg.sender, amount);
        assert(rewards[msg.sender] == previousBalance - amount);
        emit RewardClaimed(msg.sender, amount);
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

