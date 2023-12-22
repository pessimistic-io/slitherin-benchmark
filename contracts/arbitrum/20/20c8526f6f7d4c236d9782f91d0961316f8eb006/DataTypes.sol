// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IPriceOracle.sol";

library DataTypes {
    struct Synth {
        bool isActive;
        bool isDisabled;
        uint256 mintFee;
        uint256 burnFee;
    }

    /// @notice Collateral data structure
    struct Collateral {
        bool isActive;         // Checks if collateral is enabled
        uint256 cap;            // Maximum amount of collateral that can be deposited
        uint256 totalDeposits;  // Total amount of collateral deposited
        uint256 baseLTV;        // Base loan to value ratio (in bps) 80% = 8000
        uint256 liqThreshold;   // Liquidation threshold (in bps) 90% = 9000
        uint256 liqBonus;       // Liquidation bonus (in bps) 105% = 10500
    }

    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }

    struct AccountLiquidity {
        int256 liquidity;
        uint256 collateral;
        uint256 debt;
    }

    struct VarsLiquidity {
        IPriceOracle oracle;
        address collateral;
        uint price;
        address[] _accountPools;
    }

    struct Vars_Mint {
        uint amountPlusFeeUSD;
        uint _borrowCapacity;
        address[] tokens;
        uint[] prices;
    }

    struct Vars_Burn {
        uint amountUSD;
        uint debt;
        address[] tokens;
        uint[] prices;
    }

    struct Vars_Liquidate {
        AccountLiquidity liq;
        Collateral collateral;
        uint ltv;
        address[] tokens;
        uint[] prices;
        uint amountUSD;
        uint debtUSD;
        uint amountOut;
        uint penalty;
        uint refundOut;
    }
}
