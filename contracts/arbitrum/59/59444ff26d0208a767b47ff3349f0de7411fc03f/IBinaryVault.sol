// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {IBinaryVaultBaseFacet} from "./IBinaryVaultBaseFacet.sol";
import {IBinaryVaultNFTFacet} from "./IBinaryVaultNFTFacet.sol";
import {IBinaryVaultLiquidityFacet} from "./IBinaryVaultLiquidityFacet.sol";
import {IBinaryVaultBetFacet} from "./IBinaryVaultBetFacet.sol";

interface IBinaryVault is IBinaryVaultBaseFacet, IBinaryVaultNFTFacet, IBinaryVaultLiquidityFacet, IBinaryVaultBetFacet {
   
}

