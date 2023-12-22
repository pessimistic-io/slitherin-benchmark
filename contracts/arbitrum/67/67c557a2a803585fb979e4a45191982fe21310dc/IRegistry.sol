// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IRegistry {
    function get_coin_indices(address _pool, address _from, address _to) external view returns (int128, int128, bool);

    function get_coins(address _pool) external view returns (address[8] memory);

    function get_n_coins(address _pool) external view returns (uint256[2] memory);
}

