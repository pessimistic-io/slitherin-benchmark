// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IRldBaseVault.sol";

interface IRldVault is IRldBaseVault {
    function deposit(uint _amount) external;
}

