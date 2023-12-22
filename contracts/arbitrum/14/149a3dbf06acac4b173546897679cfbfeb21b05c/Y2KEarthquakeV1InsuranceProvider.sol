// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./console.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {Math} from "./Math.sol";
import {IERC1155} from "./IERC1155.sol";

import {IInsuranceProvider} from "./IInsuranceProvider.sol";
import {IVaultFactory} from "./IVaultFactory.sol";
import {IVault} from "./IVault.sol";

interface IVaultFactoryCustom {
    function WETH() external returns (address);
}

/// @title Insurance Provider for Y2k Earthquake v1
/// @author Y2K Finance
/// @dev All function calls are currently implemented without side effects
contract Y2KEarthquakeV1InsuranceProvider is IInsuranceProvider {
    using SafeERC20 for IERC20;

    address public immutable WETH;

    /// @notice Earthquake vault factory
    IVaultFactory public immutable vaultFactory;

    /// @notice Last claimed epoch index; Market Id => Epoch Index
    mapping(uint256 => uint256) public nextEpochIndexToClaim;

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Constructor
     * @param _vaultFactory Address of Earthquake v1 vault factory.
     */
    constructor(address _vaultFactory) {
        require(_vaultFactory != address(0), "VaultFactory zero address");
        vaultFactory = IVaultFactory(_vaultFactory);
        WETH = IVaultFactoryCustom(_vaultFactory).WETH();
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
    function getVaults(uint256 marketId) public view returns (address[2] memory vaults) {
        vaults[0] = vaultFactory.indexVaults(marketId, 0);
        vaults[1] = vaultFactory.indexVaults(marketId, 1);
    }

    /**
     * @notice Returns the current epoch.
     * @dev If epoch iteration takes long, then we can think of binary search
     * @param vault Earthquake vault
     */
    function currentEpoch(IVault vault) public view returns (uint256) {
        uint256 len = vault.epochsLength();
        if (len > 0) {
            for (uint256 i = len - 1; i >= 0; i--) {
                uint256 epochId = vault.epochs(i);
                if (block.timestamp > epochId) {
                    break;
                }

                uint256 epochBegin = vault.idEpochBegin(epochId);
                if (
                    block.timestamp > epochBegin &&
                    block.timestamp <= epochId &&
                    !vault.idEpochEnded(epochId)
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
    function nextEpoch(IVault vault) public view returns (uint256) {
        uint256 len = vault.epochsLength();
        if (len == 0) return 0;
        uint256 epochId = vault.epochs(len - 1);
        // TODO: should we handle the sitaution where there are two epochs at the end,
        // both of which are not started? it is unlikely but may happen if there is a
        // misconfiguration on Y2K side
        if (block.timestamp > vault.idEpochBegin(epochId)) return 0;
        return epochId;
    }

    /**
     * @notice Is next epoch purchasable.
     * @param marketId Market Id
     */
    function isNextEpochPurchasable(uint256 marketId) external view returns (bool) {
        address[2] memory vaults = getVaults(marketId);
        IVault vault = IVault(vaults[0]);
        uint256 id = nextEpoch(vault);
        return id > 0 && block.timestamp <= vault.idEpochBegin(id);
    }

    /**
     * @notice Pending payouts.
     * @param marketId Market Id
     */
    function pendingPayouts(uint256 marketId) external view returns (uint256 pending) {
        address[2] memory vaults = getVaults(marketId);

        IVault premium = IVault(vaults[0]);
        IVault collateral = IVault(vaults[1]);

        uint256 len = premium.epochsLength();
        for (uint256 i = nextEpochIndexToClaim[marketId]; i < len; i++) {
            uint256 epochId = premium.epochs(i);
            if (
                block.timestamp <= epochId ||
                !premium.idEpochEnded(epochId) ||
                !collateral.idEpochEnded(epochId)
            ) {
                break;
            }

            uint256 premiumShares = IERC1155(address(premium)).balanceOf(msg.sender, epochId);
            uint256 collateralShares = IERC1155(address(collateral)).balanceOf(msg.sender, epochId);
            pending += premium.previewWithdraw(epochId, premiumShares);
            pending += collateral.previewWithdraw(epochId, collateralShares);
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
        address[2] memory vaults = getVaults(marketId);
        IERC20(WETH).safeTransferFrom(msg.sender, address(this), amountPremium + amountCollateral);
        IERC20(WETH).safeApprove(vaults[0], amountPremium);
        IERC20(WETH).safeApprove(vaults[1], amountCollateral);

        uint256 nextEpochId = nextEpoch(IVault(vaults[0]));
        IVault(vaults[0]).deposit(nextEpochId, amountPremium, msg.sender);
        IVault(vaults[1]).deposit(nextEpochId, amountCollateral, msg.sender);
    }

    /**
     * @notice Claims payout for the resolved epochs.
     * @param marketId Market Id
     */
    function claimPayouts(uint256 marketId) external returns (uint256 amount) {
        address[2] memory vaults = getVaults(marketId);

        IVault premium = IVault(vaults[0]);
        IVault collateral = IVault(vaults[1]);

        uint256 i = nextEpochIndexToClaim[marketId];
        uint256 len = premium.epochsLength();
        for (; i < len; i++) {
            uint256 epochId = premium.epochs(i);
            if (
                block.timestamp <= epochId ||
                !premium.idEpochEnded(epochId) ||
                !collateral.idEpochEnded(epochId)
            ) {
                break;
            }

            uint256 premiumShares = IERC1155(address(premium)).balanceOf(msg.sender, epochId);
            if (premiumShares > 0) {
                amount += premium.withdraw(
                    epochId,
                    premiumShares,
                    msg.sender,
                    msg.sender
                );
            }
            uint256 collateralShares = IERC1155(address(collateral)).balanceOf(msg.sender, epochId);
            if (collateralShares > 0) {
                amount += collateral.withdraw(
                    epochId,
                    collateralShares,
                    msg.sender,
                    msg.sender
                );
            }
        }
        nextEpochIndexToClaim[marketId] = i;
    }
}

