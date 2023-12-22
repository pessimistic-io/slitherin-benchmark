// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./VaultInternal.sol";

/**
 * @title Knox Vault View Contract (read-only)
 * @dev deployed standalone and referenced by VaultDiamond
 */

contract VaultView is IVaultView, VaultInternal {
    using OptionMath for uint256;
    using VaultStorage for VaultStorage.Layout;

    constructor(bool isCall, address pool) VaultInternal(isCall, pool) {}

    /************************************************
     *  VIEW
     ***********************************************/

    /**
     * @inheritdoc IVaultView
     */
    function getActors()
        external
        view
        returns (
            address,
            address,
            address
        )
    {
        VaultStorage.Layout storage l = VaultStorage.layout();
        return (_owner(), l.feeRecipient, l.keeper);
    }

    /**
     * @inheritdoc IVaultView
     */
    function getAuctionWindowOffsets()
        external
        view
        returns (uint256, uint256)
    {
        VaultStorage.Layout storage l = VaultStorage.layout();
        return (l.startOffset, l.endOffset);
    }

    /**
     * @inheritdoc IVaultView
     */
    function getConnections()
        external
        view
        returns (
            address,
            address,
            address,
            address
        )
    {
        VaultStorage.Layout storage l = VaultStorage.layout();
        return (
            address(l.Auction),
            address(Pool),
            address(l.Pricer),
            address(l.Queue)
        );
    }

    /**
     * @inheritdoc IVaultView
     */
    function getDelta64x64() external view returns (int128) {
        VaultStorage.Layout storage l = VaultStorage.layout();
        return l.delta64x64;
    }

    /**
     * @inheritdoc IVaultView
     */
    function getEpoch() external view returns (uint64) {
        return VaultStorage._getEpoch();
    }

    /**
     * @inheritdoc IVaultView
     */
    function getOption(uint64 epoch)
        external
        view
        returns (VaultStorage.Option memory)
    {
        return VaultStorage._getOption(epoch);
    }

    /**
     * @inheritdoc IVaultView
     */
    function getOptionType() external view returns (bool) {
        return VaultStorage.layout().isCall;
    }

    /**
     * @inheritdoc IVaultView
     */
    function getPerformanceFee64x64() external view returns (int128) {
        return VaultStorage.layout().performanceFee64x64;
    }

    /**
     * @inheritdoc IVaultView
     */
    function previewDistributions(uint256 assetAmount)
        external
        view
        returns (uint256, uint256)
    {
        VaultStorage.Layout storage l = VaultStorage.layout();
        return _previewDistributions(l, assetAmount);
    }

    /**
     * @inheritdoc IVaultView
     */
    function previewReserves() external view returns (uint256) {
        return _previewReserves();
    }

    /**
     * @inheritdoc IVaultView
     */
    function previewTotalContracts(
        int128 strike64x64,
        uint256 collateral,
        uint256 reserves
    ) external view returns (uint256) {
        VaultStorage.Layout storage l = VaultStorage.layout();

        return
            (collateral - reserves).fromCollateralToContracts(
                l.isCall,
                l.baseDecimals,
                strike64x64
            );
    }

    /**
     * @inheritdoc IVaultView
     */
    function totalCollateral() external view returns (uint256) {
        return _totalCollateral();
    }

    /**
     * @inheritdoc IVaultView
     */
    function totalShortAsCollateral() external view returns (uint256) {
        return _totalShortAsCollateral();
    }

    /**
     * @inheritdoc IVaultView
     */
    function totalShortAsContracts() external view returns (uint256) {
        return _totalShortAsContracts();
    }
}

