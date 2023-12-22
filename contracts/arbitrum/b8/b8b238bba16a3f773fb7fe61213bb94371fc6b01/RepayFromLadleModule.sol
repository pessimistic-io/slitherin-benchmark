// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "./LadleStorage.sol";
import "./CastU256I128.sol";
import "./CastU256U128.sol";
import "./TransferHelper.sol";

contract RepayFromLadleModule is LadleStorage {
    using CastU256I128 for uint256;
    using CastU256U128 for uint256;
    using TransferHelper for IERC20;

    ///@notice Creates a Healer module for the Ladle
    ///@param cauldron_ address of the Cauldron
    ///@param weth_ address of WETH
    constructor(ICauldron cauldron_, IWETH9 weth_) LadleStorage(cauldron_, weth_) {}

    /// @dev Use fyToken in the Ladle to repay debt. Returns collateral to collateralReceiver and unused fyToken to remainderReceiver.
    /// Return as much collateral as debt was repaid, as well. This function is only used when
    /// removing liquidity added with "Borrow and Pool", so it's safe to assume the exchange rate
    /// is 1:1. If used in other contexts, it might revert, which is fine.
    /// Can only be used for Borrow and Pool vaults, which have the same ilkId and underlyhing
    function repayFromLadle(bytes12 vaultId_, address collateralReceiver, address remainderReceiver)
        external payable
        returns (uint256 repaid)
    {
        (bytes12 vaultId, DataTypes.Vault memory vault) = getVault(vaultId_);
        DataTypes.Series memory series = getSeries(vault.seriesId);
        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        require(series.fyToken.underlying() == cauldron.assets(vault.ilkId), "Only for Borrow and Pool");
        
        uint256 amount = series.fyToken.balanceOf(address(this));
        repaid = amount <= balances.art ? amount : balances.art;

        // Update accounting, burn fyToken and return collateral
        if (repaid > 0) {
            cauldron.pour(vaultId, -(repaid.i128()), -(repaid.i128()));
            series.fyToken.burn(address(this), repaid);
            IJoin ilkJoin = getJoin(vault.ilkId);
            ilkJoin.exit(collateralReceiver, repaid.u128());
        }

        // Return remainder
        if (amount - repaid > 0) IERC20(address(series.fyToken)).safeTransfer(remainderReceiver, amount - repaid);

    }

    /// @dev Obtains a vault by vaultId from the Cauldron, and verifies that msg.sender is the owner
    /// If bytes(0) is passed as the vaultId it tries to load a vault from the cache
    function getVault(bytes12 vaultId_)
        internal view
        returns (bytes12 vaultId, DataTypes.Vault memory vault)
    {
        if (vaultId_ == bytes12(0)) { // We use the cache
            require (cachedVaultId != bytes12(0), "Vault not cached");
            vaultId = cachedVaultId;
        } else {
            vaultId = vaultId_;
        }
        vault = cauldron.vaults(vaultId);
    } 

    /// @dev Obtains a series by seriesId from the Cauldron, and verifies that it exists
    function getSeries(bytes6 seriesId)
        internal view returns(DataTypes.Series memory series)
    {
        series = cauldron.series(seriesId);
        require (series.fyToken != IFYToken(address(0)), "Series not found");
    }

    /// @dev Obtains a join by assetId, and verifies that it exists
    function getJoin(bytes6 assetId)
        internal view returns(IJoin join)
    {
        join = joins[assetId];
        require (join != IJoin(address(0)), "Join not found");
    }

}
