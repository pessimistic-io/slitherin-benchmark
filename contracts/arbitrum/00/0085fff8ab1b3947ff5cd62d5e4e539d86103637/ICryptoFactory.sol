// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICryptoFactory {
    function get_coins(address _pool) external view returns (address[2] memory);

    function get_coin_indices(address _pool, address _from, address _to) external view returns (uint256, uint256);
}

