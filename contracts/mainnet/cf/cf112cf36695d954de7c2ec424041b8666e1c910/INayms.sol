// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// solhint-disable no-empty-blocks

import { IDiamondCut } from "./IDiamondCut.sol";
import { IDiamondLoupe } from "./IDiamondLoupe.sol";
import { IERC165 } from "./IERC165.sol";
import { IERC173 } from "./IERC173.sol";

import { IACLFacet } from "./IACLFacet.sol";
import { IUserFacet } from "./IUserFacet.sol";
import { IAdminFacet } from "./IAdminFacet.sol";
import { ISystemFacet } from "./ISystemFacet.sol";
import { INaymsTokenFacet } from "./INaymsTokenFacet.sol";
import { ITokenizedVaultFacet } from "./ITokenizedVaultFacet.sol";
import { ITokenizedVaultIOFacet } from "./ITokenizedVaultIOFacet.sol";
import { IMarketFacet } from "./IMarketFacet.sol";
import { IEntityFacet } from "./IEntityFacet.sol";
import { ISimplePolicyFacet } from "./ISimplePolicyFacet.sol";
import { IGovernanceFacet } from "./IGovernanceFacet.sol";

/**
 * @title Nayms Diamond
 * @notice Everything is a part of one big diamond.
 * @dev Every facet should be cut into this diamond.
 */
interface INayms is
    IDiamondCut,
    IDiamondLoupe,
    IERC165,
    IERC173,
    IACLFacet,
    IAdminFacet,
    IUserFacet,
    ISystemFacet,
    INaymsTokenFacet,
    ITokenizedVaultFacet,
    ITokenizedVaultIOFacet,
    IMarketFacet,
    IEntityFacet,
    ISimplePolicyFacet,
    IGovernanceFacet
{

}

