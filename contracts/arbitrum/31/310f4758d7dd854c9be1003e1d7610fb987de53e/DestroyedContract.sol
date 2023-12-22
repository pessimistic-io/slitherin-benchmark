// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.19;

import "./UpgradeableBase.sol";

contract DestroyedContract is UpgradeableBase(0)
{
    bool public constant isREBacking = true;
    bool public constant isREClaimer = true;
    bool public constant isRECurveBlargitrage = true;
    bool public constant isRECurveMintedRewards = true;
    bool public constant isRECurveZapper = true;
    bool public constant isRECustodian = true;
    bool public constant isREStablecoins = true;
    bool public constant isREUSDMinter = true;
    bool public constant isREWardSplitter = true;

    function checkUpgradeBase(address newImplementation) internal override view {}
    function initialize() public pure {}
}
