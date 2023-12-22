// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ExponentialNoError.sol";
import "./IPriceOracle.sol";
import "./IERC20.sol";

contract RiskManagerStorage is ExponentialNoError {
    bool public constant IS_RISK_MANAGER = true;

    // closeFactorMantissa must be strictly greater than this value
    uint256 internal constant CLOSE_FACTOR_MIN_MANTISSA = 5e16; // 5%

    // closeFactorMantissa must not exceed this value
    uint256 internal constant CLOSE_FACTOR_MAX_MANTISSA = 9e17; // 90%

    // No collateralFactorMantissa may exceed this value
    uint256 internal constant COLLATERAL_FACTOR_MAX_MANTISSA = 9e17; // 90%

    uint256 internal constant COLLATERAL_FACTOR_MAX_BOOST_MANTISSA = 2.5e16; // 2.5%

    uint256 internal constant LIQUIDATION_FACTOR_MAX_MANTISSA = 9e17; // 90%

    /// @notice Administrator for this contract
    address public admin;

    /// @notice Pending administrator for this contract
    address public pendingAdmin;

    IERC20 public veToken;

    /// @notice Oracle which gives the price of underlying assets
    IPriceOracle public oracle;

    uint256 public closeFactorMantissa;

    uint256 public liquidationIncentiveMantissa;

    uint256 public boostIncreaseMantissa;

    uint256 public boostRequiredToken;

    /// @notice List of assets an account has entered, capped by maxAssets
    mapping(address => address[]) public marketsEntered;

    struct Market {
        // Whether or not this market is listed
        bool isListed;
        //  Must be between 0 and 0.9, and stored as a mantissa
        //  For instance, 0.9 to allow borrowing 90% of collateral value
        uint256 collateralFactorMantissa;
        // Point (total collateral value / total borrow value) where account
        // will be liquidated. Between 0 and 0.9, and stored as mantissa.
        // Larger than or equal collateral factor
        uint256 liquidationFactorMantissa;
        // Whether or not an account is entered in this market
        mapping(address => bool) isMember;
    }

    /**
     * @notice Mapping of fTokens -> Market metadata
     * @dev Used e.g. to determine if a market is supported
     */
    mapping(address => Market) public markets;

    /**
     * @notice The Pause Guardian can pause certain actions as a safety mechanism.
     *
     * Actions which allow users to remove their own assets cannot be paused.
     * Liquidation / seizing / transfer can only be paused globally, not by market.
     */
    address public pauseGuardian;
    bool public _supplyGuardianPaused;
    bool public _borrowGuardianPaused;
    bool public transferGuardianPaused;
    bool public seizeGuardianPaused;
    mapping(address => bool) public supplyGuardianPaused;
    mapping(address => bool) public borrowGuardianPaused;

    /**
     * @dev Local vars for avoiding stack-depth limits in calculating account liquidity.
     *
     * Note: `tokenBalance` is the number of fTokens the account owns in the market,
     * `borrowBalance` is the amount of underlying that the account has borrowed.
     */
    struct AccountLiquidityLocalVars {
        address asset;
        uint256 tokenBalance;
        uint256 borrowBalance;
        uint256 exchangeRateMantissa;
        uint256 oraclePriceMantissa;
        // Maximum amount of borrow allowed, 
        // calculated using collateral factor
        uint256 sumCollateral;
        // Borrow value when account is susceptible to liquidation,
        // calculated using liquidation factor
        uint256 liquidationThreshold; 
        uint256 sumBorrowPlusEffect;
        uint256 sumBorrowPlusEffectLiquidation;
        Exp exchangeRate;
        Exp oraclePrice;
        Exp collateralFactor;
        Exp liquidationFactor;
        // Value of 1 fToken
        Exp valuePerToken;
        Exp collateralValuePerToken;
        Exp liquidationValuePerToken;
    }

     address public furionLeverage;
}

