// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.16;

interface IStabilizer {
    // Getters
    function sweep_borrowed() external view returns (uint256);
    function minimum_equity_ratio() external view returns (uint256);
    function loan_limit() external view returns (uint256);
    function repayment_date() external view returns (uint256);
    function borrower() external view returns (address);
    function settings_manager() external view returns (address);
    function spread_ratio() external view returns (uint256);
    function spread_payment_time() external view returns (uint256);
    function frozen() external view returns (bool);

    function isDefaulted() external view returns (bool);
    function getSpreadValue() external view returns (uint256);
    function getJuniorTrancheValue() external view returns (int256);
    function getEquityRatio() external view returns (uint256);

    // Setters
    function configure(
        address asset,
        uint256 minimum_equity_ratio,
        uint256 spread_ratio,
        uint256 max_mint_amount,
        string calldata url_link
    ) external;
    function propose() external;
    function reject() external;
    function setSpreadRatio(uint256 spread_ratio) external;
    function setMinimumEquityRatio(uint256 minimum_equity_ratio) external;
    function setAsset(address asset) external;
    function setLoanLimit(uint256 _loan_limit) external;
    function setRepaymentDate(uint32 days_from_now) external;
    function setFrozen(bool frozen) external;
    function setBorrower(address borrower) external;

    // Actions
    function invest(uint256 amount0, uint256 amount1) external;
    function buySWEEP(uint256 usdx_amount) external;
    function sellSWEEP(uint256 sweep_amount) external;
    function buy(uint256 usdx_amount, uint256 amount_out_min) external returns(uint256);
    function sell(uint256 sweep_amount, uint256 amount_out_min) external returns(uint256);
    function mint(uint256 sweep_amount) external;
    function burn(uint256 sweep_amount) external;
    function repay(uint256 sweep_amount) external;
    function payback(uint256 usdx_amount) external;
    function withdraw(address token, uint256 amount) external;
    function collect() external;
    function paySpread() external;
    function liquidate(uint256 sweep_amount) external;
}

