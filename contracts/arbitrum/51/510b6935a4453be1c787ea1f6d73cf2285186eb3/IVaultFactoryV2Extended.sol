// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IVaultFactoryV2.sol";

interface IVaultFactoryV2Extended is IVaultFactoryV2 {
    function getEpochsByMarketId(
        uint256
    ) external view returns (uint256[] memory);

    function marketIdInfo(
        uint256
    ) external view returns (address, uint256, address);
}

