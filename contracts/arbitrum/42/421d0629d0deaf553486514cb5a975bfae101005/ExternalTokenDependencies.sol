// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

import "./IVeDEG.sol";
import "./IDegisToken.sol";
import "./CommonDependencies.sol";

import "./Initializable.sol";

/**
 * @notice External token dependencies
 *         Include the tokens that are not deployed by this repo
 *         DEG, veDEG
 *         They are set as immutable
 */
abstract contract ExternalTokenDependencies is
    CommonDependencies,
    Initializable
{
    IDegisToken internal deg;
    IVeDEG internal veDeg;

    function __ExternalToken__Init(address _deg, address _veDeg)
        internal
        onlyInitializing
    {
        deg = IDegisToken(_deg);
        veDeg = IVeDEG(_veDeg);
    }
}

