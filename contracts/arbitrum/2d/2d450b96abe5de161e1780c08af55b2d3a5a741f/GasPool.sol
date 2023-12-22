// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./Ownable.sol";

contract GasPool is Ownable {
    // do nothing, as the core contracts have permission to send to and burn from this address

    string public constant NAME = "GasPool";
}

