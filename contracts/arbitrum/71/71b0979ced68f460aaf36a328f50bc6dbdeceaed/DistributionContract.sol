pragma solidity ^0.8.0;

import "./TestToken.sol";

contract DistributionContract {
    TestToken public testToken;
    address public owner;
    address public teamAddress;

    mapping(address => uint256) public ethReceived;
    mapping(address => uint256) public testReceived;
    mapping(address => bool) public excludedAddresses;
    mapping(address => uint256) public ethClaimable;
    mapping(address => uint256) public testClaimable;

 
    mapping(address => uint256) public lastClaimed;

    uint256 public totalEthDistributed;
    uint256 public totalTestDistributed;


    uint256 public constant MINIMUM_CLAIM_PERIOD = 1 hours;

    constructor() {
        owner = msg.sender;
    }

    function setTestTokenAddress(address _testTokenAddress) external {
        require(msg.sender == owner, "Only owner can set TestToken address");
        testToken = TestToken(_testTokenAddress);
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
       

    uint256 totalSupply = testToken.totalSupply();
    uint256 holdersCount = testToken.holdersCount();
    for (uint i = 0; i < holdersCount; i++) {
        address holder = testToken.holderAtIndex(i);
        if (excludedAddresses[holder]) {
            totalSupply -= testToken.balanceOf(holder);
        }
    }
    if (totalSupply == 0) {
        return;
    }
    uint256 value = address(this).balance; 
    for (uint i = 0; i < holdersCount; i++) {
        address holder = testToken.holderAtIndex(i);
        if (!excludedAddresses[holder]) {
            uint256 holderBalance = testToken.balanceOf(holder);
            uint256 proportion = (holderBalance * (10**18)) / totalSupply;
            uint256 amount = (value * proportion) / (10**18);
            ethClaimable[holder] += amount;
        }
    }
    distributeTestTokens();
}

function distributeTestTokens() private {
    uint256 totalSupply = testToken.totalSupply();
    uint256 holdersCount = testToken.holdersCount();
    for (uint i = 0; i < holdersCount; i++) {
        address holder = testToken.holderAtIndex(i);
        if (excludedAddresses[holder]) {
            totalSupply -= testToken.balanceOf(holder);
        }
    }
    if (totalSupply == 0) {
        return;
    }
    uint256 value = testToken.balanceOf(address(this));
    for (uint i = 0; i < holdersCount; i++) {
        address holder = testToken.holderAtIndex(i);
        if (!excludedAddresses[holder]) {
            uint256 holderBalance = testToken.balanceOf(holder);
            uint256 proportion = (holderBalance * (10**18)) / totalSupply;
            uint256 amount = (value * proportion) / (10**18);
            testClaimable[holder] += amount;
        }
    }
}


    function claim() external {
        require(isEligibleToClaim(msg.sender), "Cannot claim yet");
        require(msg.sender != teamAddress, "Team cannot claim");
        uint256 ethAmount = ethClaimable[msg.sender];
        uint256 testAmount = testClaimable[msg.sender];
        require(ethAmount > 0 || testAmount > 0, "Nothing to claim");
        if (ethAmount > 0) {
            ethClaimable[msg.sender] = 0;
            payable(msg.sender).transfer(ethAmount);
            totalEthDistributed += ethAmount; 
        }
        if (testAmount > 0) {
            testClaimable[msg.sender] = 0;
            testToken.transfer(msg.sender, testAmount);
            totalTestDistributed += testAmount; 
            
        }
        lastClaimed[msg.sender] = block.timestamp;
    }

function getTotalEthDistributed() external view returns (uint256) {
        return totalEthDistributed;
    }

    function getTotalTestDistributed() external view returns (uint256) {
        return totalTestDistributed;
    }
}
