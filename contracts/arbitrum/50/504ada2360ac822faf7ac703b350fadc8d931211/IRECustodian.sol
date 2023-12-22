// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.20;

import "./IUpgradeableBase.sol";

interface IRECustodian is IUpgradeableBase
{
    function isRECustodian() external view returns (bool);
    function amountRecovered(address token) external view returns (uint256);
}
