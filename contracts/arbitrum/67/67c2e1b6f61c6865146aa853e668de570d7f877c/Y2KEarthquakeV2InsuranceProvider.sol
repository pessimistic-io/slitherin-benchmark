// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./console.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {Math} from "./Math.sol";

import {IInsuranceProvider} from "./IInsuranceProvider.sol";
import {IVaultFactoryV2Extended} from "./IVaultFactoryV2Extended.sol";
import {IVaultV2Extended} from "./IVaultV2Extended.sol";

/// @title Insurance Provider for Y2k Earthquake v2
/// @author Y2K Finance
/// @dev All function calls are currently implemented without side effects
contract Y2KEarthquakeV2InsuranceProvider is IInsuranceProvider {
    using SafeERC20 for IERC20;

    /// @notice Earthquake vault factory
    IVaultFactoryV2Extended public immutable vaultFactory;

    /// @notice Last claimed epoch index; Market Id => Epoch Index
    mapping(uint256 => uint256) public nextEpochIndexToClaim;

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Constructor
     * @param _vaultFactory Address of Earthquake v2 vault factory.
     */
    constructor(address _vaultFactory) {
        require(_vaultFactory != address(0), "VaultFactory zero address");
        vaultFactory = IVaultFactoryV2Extended(_vaultFactory);
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Returns emissions token address.
     */
    function emissionsToken() external pure returns (address) {
        return address(0);
    }

    /**
     * @notice Returns vault addresses.
     * @param marketId Market Id
     */
    function getVaults(uint256 marketId) external view returns (address[2] memory) {
        return vaultFactory.getVaults(marketId);
    }

    /**
     * @notice Returns the current epoch.
     * @dev If epoch iteration takes long, then we can think of binary search
     * @param vault Earthquake vault
     */
    function currentEpoch(IVaultV2Extended vault) public view returns (uint256) {
        uint256 len = vault.getEpochsLength();
        if (len > 0) {
            for (uint256 i = len - 1; i >= 0; i--) {
                uint256 epochId = vault.epochs(i);
                (uint40 epochBegin, uint40 epochEnd, ) = vault.getEpochConfig(
                    epochId
                );
                if (block.timestamp > epochEnd) {
                    break;
                }

                if (
                    block.timestamp > epochBegin &&
                    block.timestamp <= epochEnd &&
                    !vault.epochResolved(epochId)
                ) {
                    return epochId;
                }
            }
        }
        return 0;
    }

    /**
     * @notice Returns the next epoch.
     * @param vault Earthquake vault
     */
    function nextEpoch(IVaultV2Extended vault) public view returns (uint256) {
        uint256 len = vault.getEpochsLength();
        if (len == 0) return 0;
        uint256 epochId = vault.epochs(len - 1);
        (uint40 epochBegin, , ) = vault.getEpochConfig(epochId);
        // TODO: should we handle the sitaution where there are two epochs at the end,
        // both of which are not started? it is unlikely but may happen if there is a
        // misconfiguration on Y2K side
        if (block.timestamp > epochBegin) return 0;
        return epochId;
    }

    /**
     * @notice Is next epoch purchasable.
     * @param marketId Market Id
     */
    function isNextEpochPurchasable(uint256 marketId) external view returns (bool) {
        address[2] memory vaults = vaultFactory.getVaults(marketId);
        IVaultV2Extended vault = IVaultV2Extended(vaults[0]);
        uint256 id = nextEpoch(vault);
        (uint40 epochBegin, , ) = vault.getEpochConfig(id);
        return id > 0 && block.timestamp <= epochBegin;
    }

    /**
     * @notice Pending payouts.
     * @param marketId Market Id
     */
    function pendingPayouts(uint256 marketId) external view returns (uint256 pending) {
        address[2] memory vaults = vaultFactory.getVaults(marketId);
        uint256[] memory epochs = vaultFactory.getEpochsByMarketId(marketId);

        IVaultV2Extended premium = IVaultV2Extended(vaults[0]);
        IVaultV2Extended collateral = IVaultV2Extended(vaults[1]);

        for (uint256 i = nextEpochIndexToClaim[marketId]; i < epochs.length; i++) {
            (, uint40 epochEnd, ) = premium.getEpochConfig(
                epochs[i]
            );
            if (
                block.timestamp <= epochEnd ||
                !premium.epochResolved(epochs[i]) ||
                !collateral.epochResolved(epochs[i])
            ) {
                break;
            }

            uint256 premiumShares = premium.balanceOf(msg.sender, epochs[i]);
            uint256 collateralShares = collateral.balanceOf(msg.sender, epochs[i]);
            pending += premium.previewWithdraw(epochs[i], premiumShares);
            pending += collateral.previewWithdraw(epochs[i], collateralShares);
        }
    }

    /**
     * @notice Pending emissions.
     */
    function pendingEmissions(uint256) external pure returns (uint256) {
        return 0;
    }

    /*//////////////////////////////////////////////////////////////
                                OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Purchase next epoch.
     * @param marketId Market Id
     * @param amountPremium Premium amount for insurance
     * @param amountCollateral Collateral amount for insurance
     */
    function purchaseForNextEpoch(
        uint256 marketId,
        uint256 amountPremium,
        uint256 amountCollateral
    ) external {
        (,,address underlyingAsset) = vaultFactory.marketIdInfo(marketId);
        address[2] memory vaults = vaultFactory.getVaults(marketId);
        IERC20(underlyingAsset).safeTransferFrom(msg.sender, address(this), amountPremium + amountCollateral);
        IERC20(underlyingAsset).safeApprove(vaults[0], amountPremium);
        IERC20(underlyingAsset).safeApprove(vaults[1], amountCollateral);

        uint256 nextEpochId = nextEpoch(IVaultV2Extended(vaults[0]));
        IVaultV2Extended(vaults[0]).deposit(nextEpochId, amountPremium, msg.sender);
        IVaultV2Extended(vaults[1]).deposit(nextEpochId, amountCollateral, msg.sender);
    }

    /**
     * @notice Claims payout for the resolved epochs.
     * @param marketId Market Id
     */
    function claimPayouts(uint256 marketId) external returns (uint256 amount) {
        uint256[] memory epochs = vaultFactory.getEpochsByMarketId(marketId);
        address[2] memory vaults = vaultFactory.getVaults(marketId);

        IVaultV2Extended premium = IVaultV2Extended(vaults[0]);
        IVaultV2Extended collateral = IVaultV2Extended(vaults[1]);

        uint256 i = nextEpochIndexToClaim[marketId];
        for (; i < epochs.length; i++) {
            (, uint40 epochEnd, ) = premium.getEpochConfig(
                epochs[i]
            );
            if (
                block.timestamp <= epochEnd ||
                !premium.epochResolved(epochs[i]) ||
                !collateral.epochResolved(epochs[i])
            ) {
                break;
            }

            uint256 premiumShares = premium.balanceOf(msg.sender, epochs[i]);
            if (premiumShares > 0) {
                amount += premium.withdraw(
                    epochs[i],
                    premiumShares,
                    msg.sender,
                    msg.sender
                );
            }
            uint256 collateralShares = collateral.balanceOf(msg.sender, epochs[i]);
            if (collateralShares > 0) {
                amount += collateral.withdraw(
                    epochs[i],
                    collateralShares,
                    msg.sender,
                    msg.sender
                );
            }
        }
        nextEpochIndexToClaim[marketId] = i;
    }
}

