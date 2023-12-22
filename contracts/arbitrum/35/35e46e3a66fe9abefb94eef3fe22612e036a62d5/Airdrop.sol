// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeMath.sol";


// temp: set cap to 1 billion ether
contract Airdrop is Ownable {
    using SafeMath for uint256;

    struct User{
        bool claimable;
        bool claimed;
        uint256 claimedAmount;
        uint256 referralCounts;
        uint256 referralRewards;
        uint256 referralRewardsClaimed;
    }

    IERC20 public sourceToken;

    uint256 public startTime;
    uint256 public endTime;
    uint256 public airdropAmount = 42_000_000 * 10**18;
    uint256 public totalClaimed;
    uint256 public totalAirdrop;
    uint256 public referralRate = 30;

    mapping(address => User) public users;


    constructor(IERC20 _sourceToken, uint256 _startTime, uint256 _endTime){
        sourceToken = _sourceToken;
        startTime = _startTime;
        endTime = _endTime;
    }

    function claim(address inviter) public {
        User storage user = users[msg.sender];
        require(startTime < block.timestamp, "Not started!");
        require(block.timestamp < endTime, "Ended!");
        require(user.claimable == true, "not eligible!");
        require(user.claimed == false, "already claimed!");
        sourceToken.transfer(msg.sender, airdropAmount);

        user.claimed = true;
        user.claimedAmount = airdropAmount;
        if(users[inviter].claimable && inviter != msg.sender){
            uint256 refAmount = airdropAmount.mul(referralRate).div(100);
            users[inviter].referralRewards = users[inviter].referralRewards.add(refAmount);
            users[inviter].referralCounts = users[inviter].referralCounts.add(1);
            totalAirdrop = totalAirdrop.add(refAmount);
        }
        totalClaimed = totalClaimed.add(airdropAmount);
    }

    function claimReferral() public {
        User storage user = users[msg.sender];
        uint256 rewards = refRewardsClaimable(msg.sender);
        require(rewards > 0, "Nothing to claim!");

        user.referralRewardsClaimed = user.referralRewardsClaimed.add(rewards);
        totalClaimed = totalClaimed.add(rewards);

        sourceToken.transfer(msg.sender, rewards);
    }

    function refRewardsClaimable(address addr) public view returns(uint256) {
        User memory user = users[msg.sender];
        return user.referralRewards.sub(user.referralRewardsClaimed);
    }



    function setWhitelist(address[] memory list) onlyOwner public {
        for(uint256 i = 0; i < list.length; i++){
            if(!users[list[i]].claimed){
                users[list[i]].claimable= true;
            }
        }
        totalAirdrop = totalAirdrop.add(airdropAmount.mul(list.length));
    }


    function transferBack(address token, uint256 amount) onlyOwner public {
        if(token == address(0)){
            msg.sender.transfer(amount);
        }
        else{
            IERC20(token).transfer(msg.sender, amount);
        }
    }

    function updateStartTime(uint256 _startTime) onlyOwner public{
        startTime = _startTime;
    }

    function updateEndTime(uint256 _endTime) onlyOwner public{
        endTime = _endTime;
    }

    function updateAirdropAmount(uint256 _airdropAmount) onlyOwner public{
        airdropAmount = _airdropAmount;
    }

    function updateReferralRate(uint256 _rate) onlyOwner public{
        referralRate = _rate;
    }

}
