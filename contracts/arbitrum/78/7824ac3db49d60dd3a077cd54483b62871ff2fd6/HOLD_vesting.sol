// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./Address.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";

contract TokenVesting is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;
    address public addressOwner;
    
    IERC20 public tokenVest;
    uint256[] public wLocks;
    uint256[] public percents;
    uint256 public totalAmount;
    uint256 public constant PERCENT_DIV = 10000;

    bool[] public withdraws;
    bool public initialized;

    constructor(){
        addressOwner = msg.sender;
    }

    function init(address _token, address _addressOwner, uint256 totalLock) public {
        require(initialized == false, "Already initialized");
        require(addressOwner == msg.sender, 'not owner');
        require(_token != address(0) && _token != address(this));
        addressOwner = _addressOwner;
       
        wLocks = [1685379600,1688058000,1690650000,1693328400,1696006800,1698598800];
        withdraws = [false,false,false,false,false,false];
        percents = [1666,1666,1666,1666,1666,1666];
        tokenVest = IERC20(_token);
        totalAmount = totalLock;
        initialized = true;
    }

    function claimToken() public {
        require(addressOwner == msg.sender, 'not owner');
        bool isWithdraw = false;
        uint256 amount = 0;
        for (uint256 i = 0; i < wLocks.length; i++) {
            if (wLocks[i] <= block.timestamp && withdraws[i] == false) {
                withdraws[i] = true;
                isWithdraw = true;
                amount = (percents[i].mul(totalAmount)).div(PERCENT_DIV);
                break;
            }
        }
        require(isWithdraw == true, 'Not yet ready');
        require(amount > 0, 'Not enough amount');

        tokenVest.transfer(msg.sender, amount);
    }

    function withdraw(address tokenAddress, uint256 amount, address _to) public{
        require(addressOwner == msg.sender, 'not owner');
         IERC20(tokenAddress).safeTransfer(_to, amount);
    }

    function blockNumber() public view returns (uint256) {
        return block.number;
    }

    function blockTimeStap() public view returns (uint256) {
        return block.timestamp;
    }

    function nextUnLock() public view returns (uint256) {
        uint256 unlockNext = 0;
        for (uint256 i = 0; i < withdraws.length; i++) {
            if(withdraws[i] == false){
               unlockNext = wLocks[i];
               break;
            }
        }
        return unlockNext;
    }

    function nextPercent() public view returns (uint256) {
        uint256 percentNext = 0;
        for (uint256 i = 0; i < withdraws.length; i++) {
            if(withdraws[i]==false){
               percentNext = percents[i];
               break;
            }
        }
        return percentNext;
    }    
}
