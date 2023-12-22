// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.19;

import "./IBridgeSelfStakingERC20.sol";
import "./ICanMint.sol";
import "./IUpgradeableBase.sol";

interface IREYIELD is IBridgeSelfStakingERC20, ICanMint, IUpgradeableBase
{
    function isREYIELD() external view returns (bool);
    function url() external view returns (string memory);
}
