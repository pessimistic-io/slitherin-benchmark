// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./IStrategy.sol";

interface IShipyardVault {

    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function strategy() external returns (IStrategy);
}
