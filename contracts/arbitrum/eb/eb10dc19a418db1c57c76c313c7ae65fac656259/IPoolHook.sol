// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {IPool} from "./IPool.sol";
import {DataTypes} from "./DataTypes.sol";

interface IPoolHook {
    /**
     * @notice Called after increase position or deposit collateral
     * @param extradata = encode of (sizeIncreased, collateralValueAdded, feeValue)
     * @dev all value of extradata is in USD
     */
    function postIncreasePosition(
        address owner,
        address indexToken,
        address collateralToken,
        DataTypes.Side side,
        bytes calldata extradata
    ) external;

    /**
     * @notice Called after decrease position / withdraw collateral
     * @param extradata = encode of (sizeDecreased, collateralValueReduced, feeValue)
     * @dev all value of extradata is in USD
     */
    function postDecreasePosition(
        address owner,
        address indexToken,
        address collateralToken,
        DataTypes.Side side,
        bytes calldata extradata
    ) external;

    /**
     * @notice Called after liquidate position
     * @param extradata = encode of (positionSize, collateralValue, feeValue)
     * @dev all value of extradata is in USD
     */
    function postLiquidatePosition(
        address owner,
        address indexToken,
        address collateralToken,
        DataTypes.Side side,
        bytes calldata extradata
    ) external;

    /**
     * @notice Called after increase position
     * @param user user who receive token out
     * @param tokenIn token swap from
     * @param tokenOut token swap to
     * @param data = encode of (amountIn, amountOutAfterFee, feeValue, extradata)
     * extradata include:
     *     - benificier address: address receive trading incentive
     * @dev
     *     - amountIn, amountOutAfterFee is number of token
     *     - feeValue is in USD
     */
    function postSwap(address user, address tokenIn, address tokenOut, bytes calldata data) external;

    event PreIncreasePositionExecuted(
        address pool, address owner, address indexToken, address collateralToken, DataTypes.Side side, bytes extradata
    );
    event PostIncreasePositionExecuted(
        address pool, address owner, address indexToken, address collateralToken, DataTypes.Side side, bytes extradata
    );
    event PreDecreasePositionExecuted(
        address pool, address owner, address indexToken, address collateralToken, DataTypes.Side side, bytes extradata
    );
    event PostDecreasePositionExecuted(
        address pool, address owner, address indexToken, address collateralToken, DataTypes.Side side, bytes extradata
    );
    event PreLiquidatePositionExecuted(
        address pool, address owner, address indexToken, address collateralToken, DataTypes.Side side, bytes extradata
    );
    event PostLiquidatePositionExecuted(
        address pool, address owner, address indexToken, address collateralToken, DataTypes.Side side, bytes extradata
    );

    event PostSwapExecuted(address pool, address user, address tokenIn, address tokenOut, bytes data);
}

