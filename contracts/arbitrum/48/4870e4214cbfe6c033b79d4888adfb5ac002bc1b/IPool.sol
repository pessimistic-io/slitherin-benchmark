// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface IPool {
    function add_liquidity(uint[2] memory amounts, uint _min_mint_amount) external returns (uint);

    function add_liquidity(uint[3] memory amounts, uint _min_mint_amount) external;

    function add_liquidity(uint[3] memory amounts, uint _min_mint_amount, bool _use_underlying) external returns (uint);

    function add_liquidity(uint[5] memory amounts, uint _min_mint_amount) external;

    function remove_liquidity_one_coin(uint _token_amount, uint i, uint _min_amount) external;

    function remove_liquidity_one_coin(uint _token_amount, int128 i, uint _min_amount) external returns (uint);

    function remove_liquidity_one_coin(uint _token_amount, int128 i, uint _min_amount, bool _use_underlying) external returns (uint);

    function lp_token() external view returns (address);

    function pool() external view returns (address);

    function base_pool() external view returns (address);

    function get_virtual_price() external view returns (uint);

    function balances(uint i) external view returns (uint);
    
    function price_oracle(uint i) external view returns (uint);

    function calc_token_amount(uint[2] memory amounts, bool deposit) external view returns (uint);

    function calc_token_amount(uint[3] memory amounts, bool deposit) external view returns (uint);

    function calc_token_amount(uint[5] memory amounts, bool deposit) external view returns (uint);

    function calc_withdraw_one_coin(uint token_amount, int128 i) external view returns (uint);

    function calc_withdraw_one_coin(uint token_amount, uint i) external view returns (uint);
}

