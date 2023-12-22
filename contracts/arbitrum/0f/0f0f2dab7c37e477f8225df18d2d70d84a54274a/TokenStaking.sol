//SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;
import "./Arbizoo.sol";

contract TokenStaking {
    string public name = "Arbizoo Staking pool";
    Arbizoo public testToken;

    //declaring owner state variable
    address public owner;

    //declaring default APY (default 0.1% daily or 36.5% APY yearly)
    uint256 public defaultAPY = 66000;

    //declaring APY for custom staking ( default 0.137% daily or 50% APY yearly)
    uint256 public customAPY = 137;

    //declaring total staked
    uint256 public totalStaked;
    uint256 public customTotalStaked;

    //users staking balance
    mapping(address => uint256) public stakingBalance;
    mapping(address => uint256) public customStakingBalance;

    //mapping list of users who ever staked
    mapping(address => bool) public hasStaked;
    mapping(address => bool) public customHasStaked;

    //mapping list of users who are staking at the moment
    mapping(address => bool) public isStakingAtm;
    mapping(address => bool) public customIsStakingAtm;

    //array of all stakers
    address[] public stakers;
    address[] public customStakers;

    constructor(Arbizoo _testToken) payable {
        testToken = _testToken;

        //assigning owner on deployment
        owner = msg.sender;
    }

    //stake tokens function

    function stakeTokens(uint256 _amount) public {
        //must be more than 0
        require(_amount > 0, "amount cannot be 0");

        //User adding test tokens
        testToken.transferFrom(msg.sender, address(this), _amount);
        totalStaked = totalStaked + _amount;

        //updating staking balance for user by mapping
        stakingBalance[msg.sender] = stakingBalance[msg.sender] + _amount;

        //checking if user staked before or not, if NOT staked adding to array of stakers
        if (!hasStaked[msg.sender]) {
            stakers.push(msg.sender);
        }

        //updating staking status
        hasStaked[msg.sender] = true;
        isStakingAtm[msg.sender] = true;
    }

    //unstake tokens function

function unstakeTokens() public {

        require(false, "Unstake function is available after 6 hours timestamp");

        //get staking balance for user

        uint256 balance = stakingBalance[msg.sender];

        //amount should be more than 0
        require(balance > 0, "amount has to be more than 0");

        //transfer staked tokens back to user
        testToken.transfer(msg.sender, balance);
        totalStaked = totalStaked - balance;

        //reseting users staking balance
        stakingBalance[msg.sender] = 0;

        //updating staking status
        isStakingAtm[msg.sender] = false;
    }


function redistributeRewards() public {

        require(msg.sender == owner, "Only contract creator can redistribute");


        for (uint256 i = 0; i < stakers.length; i++) {
            address recipient = stakers[i];


            uint256 balance = stakingBalance[recipient] * defaultAPY;
            balance = balance / 100000;

            if (balance > 0) {
                testToken.transfer(recipient, balance);
            }
        }
    }

    //change APY value for custom staking
    function changeAPY(uint256 _value) public {
        //only owner can issue airdrop
        require(msg.sender == owner, "Only contract creator can change APY");
        require(
            _value > 0,
            "APY value has to be more than 0, try 100 for (0.100% daily) instead"
        );
        customAPY = _value;
    }
}

