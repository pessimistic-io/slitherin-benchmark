// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Address.sol";
import "./IGasPrice.sol";

contract GasThrottler {
    bool public shouldGasThrottle = true;

    address public constant gasprice =
        address(0xd7623053054eF6AB56968e0438f4e8deBdda2B79);

    modifier gasThrottle() {
        if (shouldGasThrottle && Address.isContract(gasprice)) {
            require(
                tx.gasprice <= IGasPrice(gasprice).maxGasPrice(),
                "gas is too high!"
            );
        }
        _;
    }
}

