// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IPool} from "./IPool.sol";
import {IVariableDebtToken} from "./IVariableDebtToken.sol";
import {IAToken} from "./IAToken.sol";
import {IPoolDataProvider} from "./IPoolDataProvider.sol";
import {IPoolAddressesProvider} from "./IPoolAddressesProvider.sol";

import {TransferHelper} from "./TransferHelper.sol";
import {IV3SwapRouter} from "./IV3SwapRouter.sol";

import {IERC20} from "./ERC20_IERC20.sol";

/// @title AaveLogicLib
library AaveLogicLib {
    // =========================
    // Constants
    // =========================

    uint16 private constant REFFERAL_CODE = 0;
    uint256 private constant INTEREST_RATE_MODEL = 2;

    // =========================
    // Events
    // =========================

    /// @notice Emits when tokens are borrowed from Aave.
    /// @param token The token that was borrowed.
    /// @param amount The amount of tokens borrowed.
    event AaveBorrow(address token, uint256 amount);

    /// @notice Emits when tokens are supplied to Aave.
    /// @param token The token that was supplied.
    /// @param amount The amount of tokens supplied.
    event AaveSupply(address token, uint256 amount);

    /// @notice Emits when a loan is repaid to Aave.
    /// @param token The token that was repaid.
    /// @param amount The amount of tokens repaid.
    event AaveRepay(address token, uint256 amount);

    /// @notice Emits when tokens are withdrawn from Aave.
    /// @param token The token that was withdrawn.
    /// @param amount The amount of tokens withdrawn.
    event AaveWithdraw(address token, uint256 amount);

    /// @notice Emits when an emergency repayment is made using Aave's flash loan mechanism.
    /// @param supplyToken The token used to repay the debt.
    /// @param debtToken The token that was in debt.
    event AaveEmergencyRepay(address supplyToken, address debtToken);

    /// @notice Emits when a Aave's flash loan is executed.
    event AaveFlashLoan();

    // =========================
    // Errors
    // =========================

    /// @notice Thrown when the initiator of the flashLoan Aave operation
    /// is not valid or authorized.
    error AaveLogicLib_InitiatorNotValid();

    // =========================
    // Main Functions
    // =========================

    /// @dev Borrows a specified `amount` of a `token` using Aave.
    /// @param token The address of the token to be borrowed.
    /// @param amount The amount of the token to be borrowed.
    /// @param user The address of the user borrowing the token.
    /// @param poolAddressesProvider The provider of pool addresses for Aave.
    function borrowAave(
        address token,
        uint256 amount,
        address user,
        IPoolAddressesProvider poolAddressesProvider
    ) internal {
        IPool pool = IPool(poolAddressesProvider.getPool());
        pool.borrow(token, amount, INTEREST_RATE_MODEL, 0, user);

        emit AaveBorrow(token, amount);
    }

    /// @dev Supplies a specified `amount` of a `token` to Aave.
    /// @param token The address of the token to be supplied.
    /// @param amount The amount of the token to be supplied.
    /// @param user The address of the user supplying the token.
    /// @param poolAddressesProvider The provider of pool addresses for Aave.
    function supplyAave(
        address token,
        uint256 amount,
        address user,
        IPoolAddressesProvider poolAddressesProvider
    ) internal {
        IPool pool = IPool(poolAddressesProvider.getPool());
        TransferHelper.safeApprove(token, address(pool), amount);

        pool.supply(token, amount, user, 0);

        emit AaveSupply(token, amount);
    }

    /// @dev Repays a borrowed `amount` of a `token` using Aave.
    /// @param token The address of the token to be repaid.
    /// @param amount The amount of the token to be repaid.
    /// @param user The address of the user repaying the token.
    /// @param poolAddressesProvider The provider of pool addresses for Aave.
    function repayAave(
        address token,
        uint256 amount,
        address user,
        IPoolAddressesProvider poolAddressesProvider
    ) internal {
        uint256 balance = TransferHelper.safeGetBalance(token, user);
        if (balance < amount) {
            amount = balance;
        }

        IPool pool = IPool(poolAddressesProvider.getPool());
        TransferHelper.safeApprove(token, address(pool), amount);

        pool.repay(token, amount, INTEREST_RATE_MODEL, user);

        emit AaveRepay(token, amount);
    }

    /// @dev Withdraws a specified `amount` of a `token` from Aave.
    /// @param token The address of the token to be withdrawn.
    /// @param amount The amount of the token to be withdrawn.
    /// @param user The address of the user withdrawing the token.
    /// @param poolAddressesProvider The provider of pool addresses for Aave.
    function withdrawAave(
        address token,
        uint256 amount,
        address user,
        IPoolAddressesProvider poolAddressesProvider
    ) internal {
        IPool pool = IPool(poolAddressesProvider.getPool());
        pool.withdraw(token, amount, user);

        emit AaveWithdraw(token, amount);
    }

    /// @dev Executes an emergency repayment on Aave using a flash loan.
    /// @param supplyToken The address of the supply token.
    /// @param debtToken The address of the debt token.
    /// @param onBehalfOf The address on whose behalf the operation is being executed.
    /// @param poolAddressesProvider The provider of pool addresses for Aave.
    /// @param poolFee The fee tier in the uniswapV3 pool.
    function emergencyRepayAave(
        address supplyToken,
        address debtToken,
        address onBehalfOf,
        IPoolAddressesProvider poolAddressesProvider,
        uint24 poolFee
    ) internal {
        IPool pool = IPool(poolAddressesProvider.getPool());

        address aDebtToken = aDebtTokenAddress(debtToken, pool);
        bytes memory params = abi.encode(supplyToken, onBehalfOf, poolFee);

        uint256 remainingSupply = IERC20(supplyToken).balanceOf(address(this));

        pool.flashLoanSimple(
            address(this),
            debtToken,
            getTotalDebt(aDebtToken, onBehalfOf),
            params,
            REFFERAL_CODE
        );

        // return remaining supply amount back to aave
        remainingSupply =
            IERC20(supplyToken).balanceOf(address(this)) -
            remainingSupply;

        if (remainingSupply > 0) {
            IERC20(supplyToken).approve(address(pool), remainingSupply);
            pool.supply(supplyToken, remainingSupply, onBehalfOf, 0);
        }

        emit AaveEmergencyRepay(supplyToken, debtToken);
    }

    /// @dev Callback function for Aave flash loan.
    /// @param asset The address of the asset involved in the flash loan.
    /// @param amount The amount involved in the flash loan.
    /// @param premium The premium to be paid for the flash loan.
    /// @param initiator The address that initiated the flash loan.
    /// @param params Additional parameters related to the flash loan.
    /// @param poolAddressesProvider The provider of pool addresses for Aave.
    /// @param uniswapRouter The Uniswap router for token swaps.
    /// @return A boolean indicating if the operation was successful.
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params,
        IPoolAddressesProvider poolAddressesProvider,
        IV3SwapRouter uniswapRouter
    ) internal returns (bool) {
        if (initiator != address(this)) {
            revert AaveLogicLib_InitiatorNotValid();
        }

        IPool pool = IPool(poolAddressesProvider.getPool());

        // call must be from the pool contract
        if (msg.sender != address(pool)) {
            revert AaveLogicLib_InitiatorNotValid();
        }

        (address supplyToken, address onBehalfOf, uint24 poolFee) = abi.decode(
            params,
            (address, address, uint24)
        );

        // repay borrowed amount to aave position
        IERC20(asset).approve(address(pool), type(uint256).max);
        pool.repay(asset, amount, 2, onBehalfOf);

        if (onBehalfOf != address(this)) {
            address aSupplyToken = aSupplyTokenAddress(supplyToken, pool);
            uint256 supplyAmount = IAToken(aSupplyToken).balanceOf(onBehalfOf);
            IAToken(aSupplyToken).transferFrom(
                onBehalfOf,
                address(this),
                supplyAmount
            );
        }

        // withdraw max suplyAmount from aave position
        pool.withdraw(supplyToken, type(uint256).max, address(this));

        uint256 amountOwing = amount + premium;
        // cache for avoiding stack too deep error
        address _asset = asset;

        // swap withdrawed supplyToken for debtToken for repay loaned amount
        IERC20(supplyToken).approve(address(uniswapRouter), type(uint256).max);
        uniswapRouter.exactOutputSingle(
            IV3SwapRouter.ExactOutputSingleParams({
                tokenIn: supplyToken,
                tokenOut: _asset,
                fee: poolFee,
                recipient: address(this),
                amountOut: amountOwing,
                amountInMaximum: type(uint256).max,
                sqrtPriceLimitX96: 0
            })
        );
        IERC20(asset).approve(address(pool), amountOwing);

        emit AaveFlashLoan();
        return true;
    }

    // =========================
    // View Functions
    // =========================

    /// @dev Retrieves the amount of `supplyToken` supplied by a user to Aave.
    /// @param supplyToken The address of the supply token.
    /// @param user The address of the user.
    /// @return The amount supplied by the user.
    function getSupplyAmount(
        address supplyToken,
        address user
    ) internal view returns (uint256) {
        return IAToken(supplyToken).balanceOf(user);
    }

    /// @dev Retrieves the total debt of a user in a `debtToken`.
    /// @param debtToken The address of the debt token.
    /// @param user The address of the user.
    /// @return The total debt of the user in the specified token.
    function getTotalDebt(
        address debtToken,
        address user
    ) internal view returns (uint256) {
        return IERC20(debtToken).balanceOf(user);
    }

    /// @dev Retrieves the current health factor of a user in Aave.
    /// @param user The address of the user.
    /// @param poolAddressesProvider The provider of pool addresses for Aave.
    /// @return currentHF The current health factor of the user.
    function getCurrentHF(
        address user,
        IPoolAddressesProvider poolAddressesProvider
    ) internal view returns (uint256 currentHF) {
        (, , , , , currentHF) = IPool(poolAddressesProvider.getPool())
            .getUserAccountData(user);
    }

    /// @dev Retrieves the current liquidation threshold for a `token` in Aave.
    /// @param token The address of the token.
    /// @param poolAddressesProvider The provider of pool addresses for Aave.
    /// @return currentLiquidationThreshold_1e4 The current liquidation threshold for the token.
    function getCurrentLiquidationThreshold(
        address token,
        IPoolAddressesProvider poolAddressesProvider
    ) internal view returns (uint256 currentLiquidationThreshold_1e4) {
        IPoolDataProvider poolDataProvider = IPoolDataProvider(
            poolAddressesProvider.getPoolDataProvider()
        );
        (, , currentLiquidationThreshold_1e4, , , , , , , ) = poolDataProvider
            .getReserveConfigurationData(token);
    }

    /// @dev Retrieves the Aave debt token address for a specific `asset`.
    /// @param asset The address of the asset.
    /// @param pool The Aave pool instance.
    /// @return The address of the Aave debt token for the asset.
    function aDebtTokenAddress(
        address asset,
        IPool pool
    ) internal view returns (address) {
        return pool.getReserveData(asset).variableDebtTokenAddress;
    }

    /// @dev Retrieves the Aave supply token address for a specific `asset`.
    /// @param asset The address of the asset.
    /// @param pool The Aave pool instance.
    /// @return The address of the Aave supply token for the asset.
    function aSupplyTokenAddress(
        address asset,
        IPool pool
    ) internal view returns (address) {
        return pool.getReserveData(asset).aTokenAddress;
    }
}

