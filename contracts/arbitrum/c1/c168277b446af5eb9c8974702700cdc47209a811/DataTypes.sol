// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import {IERC20} from "./IERC20.sol";
import {ILiabilityToken} from "./ILiabilityToken.sol";
import {IAssetToken} from "./IAssetToken.sol";

library DataTypes {
    //@dev Uniswap requires the address of token0 < token1.
    //@dev All oracle prices by uniswap are given as a ratio of token0/token1.
    struct DexPoolData {
        address token0;
        address token1;
        uint24 fee;
        bool moneyIsToken0; //indicates whether token0 is the money token
        address poolAddress;
    }

    struct DexOracleData {
        address dexFactory; // Uniswap v3 factory
        DexPoolData dex; // Dex pool details
        uint256 currentPrice;
        uint256 TWAPPrice;
        uint256 lastTWAPObservationTime; // Timestamp of last oracle consult for TWAP price
        uint256 lastCurrentObservationTime; // Timestamp of last oracle consult for current price
        int56 lastTWAPTickCumulative; //For Uniswap v3.0 TWAP calculation
        uint256 lastTWAPTimeDelta; //recording of last time delta
    }

    struct PerpetualDebtData {
        //stores the perpetual debt configuration
        PerpDebtConfigurationMap configuration;
        //Token addresses
        IAssetToken zToken;
        ILiabilityToken dToken;
        IERC20 money;
        //beta multiplier, indicating duration of debt instrument
        uint256 beta;
        //Dex Oracle
        DexOracleData dexOracle;
        //last refinance block number
        uint256 lastRefinance;
        //Price limit variables when refinancing
        uint256 notionalPriceMax; //[ray]
        uint256 notionalPriceMin; //[ray]
    }

    struct CollateralData {
        //stores the collateral configuration
        CollateralConfigurationMap configuration;
        //the id of the collateral. Represents the position in the list of the active ERC20 collaterals
        uint16 id;
        //map of user balances (for a given collateral)
        mapping(address => uint256) balances;
        //total collateral balance held by the Guild
        uint256 totalBalance;
    }

    struct CollateralConfigurationMap {
        //bit 0-15: LTV
        //bit 16-31: Liq. threshold
        //bit 32-47: Liq. bonus
        //bit 48-55: Decimals
        //bit 56: collateral is active
        //bit 57-115: unused
        //bit 116-151: supply cap in whole tokens, supplyCap == 0 => no cap
        //bit 152-167: liquidation protocol fee
        //bit 168-255: unused

        uint256 data;
    }

    struct PerpDebtConfigurationMap {
        //bit 0: perpetual debt is paused (no mint, no burn/distribute, no liquidate, no refinance)
        //bit 1: perpetual debt is frozen (no mint, yes burn/distribute, yes liquidate, yes refinance)
        //bit 2-37: borrow cap in whole tokens, borrowCap ==0 => no cap
        //bit 38-255: unused

        uint256 data;
    }

    struct ExecuteDepositParams {
        address asset;
        uint256 amount;
        address onBehalfOf;
    }

    struct ExecuteWithdrawParams {
        address asset;
        uint256 amount;
        address to;
        uint256 collateralsCount;
        address oracle;
    }

    struct ExecuteSupplyParams {
        address collateral;
        uint256 amount;
        address user;
    }

    struct ExecuteBorrowParams {
        address user;
        address onBehalfOf;
        uint256 amount;
        uint256 collateralsCount;
        address oracle;
        // address priceOracleSentinel;
    }

    struct ExecuteRepayParams {
        address onBehalfOf;
        uint256 amount;
    }

    struct CalculateUserAccountDataParams {
        uint256 collateralsCount;
        address user;
        address oracle;
    }

    struct ValidateBorrowParams {
        address user;
        uint256 amount;
        uint256 collateralsCount;
        address oracle;
    }

    struct ValidateBorrowLocalVars {
        uint256 currentLtv;
        uint256 collateralNeededInBaseCurrency;
        uint256 userCollateralInBaseCurrency;
        uint256 userDebtInBaseCurrency;
        uint256 availableLiquidity;
        uint256 healthFactor;
        uint256 totalDebt;
        uint256 totalSupplyVariableDebt;
        uint256 reserveDecimals;
        uint256 borrowCap;
        uint256 amountInBaseCurrency;
        address eModePriceSource;
        address siloedBorrowingAddress;
    }

    struct ExecuteLiquidationCallParams {
        uint256 collateralsCount;
        uint256 debtNotionalToCover;
        address collateralAsset;
        address user;
        bool receiveCollateral;
        address priceOracle;
    }

    struct ValidateLiquidationCallParams {
        uint256 totalDebtNotional;
        uint256 healthFactor;
    }

    struct ProxyStep {
        address assetToken;
        address baseToken;
        address proxySource;
    }

    struct PriceSourceData {
        address tokenA;
        address tokenB;
        address priceSource;
    }
}

