// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./SafeCast.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

interface IERC20Decimals is IERC20 {
    function decimals() external view returns (uint8);
}

library Precision {
    // 价格精度 = 30
    // 率精度(资金费率, vault APR精度, 手续费率, global valid)
    uint256 public constant BASIS_POINTS_DIVISOR = 100000000;
    uint256 public constant FEE_RATE_PRECISION_DECIMALS = 8;
    uint256 public constant FEE_RATE_PRECISION = 10**FEE_RATE_PRECISION_DECIMALS;

    // function calRate(uint256 fenmu) external{
    //     return fenmu / BASIS_POINTS_DIVISOR;
    // }
}

library TransferHelper {
    uint8 public constant usdDecimals = 18; //数量精度

    using SafeERC20 for IERC20;

    function getUSDDecimals() internal pure returns (uint8) {
        return usdDecimals;
    }

    function formatCollateral(
        uint256 amount,
        uint8 collateralTokenDigits
    ) internal pure returns (uint256) {
        return
            (amount * (10 ** uint256(collateralTokenDigits))) /
            (10 ** usdDecimals);
    }

    function parseVaultAsset(
        uint256 amount,
        uint8 originDigits
    ) internal pure returns (uint256) {
        return
            (amount * (10 ** uint256(usdDecimals))) /
            (10 ** originDigits);
    }

    /**
     * @dev This library contains utility functions for transferring assets.
     * @param amount The amount of assets to transfer in integer format with decimal precision.
     * @param collateralTokenDigits The decimal precision of the collateral token.
     * @return The transferred asset amount converted to integer with decimal precision for the USD stablecoin.
     * This function is internal and can only be accessed within the current contract or library.
     */
    function parseVaultAssetSigned(
        int256 amount,
        uint8 collateralTokenDigits
    ) internal pure returns (int256) {
        return
            (amount * int256(10 ** uint256(collateralTokenDigits))) /
            int256(10 ** uint256(usdDecimals));
    }

    //=======================================

    function transferIn(
        address tokenAddress,
        address _from,
        address _to,
        uint256 _tokenAmount
    ) internal {
        if (_tokenAmount == 0) return;
        IERC20 coll = IERC20(tokenAddress);
        coll.safeTransferFrom(
            _from,
            _to,
            formatCollateral(
                _tokenAmount,
                IERC20Decimals(tokenAddress).decimals()
            )
        );
    }

    function transferOut(
        address tokenAddress,
        address _to,
        uint256 _tokenAmount
    ) internal {
        if (_tokenAmount == 0) return;
        IERC20 coll = IERC20(tokenAddress);
        _tokenAmount = formatCollateral(
            _tokenAmount,
            IERC20Decimals(tokenAddress).decimals()
        );
        coll.safeTransfer(_to, _tokenAmount);
    }
}

