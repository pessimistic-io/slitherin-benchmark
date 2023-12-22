// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TokenExposure} from "./TokenExposure.sol";
import {GlpTokenAllocation} from "./GlpTokenAllocation.sol";

interface IGlpUtils {
    function getGlpTokenAllocations(address[] memory tokens)
        external
        view
        returns (GlpTokenAllocation[] memory);

    function getGlpTokenExposure(
        uint256 glpPositionWorth,
        address[] memory tokens
    ) external view returns (TokenExposure[] memory);
}

