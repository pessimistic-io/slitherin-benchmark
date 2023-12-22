// SPDX-License-Identifier: MIT




pragma solidity 0.8.15;

import "./IERC20.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./TEST.sol";
import "./ITEST.sol";


contract TestNodeFarm is Ownable {

    //Emit payment events

    event IERC20TransferEvent(IERC20 indexed token, address to, uint256 amount);
    event IERC20TransferFromEvent(IERC20 indexed token, address from, address to, uint256 amount);

    //SafeMathuse

    using SafeMath for uint256;


    //Variables

    ITEST private test;
    IERC20 private usdc;

    address private pair;
    address public treasury;
    address public dev;
    address private burn;

    uint256 private dailyInterest;
    uint256 private nodeCost;
    uint256 private nodeBase;



    bool public isLive = false;
    uint256 totalNodes = 0;

    //Array

    address [] public farmersAddresses;

    //Farmers Struct

    struct Farmer {
        bool exists;
        uint256 testNodes;
        uint256 lastUpdate;
        
    }

    //Mappings

    mapping(address => Farmer) private farmers;

    //Constructor

    constructor (
        address _test,        //Address of the $TEST token to use in the platform
        address _usdc,          //Address of USDC stablecoin
        address _pair,          //Address of the liquidity pool 
        address _treasury,      //Address of a treasury wallet to hold fees and taxes
        uint256 _nodeCost      //Cost of a node in $TEST  
    ) {
        test = ITEST(_test);
        usdc = IERC20(_usdc);
        pair = _pair;
        treasury = _treasury;
        nodeCost = _nodeCost.mul(1e18);
        nodeBase = SafeMath.mul(10, 1e18);
    }

    //Price Checking Functions

    function getTestBalance() external view returns (uint256) {
	return test.balanceOf(pair);
    }

    function getUSDCBalance() external view returns (uint256) {
	return usdc.balanceOf(pair);
    }

    function getPrice() public view returns (uint256) {
        uint256 testBalance = test.balanceOf(pair);
        uint256 usdcBalance = usdc.balanceOf(pair);
        require(testBalance > 0, "divison by zero error");
        uint256 price = usdcBalance.mul(1e30).div(testBalance);
        return price;
    }

    
    //Set Addresses

    function setTreasuryAddr(address treasuryAddress) public onlyOwner {
        treasury = treasuryAddress;
    }
    function setTestAddr(address testaddress) public onlyOwner {
        test = ITEST(testaddress);
    }

    //Platform Settings

    function setPlatformState(bool _isLive) public onlyOwner {
        isLive = _isLive;
    }


    //Node management - Buy - Claim - Bond - User front

    function buyNode(uint256 _amount) external payable {  
        require(isLive, "Platform is offline");
        uint256 nodesOwned = farmers[msg.sender].testNodes + _amount;
        require(nodesOwned < 101, "Max Nodes Owned");
        Farmer memory farmer;
        if(farmers[msg.sender].exists){
            farmer = farmers[msg.sender];
        } else {
            farmer = Farmer(true, 0, 0);
            farmersAddresses.push(msg.sender);
        }
        uint256 transactionTotal = nodeCost.mul(_amount);
        uint256 burnAmount = transactionTotal.mul(20).div(100);
        uint256 bribes = transactionTotal.mul(30).div(100);
        uint256 remainingAmount = transactionTotal.sub(burnAmount).sub(bribes);
        test.burn(msg.sender , burnAmount);
        test.transfer( treasury, bribes);
        test.transfer( dev, remainingAmount);
        farmers[msg.sender] = farmer;
        farmers[msg.sender].testNodes += _amount;
        totalNodes += _amount;
    }


    function awardNode(address _address, uint256 _amount) public onlyOwner {
        uint256 nodesOwned = farmers[_address].testNodes  + _amount;
        require(nodesOwned < 101, "Max Rabbits Owned");
        Farmer memory farmer;
        if(farmers[_address].exists){
            farmer = farmers[_address];
        } else {
            farmer = Farmer(true, 0, 0);
            farmersAddresses.push(_address);
        }
        farmers[_address] = farmer;
        
        
        farmers[_address].testNodes += _amount;
        totalNodes += _amount;
        farmers[_address].lastUpdate = block.timestamp;
    }


    //Platform Info


    function getOwnedNodes() external view returns (uint256) {
        uint256 ownedNodes = farmers[msg.sender].testNodes;
        return ownedNodes;
    }

    function getTotalNodes() external view returns (uint256) {
        return totalNodes;
    }

    //SafeERC20 transferFrom 

    function _transferFrom(IERC20 token, address from, address to, uint256 amount) private {
        SafeERC20.safeTransferFrom(token, from, to, amount);

    //Log transferFrom to blockchain
        emit IERC20TransferFromEvent(token, from, to, amount);
    }

}
