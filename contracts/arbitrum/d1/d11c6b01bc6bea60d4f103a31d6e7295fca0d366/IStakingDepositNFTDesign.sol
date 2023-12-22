// SPDX-License-Identifier: MIT
import "./IUnlimitedStaking.sol";

pragma solidity ^0.8.0;

interface IStakingDepositNFTDesign{
    function buildTokenURI(
        uint tokenId,
        IUnlimitedStaking.UserInfo memory user,
        uint256 pendingRewards,
        uint256 userMultiplier,
        IUnlimitedStaking.EpochInfo memory epoch,
        uint256 currentEpochNumber,
        string memory assetSymbol,
        uint8 numberInputDecimals,
        uint8 numberOutputDecimals
    ) external pure returns (string memory);
}

