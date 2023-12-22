pragma solidity >=0.7.0 <0.9.0;
// SPDX-License-Identifier: UNLICENSED

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Pausable.sol";
import "./Ownable.sol";

contract PledgeRewardManager is Ownable, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public token;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public lastClaim;
    mapping(uint256 => address) public idToUser;
    mapping(address => uint256) public userToId;
    mapping(address => bool) public hasId;

    uint256 public nextId = 0; // Start from 0, as 0 is default value in mapping

    event RewardCreated(
        uint256 indexed allocationId,
        address indexed user,
        uint256 amount
    );
    event RewardClaimed(address indexed user, uint256 amount);
    event ContractPaused(address indexed owner);
    event ContractUnpaused(address indexed owner);

    constructor(IERC20 _token) {
        token = _token;
    }

    function createReward(
        address user,
        uint256 amount
    ) public whenNotPaused onlyOwner {
        require(user != address(0), "Invalid user address");
        require(amount >= 0, "Reward amount must not be negative");

        if (!hasId[user]) {
            userToId[user] = nextId;
            idToUser[nextId] = user;
            hasId[user] = true;
            nextId++;
        }

        rewards[user] = rewards[user].add(amount);
        emit RewardCreated(userToId[user], user, amount);
    }

    function claimReward(address userAddress) public whenNotPaused {
        require(
            userAddress == msg.sender,
            "You can only claim your own rewards"
        );

        uint256 timeElapsed = block.timestamp - lastClaim[msg.sender];
        require(timeElapsed > 1 days, "You can only claim once per day");

        uint256 rewardAmount = rewards[userAddress];
        require(rewardAmount > 0, "No rewards to claim");

        require(
            token.balanceOf(address(this)) >= rewardAmount,
            "Insufficient contract balance to fulfill the reward"
        );

        rewards[userAddress] = 0;
        lastClaim[msg.sender] = block.timestamp;
        token.safeTransfer(userAddress, rewardAmount);
        emit RewardClaimed(userAddress, rewardAmount);
    }

    function rewardBalance(address user) public view returns (uint256) {
        return rewards[user];
    }

    function pause() public onlyOwner {
        _pause();
        emit ContractPaused(msg.sender);
    }

    function unpause() public onlyOwner {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }
}
