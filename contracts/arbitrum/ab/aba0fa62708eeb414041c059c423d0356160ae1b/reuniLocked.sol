//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import "./SafeERC20.sol";

contract lockedReuni {
    using SafeERC20 for IERC20;
    
    /**
    REUNI tokens held by this contract are not considered to be in circulation.
    A maximum of 250,000 REUNI can be withdrawn per 30 days, and therefore put into circulation.
    The maximum supply of REUNI is fixed at 10,000,000 and is fragmented across 7 networks:
        - Ethereum
        - Binance Smart Chain
        - Polygon
        - Avalanche
        - Arbitrum
        - Optimism
        - Fantom 
    More information on : https://everywhere.finance
    **/

    address         public      REUNIT_TREASURY;
    address         public      OWNER;
    address         public      REUNI_TOKEN         =   0x9ed7E4B1BFF939ad473dA5E7a218C771D1569456;
    uint256         public      REUNI_DECIMALS      =   1e6;
    uint256         public      AMOUNT_WITHDRAWN    =   250000; // First time : 03/04/2023
    uint256         public      MAXIMUM             =   250000;
    uint256         public      LAST_WITHDRAWAL;

    event unlockedReuni(uint256 timestamp, uint256 amount, address treasury);

    constructor() {  
        OWNER               =   msg.sender;
        LAST_WITHDRAWAL     =   1680472800;     // 03 April 2023
        REUNIT_TREASURY     =   0x3Ef9962A422727D9d70f1d8CFfAc63C0D4ac0fDe;
    }

    function updateTreasury(address reunitTreasury) public {
        require(msg.sender == OWNER, "You are not the owner");
        REUNIT_TREASURY =   reunitTreasury;   
    }

    function transferOwnership(address new_owner) public {
        require(msg.sender == OWNER, "You are not the owner");
        OWNER   =   new_owner;
    }

    function setReuniToken(address token, uint256 decimals) public {
        require(msg.sender == OWNER, "You are not the owner");
        REUNI_TOKEN     =   token;
        REUNI_DECIMALS  =   decimals;
    }

    function unlockReuni(uint256 amount) public {
        require(msg.sender == OWNER, "You are not the owner");
        require(block.timestamp >= (LAST_WITHDRAWAL + 30 days), "You must wait 30 days from the last withdrawal");
        require(amount <= MAXIMUM, "The maximum amount allowed is 250000");

        // Update the amount withdrawn
        AMOUNT_WITHDRAWN += amount;

        // Update the timestamp of the last withdrawal
        LAST_WITHDRAWAL = block.timestamp;

        // Transfer to treasury
        IERC20(REUNI_TOKEN).safeTransfer(REUNIT_TREASURY,amount*REUNI_DECIMALS);

        // Emit
        emit unlockedReuni(block.timestamp, amount, REUNIT_TREASURY);

    }

    // This function should only be used when absolutely necessary
    function emergencyWithdraw(uint256 amount, address token) public {
        require(msg.sender == OWNER, "You are not the owner");
        IERC20(token).safeTransfer(REUNIT_TREASURY,amount);
    }
}
