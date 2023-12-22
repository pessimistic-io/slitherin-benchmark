// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Clones.sol";
import "./SafeERC20.sol";

import "./IUniswapV3Pool.sol";
import "./INonfungiblePositionManager.sol";
import "./ISwapRouter.sol";

import "./UniV3Token.sol";

contract UniV3TokenRegistry {
    using SafeERC20 for IERC20;
    UniV3Token public immutable singleton;
    uint256 public numberOfTokens = 1;

    // returns registry id of token by its address
    mapping(address => uint256) public ids;
    mapping(uint256 => UniV3Token) public tokenById;

    constructor(INonfungiblePositionManager positionManager_, ISwapRouter router_) {
        singleton = new UniV3Token(positionManager_, router_, UniV3TokenRegistry(address(this)));
    }

    function createToken(bytes memory params) external returns (uint256 currentTokenId, UniV3Token token) {
        currentTokenId = numberOfTokens++;
        token = UniV3Token(Clones.cloneDeterministic(address(singleton), bytes32(currentTokenId)));
        (address token0, address token1, , , , , ) = abi.decode(
            params,
            (address, address, uint24, int24, int24, string, string)
        );

        IERC20(token0).safeApprove(address(token), type(uint256).max);
        IERC20(token1).safeApprove(address(token), type(uint256).max);

        token.initialize(params);
        ids[address(token)] = currentTokenId;
        tokenById[currentTokenId] = token;

        IERC20(address(token)).safeTransfer(msg.sender, token.balanceOf(address(this)));

        IERC20(token0).safeApprove(address(token), 0);
        IERC20(token1).safeApprove(address(token), 0);
    }
}

