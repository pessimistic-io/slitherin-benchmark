// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

import "./INonfungiblePositionManager.sol";
import "./ISwapRouter.sol";
import "./IUniswapV3Pool.sol";

/// @title UniRef interface
/// @author Ring Protocol
interface IUniRef {
    // ----------- Events -----------

    event PoolUpdate(address indexed _pool);

    // ----------- Governor only state changing api -----------

    function setPool(address _pool) external;

    // ----------- Getters -----------

    function nft() external view returns (INonfungiblePositionManager);

    function router() external view returns (ISwapRouter);

    function pool() external view returns (IUniswapV3Pool);

    function tokenId() external view returns (uint256);

    function token() external view returns (address);

    function liquidityOwned() external view returns (uint128);
}

