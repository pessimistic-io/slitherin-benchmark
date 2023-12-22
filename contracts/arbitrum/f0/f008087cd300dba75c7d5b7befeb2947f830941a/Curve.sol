// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

interface ICurveFi {
    function get_virtual_price() external view returns (uint256);

    function add_liquidity(
        // EURs
        uint256[2] calldata amounts,
        uint256 min_mint_amount
    ) external returns(uint256);

    function add_liquidity(
        // sBTC pool
        uint256[3] calldata amounts,
        uint256 min_mint_amount
    ) external returns(uint256);

    function add_liquidity(
        // bUSD pool
        uint256[4] calldata amounts,
        uint256 min_mint_amount
    ) external returns(uint256);

    function remove_liquidity_imbalance(uint256[4] calldata amounts, uint256 max_burn_amount) external returns(uint256);

    function remove_liquidity(uint256 _amount, uint256[4] calldata amounts) external returns(uint256);

    function remove_liquidity_one_coin(
        uint256 _token_amount,
        int128 i,
        uint256 min_amount
    ) external returns(uint256);

    function exchange(
        int128 from,
        int128 to,
        uint256 _from_amount,
        uint256 _min_to_amount
    ) external returns(uint256);

    function exchange_underlying(
        int128 from,
        int128 to,
        uint256 _from_amount,
        uint256 _min_to_amount
    ) external;

    function balances(int128) external view returns (uint256);

    function get_dy(
        int128 from,
        int128 to,
        uint256 _from_amount
    ) external view returns (uint256);
}

interface Zap {
    function remove_liquidity_one_coin(
        uint256,
        int128,
        uint256
    ) external;
}

