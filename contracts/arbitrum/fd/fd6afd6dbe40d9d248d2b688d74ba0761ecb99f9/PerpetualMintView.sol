// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import { PerpetualMintInternal } from "./PerpetualMintInternal.sol";
import { IPerpetualMintView } from "./IPerpetualMintView.sol";
import { PerpetualMintStorage as Storage, TiersData, VRFConfig } from "./Storage.sol";

/// @title PerpetualMintView facet contract
/// @dev contains all externally called view functions
contract PerpetualMintView is PerpetualMintInternal, IPerpetualMintView {
    constructor(address vrf) PerpetualMintInternal(vrf) {}

    /// @inheritdoc IPerpetualMintView
    function accruedConsolationFees()
        external
        view
        returns (uint256 accruedFees)
    {
        accruedFees = _accruedConsolationFees();
    }

    /// @inheritdoc IPerpetualMintView
    function accruedMintEarnings()
        external
        view
        returns (uint256 accruedEarnings)
    {
        accruedEarnings = _accruedMintEarnings();
    }

    /// @inheritdoc IPerpetualMintView
    function accruedProtocolFees() external view returns (uint256 accruedFees) {
        accruedFees = _accruedProtocolFees();
    }

    /// @inheritdoc IPerpetualMintView
    function BASIS() external pure returns (uint32 value) {
        value = _BASIS();
    }

    /// @inheritdoc IPerpetualMintView
    function collectionMintPrice(
        address collection
    ) external view returns (uint256 mintPrice) {
        mintPrice = _collectionMintPrice(
            Storage.layout().collections[collection]
        );
    }

    /// @inheritdoc IPerpetualMintView
    function collectionRisk(
        address collection
    ) external view returns (uint32 risk) {
        risk = _collectionRisk(Storage.layout().collections[collection]);
    }

    /// @inheritdoc IPerpetualMintView
    function consolationFeeBP()
        external
        view
        returns (uint32 consolationFeeBasisPoints)
    {
        consolationFeeBasisPoints = _consolationFeeBP();
    }

    /// @inheritdoc IPerpetualMintView
    function defaultCollectionMintPrice()
        external
        pure
        returns (uint256 mintPrice)
    {
        mintPrice = _defaultCollectionMintPrice();
    }

    /// @inheritdoc IPerpetualMintView
    function defaultCollectionRisk() external pure returns (uint32 risk) {
        risk = _defaultCollectionRisk();
    }

    /// @inheritdoc IPerpetualMintView
    function defaultEthToMintRatio() external pure returns (uint32 ratio) {
        ratio = _defaultEthToMintRatio();
    }

    /// @inheritdoc IPerpetualMintView
    function ethToMintRatio() external view returns (uint256 ratio) {
        ratio = _ethToMintRatio(Storage.layout());
    }

    /// @inheritdoc IPerpetualMintView
    function mintFeeBP() external view returns (uint32 mintFeeBasisPoints) {
        mintFeeBasisPoints = _mintFeeBP();
    }

    /// @inheritdoc IPerpetualMintView
    function mintToken() external view returns (address token) {
        token = _mintToken();
    }

    /// @inheritdoc IPerpetualMintView
    function redemptionFeeBP() external view returns (uint32 feeBP) {
        feeBP = _redemptionFeeBP();
    }

    /// @inheritdoc IPerpetualMintView
    function tiers() external view returns (TiersData memory tiersData) {
        tiersData = _tiers();
    }

    /// @inheritdoc IPerpetualMintView
    function vrfConfig() external view returns (VRFConfig memory config) {
        config = _vrfConfig();
    }

    /// @inheritdoc IPerpetualMintView
    function vrfSubscriptionBalanceThreshold()
        external
        view
        returns (uint96 threshold)
    {
        threshold = _vrfSubscriptionBalanceThreshold();
    }

    /// @notice Chainlink VRF Coordinator callback
    /// @param requestId id of request for random values
    /// @param randomWords random values returned from Chainlink VRF coordination
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        _fulfillRandomWords(requestId, randomWords);
    }
}

