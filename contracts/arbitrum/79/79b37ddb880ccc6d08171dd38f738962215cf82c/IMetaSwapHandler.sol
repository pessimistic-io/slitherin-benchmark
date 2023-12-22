// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import { ICoreSwapHandlerV1 } from "./ICoreSwapHandlerV1.sol";

interface IMetaSwapHandler is ICoreSwapHandlerV1 {
    struct MetaSwapParams {
        uint256 deadline;
        address underlyingSwapRouterAddress;
        bytes swapData;
    }

    function removeFromWhitelist(address[] memory swapContracts) external;

    function addToWhitelist(address[] memory swapContracts) external;
}

