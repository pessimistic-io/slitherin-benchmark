// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IRiskManager {
    /// @notice Emitted when pendingAdmin is changed
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /// @notice Emitted when pendingAdmin is accepted, which means admin is updated
    event NewAdmin(address oldAdmin, address newAdmin);

    /// @notice Emitted when an admin supports a market
    event MarketListed(address fToken);

    /// @notice Emitted when an account enters a market
    event MarketEntered(address fToken, address account);

    /// @notice Emitted when an account exits a market
    event MarketExited(address fToken, address account);

    /// @notice Emitted when close factor is changed by admin
    event NewCloseFactor(
        uint256 oldCloseFactorMantissa,
        uint256 newCloseFactorMantissa
    );

    /// @notice Emitted when a collateral factor is changed by admin
    event NewCollateralFactor(
        address fToken,
        uint256 oldCollateralFactorMantissa,
        uint256 newCollateralFactorMantissa
    );

    /// @notice Emitted when a liquidation factor is changed by admin
    event NewLiquidationFactor(
        address fToken,
        uint256 oldLiquidationFactorMantissa,
        uint256 newLiquidationFactorMantissa
    );

    /// @notice Emitted when price oracle is changed
    event NewPriceOracle(address oldPriceOracle, address newPriceOracle);

    event NewVeToken(address oldVeToken, address newVeToken);

    event NewLiquidationIncentive(uint256 oldIncentiveMantissa, uint256 newIncentiveMantissa);

    event NewBoostIncrease(uint256 oldIncreaseMantissa, uint256 newIncreaseMantissa);

    event NewBoostRequired(uint256 oldRequiredToken, uint256 newRequiredToken);

    /// @notice Emitted when an action is paused globally
    event ActionPausedGlobal(string action, bool pauseState);

    /// @notice Emitted when an action is paused on a market
    event ActionPausedMarket(address fToken, string action, bool pauseState);

    function isRiskManager() external returns (bool);

    function getMarketsEntered(
        address _account
    ) external view returns (address[] memory);

    function checkListed(address _fToken) external view returns (bool);

    function enterMarkets(address[] memory _fTokens) external;

    function exitMarket(address _fToken) external;

    function supplyAllowed(address _fToken) external view returns (bool);

    function redeemAllowed(
        address _fToken,
        address _redeemer,
        uint256 _redeemTokens
    ) external view returns (bool);

    function borrowAllowed(
        address _fToken,
        address _borrower,
        uint256 _borrowAmount
    ) external returns (bool);

    function repayBorrowAllowed(address _fToken) external returns (bool);

    function liquidateBorrowAllowed(
        address _fTokenBorrowed,
        address _fTokenCollateral,
        address _borrower,
        uint256 _repayAmount
    ) external view returns (bool);

    function delegateLiquidateBorrowAllowed(
        address _fTokenBorrowed,
        address _fTokenCollateral,
        address _borrower,
        uint256 _repayAmount
    ) external view returns (bool);

    function seizeAllowed(
        address _fTokenCollateral,
        address _fTokenBorrowed,
        address _borrower,
        uint256 _seizeTokens
    ) external view returns (bool allowed);

    function transferAllowed(
        address _fToken,
        address _src,
        uint256 _amount
    ) external view returns (bool);

    function liquidateCalculateSeizeTokens(
        address _fTokenBorrowed,
        address _fTokenCollateral,
        uint256 _repayAmount
    ) external view returns (uint256 seizeTokens);

    function getAccountLiquidity(
        address _account
    )
        external
        view
        returns (
            uint256 liquidity,
            uint256 shortfallCollateral,
            uint256 shortfallLiquidation,
            uint256 healthFactor
        );

    function getMarketInfo(
        address _ftoken
    ) external view returns (uint256, uint256);
}

