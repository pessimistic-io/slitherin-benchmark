// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";

interface ICrv2Pool is IERC20 {
    function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount)
        external
        returns (uint256);

    function remove_liquidity_one_coin(
        uint256 _token_amount,
        int128 i,
        uint256 min_amount
    ) external returns (uint256);

    function get_virtual_price() external view returns (uint256);
}

