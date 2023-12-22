// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IVault.sol";

interface IVaultsFactory {
    function feeReceiver() external view returns(address);
    function feeBasisPoints() external view returns (uint256);
    function emergencyWithdrawAddress() external view returns (address);

    function unwrapDelay() external view returns (uint256);
    function isPaused(IVault vault) external view returns (bool);
}

