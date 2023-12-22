// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {ILendingPoolV2, DataTypes as DataTypesV2} from "./ILendingPoolV2.sol";
import {IPool as ILendingPoolV3, DataTypes as DataTypesV3} from "./ILendingPoolV3.sol";
import {ERC20, SafeTransferLib} from "./SafeTransferLib.sol";

contract Migrator {

    using SafeTransferLib for ERC20;

    ILendingPoolV2 public immutable VEGA;

    enum Version {V2, V3}

    constructor(ILendingPoolV2 vega) {
        VEGA = vega;
    }

    // VEGA callback.
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == address(VEGA), 'Not from vega');
        require(initiator == address(this), 'Not from address(this)');
        (
            address lendingPool,
            address user,
            address[] memory collateral, 
            Version version
        ) = abi.decode(params, (address, address, address[], Version));
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 amount = amounts[i];
            ERC20(asset).safeApprove(address(lendingPool), amount);
            // Same call for V2 and V3.
            ILendingPoolV2(lendingPool).repay(asset, amount, 2, user);
        }
        if (version == Version.V2) {
            _migrateAssetsFromV2(ILendingPoolV2(lendingPool), collateral, user);
        } else if (version == Version.V3) {
            _migrateAssetsFromV3(ILendingPoolV3(lendingPool), collateral, user);
        }
        return true;
    }

    function migrateFromV3(
        ILendingPoolV3 lendingPool,
        address[] memory assetsToMigrate,
        address[] memory positionsToRepay
    ) external {
        if (positionsToRepay.length > 0) {
            VEGA.flashLoan({
                receiverAddress: address(this),
                assets: positionsToRepay,
                modes: _getModes(positionsToRepay.length),
                amounts: _getDebtAmountsV3(lendingPool, positionsToRepay),
                onBehalfOf: msg.sender,
                params: abi.encode(lendingPool, msg.sender, assetsToMigrate, Version.V3),
                referralCode: 0
            });
        } else {
            _migrateAssetsFromV3(lendingPool, assetsToMigrate, msg.sender);
        }
    }

    function migrateFromV2(
        ILendingPoolV2 lendingPool,
        address[] memory assetsToMigrate,
        address[] memory positionsToRepay
    ) external {
        if (positionsToRepay.length > 0) {
            VEGA.flashLoan({
                receiverAddress: address(this),
                assets: positionsToRepay,
                modes: _getModes(positionsToRepay.length),
                amounts: _getDebtAmountsV2(lendingPool, positionsToRepay),
                onBehalfOf: msg.sender,
                params: abi.encode(lendingPool, msg.sender, assetsToMigrate, Version.V2),
                referralCode: 0
            });
        } else {
            _migrateAssetsFromV2(lendingPool, assetsToMigrate, msg.sender);
        }
    }

    function _migrateAssetsFromV3(ILendingPoolV3 lendingPool, address[] memory assets, address user) internal {
        for(uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            _withdrawAssetFromV3(lendingPool, asset, user);
            _depositAsset(asset, user);
        }
    }

    function _migrateAssetsFromV2(ILendingPoolV2 lendingPool, address[] memory assets, address user) internal {
        for(uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            _withdrawAssetFromV2(lendingPool, asset, user);
            _depositAsset(asset, user);
        }
    }

    function _withdrawAssetFromV3(ILendingPoolV3 lendingPool, address asset, address user) internal {
        DataTypesV3.ReserveData memory reserveData = lendingPool.getReserveData(asset);
        address token = reserveData.aTokenAddress;
        uint256 balance = ERC20(token).balanceOf(user);
        ERC20(token).safeTransferFrom(user, address(this), balance);
        lendingPool.withdraw(asset, balance, address(this));
    }

    function _withdrawAssetFromV2(ILendingPoolV2 lendingPool, address asset, address user) internal {
        DataTypesV2.ReserveData memory reserveData = lendingPool.getReserveData(asset);
        address token = reserveData.aTokenAddress;
        uint256 balance = ERC20(token).balanceOf(user);
        ERC20(token).safeTransferFrom(user, address(this), balance);
        lendingPool.withdraw(asset, balance, address(this));
    }

    function _depositAsset(address asset, address user) internal {
        uint256 balance = ERC20(asset).balanceOf(address(this));
        ERC20(asset).approve(address(VEGA), balance);
        VEGA.deposit(asset, balance, user, 0);
    }

    function _getDebtAmountsV2(ILendingPoolV2 pool, address[] memory debtPositions) internal view returns (uint256[] memory amounts) {
        amounts = new uint256[](debtPositions.length);
        for (uint256 i = 0; i < debtPositions.length; i++) {
            DataTypesV2.ReserveData memory reserveData = pool.getReserveData(debtPositions[i]);
            amounts[i] = ERC20(reserveData.variableDebtTokenAddress).balanceOf(msg.sender);
            require(amounts[i] > 0, 'No debt to migrate');
        }
    }

    function _getDebtAmountsV3(ILendingPoolV3 pool, address[] memory debtPositions) internal view returns (uint256[] memory amounts) {
        amounts = new uint256[](debtPositions.length);
        for (uint256 i = 0; i < debtPositions.length; i++) {
            DataTypesV3.ReserveData memory reserveData = pool.getReserveData(debtPositions[i]);
            amounts[i] = ERC20(reserveData.variableDebtTokenAddress).balanceOf(msg.sender);
            require(amounts[i] > 0, 'No debt to migrate');
        }
    }

    function _getModes(uint256 length) internal pure returns (uint256[] memory modes) {
        modes = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            modes[i] = 2; // We open variable debt positions.
        }
    }

}
