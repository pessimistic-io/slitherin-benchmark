// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


interface ICurvePool { 
    function add_liquidity(uint256[] calldata uamounts, uint256 min_mint_amount, address receiver) external;
    function add_liquidity(uint256[] calldata uamounts, uint256 min_mint_amount, bool _use_underlying) external;
    function remove_liquidity(uint256 _amount, uint256[] calldata min_uamounts) external;
    function remove_liquidity_imbalance(uint256[] calldata uamounts, uint256 max_burn_amount) external;
    function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 min_uamount, bool _use_underlying) external;
    function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 min_uamount, address receiver) external;

    function coins(uint256 i) external view returns (address);
    function underlying_coins(uint256 i) external view returns (address);
    function curve() external view returns (address);
    function token() external view returns (address);
    function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external;
    function exchange_underlying(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external;
}
