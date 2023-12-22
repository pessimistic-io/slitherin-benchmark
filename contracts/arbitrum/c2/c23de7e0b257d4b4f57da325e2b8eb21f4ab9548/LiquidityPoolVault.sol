// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20Metadata.sol";
import "./SafeERC20.sol";
import "./Math.sol";
import "./ERC20Upgradeable.sol";
import "./ILiquidityPoolVault.sol";

/**
 * @notice ADAPTATION OF THE OPENZEPPELIN ERC4626 CONTRACT
 * @dev
 * All function implementations are left as in the original implementation.
 * Some functions are removed.
 * Some function scopes are changed from private to internal.
 */
abstract contract LiquidityPoolVault is ERC20Upgradeable, ILiquidityPoolVault {
    using Math for uint256;

    IERC20Metadata internal immutable _asset;

    uint8 internal constant _decimals = 24;

    // Storage gap
    uint256[50] __gap;

    /**
     * @dev Set the underlying asset contract. This must be an ERC20-compatible contract (ERC20 or ERC777).
     */
    constructor(IERC20Metadata asset_) {
        // To prevent a front-running attack, we make sure that the share decimals are larger than the asset decimals.
        require(asset_.decimals() <= 18, "LiquidityPoolVault::constructor: asset decimals must be <= 18");
        _asset = asset_;
    }

    /**
     * @dev See {IERC4262-asset}
     */
    function asset() public view virtual override returns (address) {
        return address(_asset);
    }

    /**
     * @dev See {IERC4262-decimals}
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev See {IERC4262-totalAssets}
     */
    function totalAssets() public view virtual override returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    /**
     * @dev See {IERC4262-convertToShares}
     */
    function convertToShares(uint256 assets) public view virtual override returns (uint256 shares) {
        return _convertToShares(assets, Math.Rounding.Down);
    }

    /**
     * @dev See {IERC4262-convertToAssets}
     */
    function convertToAssets(uint256 shares) public view virtual override returns (uint256 assets) {
        return _convertToAssets(shares, Math.Rounding.Down);
    }

    /**
     * @dev See {IERC4262-previewDeposit}
     */
    function previewDeposit(uint256 assets) public view virtual override returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Down);
    }

    /**
     * @dev See {IERC4262-previewMint}
     */
    function previewMint(uint256 shares) public view virtual override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Up);
    }

    /**
     * @dev See {IERC4262-previewWithdraw}
     */
    function previewWithdraw(uint256 assets) public view virtual override returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Up);
    }

    /**
     * @dev See {IERC4262-previewRedeem}
     */
    function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Down);
    }

    /**
     * @dev Internal convertion function (from assets to shares) with support for rounding direction
     *
     * Will revert if assets > 0, totalSupply > 0 and totalAssets = 0. That corresponds to a case where any asset
     * would represent an infinite amout of shares.
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual returns (uint256 shares) {
        uint256 supply = totalSupply();
        return (assets == 0 || supply == 0)
            ? assets.mulDiv(10 ** decimals(), 10 ** _asset.decimals(), rounding)
            : assets.mulDiv(supply, totalAssets(), rounding);
    }

    /**
     * @dev Internal convertion function (from shares to assets) with support for rounding direction
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual returns (uint256 assets) {
        uint256 supply = totalSupply();
        return (supply == 0)
            ? shares.mulDiv(10 ** _asset.decimals(), 10 ** decimals(), rounding)
            : shares.mulDiv(totalAssets(), supply, rounding);
    }

    /**
     * @dev Deposit/mint common workflow
     */
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal {
        // If _asset is ERC777, `transferFrom` can trigger a reenterancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transfered and before the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth
        SafeERC20.safeTransferFrom(_asset, caller, address(this), assets);
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev Withdraw/redeem common workflow
     */
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal {
        // If _asset is ERC777, `transfer` can trigger trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transfered, which is a valid state.
        _burn(owner, shares);
        SafeERC20.safeTransfer(_asset, receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }
}

