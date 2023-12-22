// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./EnumerableSet.sol";
import "./console.sol";

import "./AbstractPool.sol";
import "./ILendingPool.sol";

abstract contract AbstractLendingPool is ILendingPool, AbstractPool {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSet for EnumerableSet.AddressSet;

    // ==============================================================================================
    // Protocol Transactional Functions
    // ==============================================================================================
    /**
     * @dev Supplies an `amount` of underlying asset into the reserve, receiving in return overlying aTokens.
     * - E.g. User deposits 100 USDC and gets in return 100 aUSDC
     * @param assetAddress The address of the underlying asset to deposit
     * @param amount The amount to be deposited
     **/
    function supply(
        address assetAddress,
        uint256 amount
    ) virtual external;

    /**
     * @dev Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens owned
     * E.g. User has 100 aUSDC, calls withdraw() and receives 100 USDC, burning the 100 aUSDC
     * @param assetAddress The address of the underlying asset to withdraw
     * @param amount The underlying amount to be withdrawn
     *   - Send the value type(uint256).max in order to withdraw the whole aToken balance
     * @return The final amount withdrawn
     **/
    function withdraw(
        address assetAddress,
        uint256 amount
    ) virtual external returns (uint256);

    /**
     * @dev Allows users to borrow a specific `amount` of the reserve underlying asset, provided that the borrower
     * already deposited enough collateral, or he was given enough allowance by a credit delegator on the
     * corresponding debt token (StableDebtToken or VariableDebtToken)
     * - E.g. User borrows 100 USDC passing as `onBehalfOf` his own address, receiving the 100 USDC in his wallet
     *   and 100 stable/variable debt tokens, depending on the `interestRateMode`
     * @param assetAddress The address of the underlying asset to borrow
     * @param amount The amount to be borrowed
     * @param interestRateMode The interest rate mode at which the user wants to borrow: 1 for Stable, 2 for Variable
     **/
    function borrow(
        address assetAddress,
        uint256 amount,
        uint256 interestRateMode
    ) virtual external;

    /**
     * @notice Repays a borrowed `amount` on a specific reserve, burning the equivalent debt tokens owned
     * - E.g. User repays 100 USDC, burning 100 variable/stable debt tokens of the `onBehalfOf` address
     * @param assetAddress The address of the borrowed underlying asset previously borrowed
     * @param amount The amount to repay
     * - Send the value type(uint256).max in order to repay the whole debt for `asset` on the specific `debtMode`
     * @param interestRateMode The interest rate mode at of the debt the user wants to repay: 1 for Stable, 2 for Variable
     * @return The final amount repaid
     **/
    function repay(
        address assetAddress,
        uint256 amount,
        uint256 interestRateMode
    ) virtual external returns (uint256);

    // ==============================================================================================
    // Events
    // ==============================================================================================
    /**
     * @dev Emitted on withdrawAll()
     * @param actualTokenAmounts Amount reclaimed
     **/
    event WithdrawAll(
        address[] tokens,
        uint256[] actualTokenAmounts
    );

    /**
     * @dev Emitted on supply()
     * @param reserve The address of the underlying asset of the reserve
     * @param user The address initiating the deposit
     * @param amount The amount supplied
     **/
    event Supply(
        address indexed reserve,
        address user,
        uint256 amount
    );

    /**
     * @dev Emitted on withdraw()
     * @param reserve The address of the underlyng asset being withdrawn
     * @param user The address initiating the withdrawal, owner of aTokens
     * @param amount The amount to be withdrawn
     **/
    event Withdraw(
        address indexed reserve,
        address indexed user,
        uint256 amount
    );

    /**
     * @dev Emitted on borrow() when debt needs to be opened
     * @param reserve The address of the underlying asset being borrowed
     * @param user The address of the user initiating the borrow(), receiving the funds on borrow()
     * @param amount The amount borrowed out
     * @param borrowRateMode The rate mode: 1 for Stable, 2 for Variable
     **/
    event Borrow(
        address indexed reserve,
        address user,
        uint256 amount,
        uint256 borrowRateMode
    );

    /**
     * @dev Emitted on repay()
     * @param reserve The address of the underlying asset of the reserve
     * @param user The beneficiary of the repayment, getting his debt reduced
     * @param amount The amount repaid
     **/
    event Repay(
        address indexed reserve,
        address indexed user,
        uint256 amount
    );
}
