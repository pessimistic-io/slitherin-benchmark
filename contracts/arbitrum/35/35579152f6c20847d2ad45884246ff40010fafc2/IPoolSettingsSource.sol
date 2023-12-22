// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "./Pool.sol";
import "./IPoolSettingsSource.sol";
import "./ISwapper.sol";

interface IPoolSettingsSource {
    struct PoolSettings {
        ISwapper swapper;
    }
    function getPoolSettings() external view returns (PoolSettings memory) ;
}
