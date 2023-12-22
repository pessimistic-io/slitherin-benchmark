// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "./Address.sol";
import "./IGasPrice.sol";

contract GasThrottler {

    bool public shouldGasThrottle = true;

    address public gasprice = address(0x87b2ba49d033372B335B5bAd57fC387577622C58);

    modifier gasThrottle() {
        if (shouldGasThrottle && Address.isContract(gasprice)) {
            require(tx.gasprice <= IGasPrice(gasprice).maxGasPrice(), "gas is too high!");
        }
        _;
    }
}
