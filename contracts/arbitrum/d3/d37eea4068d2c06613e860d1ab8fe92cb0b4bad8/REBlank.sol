// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.19;

import "./UpgradeableBase.sol";

contract REBlank is UpgradeableBase(999)
{
    bool public constant isBridgeable = true;
    bool public constant isSelfStakingERC20 = true;
    bool public constant isRERC20 = true;

    bool public constant isREBacking = true;
    bool public constant isREClaimer = true;
    bool public constant isRECurveBlargitrage = true;
    bool public constant isRECurveMintedRewards = true;
    bool public constant isRECurveZapper = true;
    bool public constant isRECustodian = true;
    bool public constant isREStablecoins = true;
    bool public constant isREUP = true;
    bool public constant isREUSD = true;
    bool public constant isREYIELD = true;
    bool public constant isREUSDExit = true;
    bool public constant isREUSDMinter = true;
    bool public constant isREWardSplitter = true;

    bool public constant isEthereumExit = true;
    bool public constant isArbitrumMigrator = true;

    function reflected() private view returns (REBlank) { return REBlank(msg.sender); }

    function nameHash() public view returns (bytes32) { return reflected().nameHash(); }
    function rewardToken() public view returns (address) { return reflected().rewardToken(); }

    function checkUpgradeBase(address newImplementation)
        internal
        override
        view
    {
        assert(false);
    }
}
