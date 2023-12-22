// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./AaveBase.sol";
import "./IAaveGateway.sol";

// https://onthis.xyz
/*
 .d88b.  d8b   db d888888b db   db d888888b .d8888. 
.8P  Y8. 888o  88    88    88   88    88    88   YP 
88    88 88V8o 88    88    88ooo88    88     8bo.   
88    88 88 V8o88    88    88   88    88       Y8b. 
`8b  d8' 88  V888    88    88   88    88    db   8D 
 `Y88P'  VP   V8P    YP    YP   YP Y888888P  8888Y  
*/

contract AaveL2Gateway is AAVEBase {
    address public constant AAVE_ARB_GATEWAY =
        0xB5Ee21786D28c5Ba61661550879475976B707099;
    address public constant AAVE_ARB_POOL_V3 =
        0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    uint16 public constant REF_CODE = 0;

    function depositAaveEth(address receiver) public payable {
        IAaveGateway(AAVE_ARB_GATEWAY).depositETH{value: msg.value}(
            AAVE_ARB_POOL_V3,
            receiver,
            REF_CODE
        );
    }

    receive() external payable {
        depositAaveEth(msg.sender);
    }
}

