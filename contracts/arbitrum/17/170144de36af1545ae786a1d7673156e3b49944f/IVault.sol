// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IVaultsFactory.sol";

interface IVault {
    function emergencyWithdraw(uint256 amount_) external;
}

