// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./ArbotToken.sol";

contract DistributionContract {
    ArbotToken public arbotToken;
    address public owner;
    address public teamAddress;

    mapping(address => uint256) public ethReceived;
    mapping(address => uint256) public arbotReceived;
    mapping(address => bool) public excludedAddresses;
    mapping(address => uint256) public ethClaimable;
    mapping(address => uint256) public arbotClaimable;

 
    mapping(address => uint256) public lastClaimed;

    uint256 public totalEthDistributed;
    uint256 public totalArbotDistributed;


    uint256 public constant MINIMUM_CLAIM_PERIOD = 1 hours;

    constructor() {
        owner = msg.sender;
    }

    function setArbotTokenAddress(address _arbotTokenAddress) external {
        require(msg.sender == owner, "Only owner can set ArbotToken address");
        arbotToken = ArbotToken(_arbotTokenAddress);
    }

    function setTeamAddress(address _teamAddress) external {
        require(msg.sender == owner, "Only owner can set team address");
        teamAddress = _teamAddress;
    }

    function excludeAddress(address _address) external {
        require(msg.sender == owner, "Only owner can exclude address");
        excludedAddresses[_address] = true;
    }

    function includeAddress(address _address) external {
        require(msg.sender == owner, "Only owner can include address");
        excludedAddresses[_address] = false;
    }

    function isEligibleToClaim(address _user) public view returns(bool) {
        if(lastClaimed[_user] + MINIMUM_CLAIM_PERIOD < block.timestamp) {
            return true;
        }
        else {
            return false;
        }
    }

    receive() external payable {
        distributeETH();
    }

      function distributeETH() private {
        uint256 teamShare = address(this).balance / 2;
        payable(teamAddress).transfer(teamShare); 
        totalEthDistributed += teamShare; 
       

    uint256 totalSupply = arbotToken.totalSupply();
    uint256 holdersCount = arbotToken.holdersCount();
    for (uint i = 0; i < holdersCount; i++) {
        address holder = arbotToken.holderAtIndex(i);
        if (excludedAddresses[holder]) {
            totalSupply -= arbotToken.balanceOf(holder);
        }
    }
    if (totalSupply == 0) {
        return;
    }
    uint256 value = address(this).balance; 
    for (uint i = 0; i < holdersCount; i++) {
        address holder = arbotToken.holderAtIndex(i);
        if (!excludedAddresses[holder]) {
            uint256 holderBalance = arbotToken.balanceOf(holder);
            uint256 proportion = (holderBalance * (10**18)) / totalSupply;
            uint256 amount = (value * proportion) / (10**18);
            ethClaimable[holder] += amount;
        }
    }
    distributeArbotTokens();
}

function distributeArbotTokens() private {
    uint256 totalSupply = arbotToken.totalSupply();
    uint256 holdersCount = arbotToken.holdersCount();
    for (uint i = 0; i < holdersCount; i++) {
        address holder = arbotToken.holderAtIndex(i);
        if (excludedAddresses[holder]) {
            totalSupply -= arbotToken.balanceOf(holder);
        }
    }
    if (totalSupply == 0) {
        return;
    }
    uint256 value = arbotToken.balanceOf(address(this));
    for (uint i = 0; i < holdersCount; i++) {
        address holder = arbotToken.holderAtIndex(i);
        if (!excludedAddresses[holder]) {
            uint256 holderBalance = arbotToken.balanceOf(holder);
            uint256 proportion = (holderBalance * (10**18)) / totalSupply;
            uint256 amount = (value * proportion) / (10**18);
            arbotClaimable[holder] += amount;
        }
    }
}


    function claim() external {
        require(isEligibleToClaim(msg.sender), "Cannot claim yet");
        require(msg.sender != teamAddress, "Team cannot claim");
        uint256 ethAmount = ethClaimable[msg.sender];
        uint256 arbotAmount = arbotClaimable[msg.sender];
        require(ethAmount > 0 || arbotAmount > 0, "Nothing to claim");
        if (ethAmount > 0) {
            ethClaimable[msg.sender] = 0;
            payable(msg.sender).transfer(ethAmount);
            totalEthDistributed += ethAmount; 
        }
        if (arbotAmount > 0) {
            arbotClaimable[msg.sender] = 0;
            arbotToken.transfer(msg.sender, arbotAmount);
            totalArbotDistributed += arbotAmount; 
            
        }
        lastClaimed[msg.sender] = block.timestamp;
    }

function getTotalEthDistributed() external view returns (uint256) {
        return totalEthDistributed;
    }

    function getTotalArbotDistributed() external view returns (uint256) {
        return totalArbotDistributed;
    }
}
