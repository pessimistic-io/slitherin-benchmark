pragma solidity >= 0.8.0;

library Constants {
    // common precision for fee, tax, interest rate, maintenace margin ratio
    uint256 public constant PRECISION = 1e10;
    uint256 public constant LP_INITIAL_PRICE = 1e12; // fix to 1$
    uint256 public constant MAX_BASE_SWAP_FEE = 1e8; // 1%
    uint256 public constant MAX_TAX_BASIS_POINT = 1e8; // 1%
    uint256 public constant MAX_POSITION_FEE = 1e8; // 1%
    uint256 public constant MAX_LIQUIDATION_FEE = 10e30; // 10$
    uint256 public constant MAX_TRANCHES = 3;
    uint256 public constant MAX_ASSETS = 10;
    uint256 public constant MAX_INTEREST_RATE = 1e7; // 0.1%
    uint256 public constant MAX_MAINTENANCE_MARGIN = 5e8; // 5%
    uint256 public constant USD_VALUE_DECIMAL = 5e8; // 5%
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
}

