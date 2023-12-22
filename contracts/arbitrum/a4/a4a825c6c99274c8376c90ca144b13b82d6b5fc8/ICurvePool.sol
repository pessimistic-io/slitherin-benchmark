// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.19;

import "./IERC20Full.sol";

interface ICurvePool
{
    function coins(uint256 index) external view returns (IERC20Full);
    function balances(uint256 index) external view returns (uint256);
    function get_virtual_price() external view returns (uint256);
    function calc_withdraw_one_coin(uint256 amount, int128 index) external view returns (uint256);
    
    function fee() external view returns (uint256);

    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns (uint256);

    function calc_token_amount(uint256[2] memory amounts, bool isDeposit) external view returns (uint256);
    function calc_token_amount(uint256[3] memory amounts, bool isDeposit) external view returns (uint256);
    function calc_token_amount(uint256[4] memory amounts, bool isDeposit) external view returns (uint256);

    function remove_liquidity(uint256 amount, uint256[2] memory minAmounts) external returns (uint256[2] memory receivedAmounts);
    function remove_liquidity(uint256 amount, uint256[3] memory minAmounts) external returns (uint256[3] memory receivedAmounts);
    function remove_liquidity(uint256 amount, uint256[4] memory minAmounts) external returns (uint256[4] memory receivedAmounts);
}

