// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICryptoRegistry {
    function get_coin_indices(address _pool, address _from, address _to) external view returns (uint256, uint256);

    function get_coins(address _pool) external view returns (address[8] memory);

    function get_n_coins(address _pool) external view returns (uint256);
}

