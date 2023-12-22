// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IVaultFactoryV2Extended.sol";

interface ICarouselFactoryExtended is IVaultFactoryV2Extended {
    function emissionsToken() external view returns (address);
}

