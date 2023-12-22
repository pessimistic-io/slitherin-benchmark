// SPDX-License-Identifier: BUSL-1.1
// Last deployed from commit: c192482da8ad844970da54d609babb69b9cca2a7;
pragma solidity 0.8.17;

import "./IERC20Metadata.sol";
import "./ReentrancyGuard.sol";
import "./AvalancheDataServiceConsumerBase.sol";
import "./ITokenManager.sol";
import "./Pool.sol";
import "./SolvencyFacetProd.sol";
import "./IStakingPositions.sol";
import "./ITraderJoeV2Facet.sol";
import "./INonfungiblePositionManager.sol";
import "./UniswapV3IntegrationHelper.sol";
import {PriceHelper} from "./PriceHelper.sol";
import {Uint256x256Math} from "./Uint256x256Math.sol";
import {TickMath} from "./TickMath.sol";
import {FullMath} from "./FullMath.sol";

//This path is updated during deployment
import "./DeploymentConstants.sol";
import "./IUniswapV3Facet.sol";

contract SolvencyFacetProdAvalanche is SolvencyFacetProd {
    function getDataServiceId() public view virtual override returns (string memory) {
        return "redstone-avalanche-prod";
    }

    function getUniqueSignersThreshold() public view virtual override returns (uint8) {
        return 3;
    }

    function getAuthorisedSignerIndex(
        address signerAddress
    ) public view virtual override returns (uint8) {
        if (signerAddress == 0x1eA62d73EdF8AC05DfceA1A34b9796E937a29EfF) {
            return 0;
        } else if (signerAddress == 0x2c59617248994D12816EE1Fa77CE0a64eEB456BF) {
            return 1;
        } else if (signerAddress == 0x12470f7aBA85c8b81D63137DD5925D6EE114952b) {
            return 2;
        } else if (signerAddress == 0x109B4a318A4F5ddcbCA6349B45f881B4137deaFB) {
            return 3;
        } else if (signerAddress == 0x83cbA8c619fb629b81A65C2e67fE15cf3E3C9747) {
            return 4;
        } else {
            revert SignerNotAuthorised(signerAddress);
        }
    }
}

