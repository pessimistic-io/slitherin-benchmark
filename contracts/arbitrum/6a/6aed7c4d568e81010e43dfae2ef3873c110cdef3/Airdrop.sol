// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeMath.sol";

contract Airdrop is Ownable {
    using SafeMath for uint256;

    struct User {
        bool hasClaimed;
        uint256 claimedAmount;
        uint256 referralCounts;
        uint256 referralRewards;
        uint256 referralRewardsClaimed;
    }

    IERC20 public aipoppy;

    uint256 public startTime;
    uint256 public endTime;
    uint256 public amountPerUser;
    uint256 public totalClaimed;
    uint256 public totalAllocation;
    uint256 public referralRate;
    uint256 public guardianQuest;
    address public guardian;

    mapping(address => User) public users;

    constructor(
        IERC20 _aipoppy,
        uint256 _totalAllocation,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _amountPerUser,
        uint256 _referralRate,
        address _guardian,
        uint256 _guardianQuest
    ) {
        aipoppy = _aipoppy;
        totalAllocation = _totalAllocation;
        startTime = _startTime;
        endTime = _endTime;
        amountPerUser = _amountPerUser;
        referralRate = _referralRate;
        guardian = _guardian;
        guardianQuest = _guardianQuest;
    }

    receive() external payable {}

    function claim(address referrer) external payable {
        User storage user = users[msg.sender];
        require(startTime < block.timestamp, "Not started!");
        require(block.timestamp < endTime, "Has ended!");
        require(user.hasClaimed == false, "Has already claimed!");
        require(msg.value >= guardianQuest, "Low guardian quest!");

        aipoppy.transfer(msg.sender, amountPerUser);
        payable(guardian).transfer(msg.value);

        user.hasClaimed = true;
        user.claimedAmount = amountPerUser;
        if (referrer != msg.sender && referrer != address(0)) {
            uint256 referralReward = amountPerUser.mul(referralRate).div(100);
            users[referrer].referralRewards = users[referrer]
                .referralRewards
                .add(referralReward);
            users[referrer].referralCounts = users[referrer].referralCounts.add(1);
            totalAllocation = totalAllocation.add(referralReward);
        }
        totalClaimed = totalClaimed.add(amountPerUser);
    }

    function claimReferralRewards() external {
        User storage user = users[msg.sender];
        uint256 rewards = getClaimableRewards(msg.sender);
        require(rewards > 0, "Nothing to claim!");

        user.referralRewardsClaimed = user.referralRewardsClaimed.add(rewards);
        totalClaimed = totalClaimed.add(rewards);

        aipoppy.transfer(msg.sender, rewards);
    }

    function getClaimableRewards(
        address account
    ) public view returns (uint256) {
        User memory user = users[account];
        return user.referralRewards.sub(user.referralRewardsClaimed);
    }

    function updateAipoppy(IERC20 _aipoppy) external onlyOwner {
        aipoppy = _aipoppy;
    }

    function updateStartTime(uint256 _startTime) external onlyOwner {
        startTime = _startTime;
    }

    function updateEndTime(uint256 _endTime) external onlyOwner {
        endTime = _endTime;
    }

    function updateAmountPerUser(uint256 _amountPerUser) external onlyOwner {
        amountPerUser = _amountPerUser;
    }

    function updateReferralRate(uint256 _referralRate) external onlyOwner {
        referralRate = _referralRate;
    }

    function updateGuardian(address _guardian) external onlyOwner {
        guardian = _guardian;
    }

    function updateGuardianQuest(uint256 _guardianQuest) external onlyOwner {
        guardianQuest = _guardianQuest;
    }

    function withdrawEther(
        address recipient,
        uint256 amount
    ) external onlyOwner {
        require(recipient != address(0), "Is zero address");
        uint256 balance = address(this).balance;
        if (amount > balance) {
            amount = balance;
        }
        payable(recipient).transfer(amount);
    }

    function withdrawTokens(
        address tokenAddress,
        address recipient,
        uint256 amount
    ) external onlyOwner {
        require(recipient != address(0), "Is zero address");
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        if (amount > balance) {
            amount = balance;
        }
        token.transfer(recipient, amount);
    }
}

