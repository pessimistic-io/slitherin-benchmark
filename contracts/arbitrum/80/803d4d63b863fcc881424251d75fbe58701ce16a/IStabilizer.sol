// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.16;

interface IStabilizer {
    // Getters
    function sweep_borrowed() external view returns (uint256);

    function min_equity_ratio() external view returns (int256);

    function loan_limit() external view returns (uint256);

    function call_time() external view returns (uint256);

    function call_delay() external view returns (uint256);

    function call_amount() external view returns (uint256);

    function borrower() external view returns (address);

    function settings_enabled() external view returns (bool);

    function spread_fee() external view returns (uint256);

    function spread_date() external view returns (uint256);

    function liquidator_discount() external view returns (uint256);

    function liquidatable() external view returns (bool);

    function frozen() external view returns (bool);

    function isDefaulted() external view returns (bool);

    function getCurrentValue() external view returns (uint256);
    
    function getDebt() external view returns (uint256);

    function accruedFee() external view returns (uint256);

    function getJuniorTrancheValue() external view returns (int256);

    function getEquityRatio() external view returns (int256);

    // Setters
    function configure(
        address asset,
        int256 min_equity_ratio,
        uint256 spread_fee,
        uint256 loan_limit,
        uint256 liquidator_discount,
        uint256 call_delay,
        bool liquidatable,
        string calldata link
    ) external;

    function propose() external;

    function reject() external;

    function setFrozen(bool frozen) external;

    function setBorrower(address borrower) external;

    // Actions
    function invest(uint256 amount0, uint256 amount1) external;

    function divest(uint256 usdx_amount) external;

    function buySWEEP(uint256 usdx_amount) external;

    function sellSWEEP(uint256 sweep_amount) external;

    function buy(uint256 usdx_amount, uint256 amount_out_min)
        external
        returns (uint256);

    function sell(uint256 sweep_amount, uint256 amount_out_min)
        external
        returns (uint256);

    function borrow(uint256 sweep_amount) external;

    function repay(uint256 sweep_amount) external;

    function withdraw(address token, uint256 amount) external;

    function collect() external;

    function payFee() external;

    function liquidate() external;

    function marginCall(uint256 amount) external;
}

