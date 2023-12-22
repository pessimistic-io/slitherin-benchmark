pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;
// SPDX-License-Identifier: SimPL-2.0

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Member.sol";

contract CryptoBrainMain is Member {
    
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
	
    event UsdtPledge(address indexed uaddress, uint256 amount);
    event EthPledge(address indexed uaddress, uint256 amount);
    event UsdtRedeem(address indexed uaddress, uint256 amount);
    event EthRedeem(address indexed uaddress, uint256 amount);
    event LpPledge(address indexed token, address indexed uaddress, uint256 amount);
    event LpRedeem(address indexed token, address indexed uaddress, uint256 amount);
    
    struct PledgeInfo {
        uint256 usdtAmount;
        uint256 ethAmount;
        uint256 crblpAmount;
        uint256 czzlpAmount;
    }

    mapping(address => PledgeInfo) public userPledgeInfo;

    function usdtPledge(uint256 amount) public {
        uint8 decimals = ERC20(manager.members("usdt")).decimals();
        require(amount > (10 ** decimals).div(10) , 'not enough usdt pledge');
        IERC20(manager.members("usdt")).transferFrom(msg.sender, address(this), amount);
        userPledgeInfo[msg.sender].usdtAmount += amount;
        emit UsdtPledge(msg.sender, amount);
    }

    function usdtRedeem(uint256 amount) public {
        require(userPledgeInfo[msg.sender].usdtAmount >= amount, 'not enough usdt redeem');
        userPledgeInfo[msg.sender].usdtAmount -= amount;
        IERC20(manager.members("usdt")).transfer(msg.sender, amount);
        emit UsdtRedeem(msg.sender, amount);
    }

    function ethPledge() public payable {
        require(msg.value > 0.1 ether, 'not enough eth pledge');
        userPledgeInfo[msg.sender].ethAmount += msg.value;
        emit EthPledge(msg.sender, msg.value);
    }

    function ethRedeem(uint256 amount) public {
        require(userPledgeInfo[msg.sender].ethAmount >= amount, 'not enough eth redeem');
        require(address(this).balance >= amount, 'pool not enough eth for redeem');
        userPledgeInfo[msg.sender].ethAmount -= amount;
        address payable uaddress = msg.sender;
        uaddress.transfer(amount);
        emit EthRedeem(msg.sender, amount);
    }

    function crbLpPledge(uint256 amount) public {
        uint256 decimals = ERC20(manager.members("crblp")).decimals();
        require(amount > (10 ** decimals).div(10), 'not enough crb lp pledge');
        IERC20(manager.members("crblp")).transferFrom(msg.sender, address(this), amount);
        userPledgeInfo[msg.sender].crblpAmount += amount;
        emit LpPledge(manager.members("crblp"), msg.sender, amount);
    }

    function crbLpRedeem(uint256 amount) public {
        require(userPledgeInfo[msg.sender].crblpAmount >= amount, 'not enough crb lp redeem');
        userPledgeInfo[msg.sender].crblpAmount -= amount;
        IERC20(manager.members("crblp")).transfer(msg.sender, amount);
        emit LpRedeem(manager.members("crblp"), msg.sender, amount);
    }

    function czzLpPledge(uint256 amount) public {
        uint256 decimals = ERC20(manager.members("czzlp")).decimals();
        require(amount > (10 ** decimals).div(10), 'not enough czz lp pledge');
        IERC20(manager.members("czzlp")).transferFrom(msg.sender, address(this), amount);
        userPledgeInfo[msg.sender].czzlpAmount += amount;
        emit LpPledge(manager.members("czzlp"), msg.sender, amount);
    }

    function czzLpRedeem(uint256 amount) public {
        require(userPledgeInfo[msg.sender].czzlpAmount >= amount, 'not enough czz lp redeem');
        userPledgeInfo[msg.sender].czzlpAmount -= amount;
        IERC20(manager.members("czzlp")).transfer(msg.sender, amount);
        emit LpRedeem(manager.members("czzlp"), msg.sender, amount);
    }

}

