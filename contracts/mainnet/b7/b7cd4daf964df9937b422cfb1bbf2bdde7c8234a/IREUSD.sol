// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.17;

import "./IBridgeRERC20.sol";
import "./ICanMint.sol";
import "./IUpgradeableBase.sol";

interface IREUSD is IBridgeRERC20, ICanMint, IUpgradeableBase
{
    function isREUSD() external view returns (bool);
    function url() external view returns (string memory);
}
