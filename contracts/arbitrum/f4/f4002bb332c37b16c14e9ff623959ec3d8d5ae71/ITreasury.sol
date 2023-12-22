// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITreasury {

    function isBridgeWorldPowered() external view returns(bool);

    function forwardCoinsToMine(uint256 _totalMagicSent) external;
}
