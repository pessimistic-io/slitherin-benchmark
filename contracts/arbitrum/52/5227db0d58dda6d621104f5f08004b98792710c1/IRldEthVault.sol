// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IRldBaseVault.sol";

interface IRldEthVault is IRldBaseVault {
    function deposit() external payable;
}

