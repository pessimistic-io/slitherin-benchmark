// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


interface INonfungiblePositionManager {

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);

    function transferFrom(address from, address to, uint256 tokenID) external;
    
}
