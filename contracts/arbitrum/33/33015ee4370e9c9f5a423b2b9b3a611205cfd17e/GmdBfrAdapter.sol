// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;

import "./RariVault.sol";
import "./ERC20.sol";
import "./IGMDVault.sol";
import "./FixedPointMathLib.sol";

contract GmdBfrAdapter is RariVault {
    using FixedPointMathLib for uint256;

    IGMDVault public immutable vault;
    ERC20 public immutable gmdToken;
    uint256 public immutable PID;
    uint constant BASIS_POINTS = 100000;

    constructor(address _asset, address _vault, address _gmdToken, uint _pid) RariVault(ERC20(_asset)) {
        vault = IGMDVault(_vault);
        gmdToken = ERC20(_gmdToken);
        PID = _pid;

        ERC20(asset).approve(_vault, type(uint).max);
        ERC20(gmdToken).approve(_vault, type(uint).max);
    }

    function totalAssets() public view virtual override returns (uint256 total) {
        //Total supply and price per staked token are in 1e18 even though USDC is in 1e6
        total = vault.GDpriceToStakedtoken(PID).mulDivDown(gmdToken.balanceOf(address(this)), 1e18);

        //Convert it from 18 decimals down to 6 for USDC
        try asset.decimals() returns (uint8 _decimals) {
            total /= (10 ** (18 - _decimals));
        }
        catch {
            return total;
        }
    }

    function afterDeposit(uint256 assets, uint256) internal virtual override {
        vault.enter(assets, PID);
    }

    function convertToShares(uint256 assets) public view virtual override returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        IGMDBfrPool.PoolInfo memory info = IGMDBfrPool(address(vault)).poolInfo(PID);
        uint256 balanceMultiplier = BASIS_POINTS - info.BlpFees;

        //Should be 99.5% of assets
        uint assetsAfterFee = assets.mulDivUp(balanceMultiplier, BASIS_POINTS);

        //Since it's shares it should be mulDivUp
        return supply == 0 ? assetsAfterFee : assetsAfterFee.mulDivUp(supply, totalAssets());

    }

    function previewMint(uint256 shares) public view virtual override returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        IGMDBfrPool.PoolInfo memory info = IGMDBfrPool(address(vault)).poolInfo(PID);
        uint256 balanceMultipier = BASIS_POINTS - info.BlpFees;

        //Should be mulDivDown it's about assets
        uint assetsAfterFee = supply == 0 ? shares : shares.mulDivDown(totalAssets(), supply);

        //Should round up because we want more assets before the fee as a buffer
        //Assets before fee - 1.05% of assets before fee
        return assetsAfterFee.mulDivDown(BASIS_POINTS, balanceMultipier);
    }

    function beforeWithdraw(uint256, uint256 shares) internal virtual override {
        uint gmdAssets = shares.mulDivDown(gmdToken.balanceOf(address(this)), totalSupply);
        vault.leave(gmdAssets, PID);
    }

    function maxDeposit(address) public view virtual override returns (uint256) {
        IGMDVault.PoolInfo memory info = vault.poolInfo(PID);

        return info.vaultcap - info.totalStaked;
    }

    function maxMint(address) public view virtual override returns (uint256) {
        IGMDVault.PoolInfo memory info = vault.poolInfo(PID);

        return convertToShares(info.vaultcap - info.totalStaked);
    }

    //This adapter is not permissioned so no overrides are needed

}
