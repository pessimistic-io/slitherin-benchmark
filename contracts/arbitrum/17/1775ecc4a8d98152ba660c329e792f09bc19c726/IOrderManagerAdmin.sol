//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IOrderManagerAdminEvents {
    event GasMultiplierSet(uint256 gasMultiplier);
    event GasTipSet(uint256 gasTip);
}

interface IOrderManagerAdmin is IOrderManagerAdminEvents {
    function setGasMultiplier(uint64 gasMultiplier) external;
    function setGasTip(uint64 gasTip) external;
}

