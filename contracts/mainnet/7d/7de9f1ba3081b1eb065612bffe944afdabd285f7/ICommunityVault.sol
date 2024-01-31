//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;


import "./ERC20.sol";
import "./ICommunityVaultEvents.sol";
import "./V1Migrateable.sol";
import "./IStorageView.sol";
import "./IComputationalView.sol";
import "./IRewardHandler.sol";
import "./IPausable.sol";

interface ICommunityVault is IStorageView, IComputationalView, IRewardHandler, ICommunityVaultEvents, IPausable, V1Migrateable {
    function redeemDXBL(address feeToken, uint dxblAmount, uint minOutAmount, bool unwrapNative) external;
}
