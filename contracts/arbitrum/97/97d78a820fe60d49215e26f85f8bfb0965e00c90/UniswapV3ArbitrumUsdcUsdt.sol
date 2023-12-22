// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./ERC20_IERC20.sol";
import {ERC721Holder} from "./ERC721Holder.sol";
import {IERC721Enumerable} from "./IERC721Enumerable.sol";

import {DefiiWithParams} from "./DefiiWithParams.sol";
import "./console.sol";

contract UniswapV3ArbitrumUsdcUsdt is DefiiWithParams, ERC721Holder {
    INonfungiblePositionManager constant nfpManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    IERC20 constant USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IERC20 constant USDT = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);

    /// @notice Encode params for enterWithParamas function
    /// @param tickLower Left tick for position
    /// @param tickUpper Right tick for position
    /// @param fee The pool's fee in hundredths of a bip, i.e. 1e-6 (e.g 100 for 0.01%)
    /// @return encodedParams Encoded params for enterWithParams function
    function encodeParams(
        int24 tickLower,
        int24 tickUpper,
        uint24 fee
    ) external pure returns (bytes memory encodedParams) {
        encodedParams = abi.encode(tickLower, tickUpper, fee);
    }

    function hasAllocation() external view override returns (bool) {
        return nfpManager.balanceOf(address(this)) > 0;
    }

    function _enterWithParams(bytes memory params) internal override {
        (int24 tickLower, int24 tickUpper, uint24 fee) = abi.decode(
            params,
            (int24, int24, uint24)
        );
        uint256 usdcAmount = USDC.balanceOf(address(this));
        uint256 usdtAmount = USDT.balanceOf(address(this));

        USDC.approve(address(nfpManager), usdcAmount);
        USDT.approve(address(nfpManager), usdtAmount);

        INonfungiblePositionManager.MintParams
            memory mintParams = INonfungiblePositionManager.MintParams({
                token0: address(USDT),
                token1: address(USDC),
                fee: fee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: usdtAmount,
                amount1Desired: usdcAmount,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            });

        nfpManager.mint(mintParams);
    }

    function _exit() internal override {
        INonfungiblePositionManager.DecreaseLiquidityParams
            memory decreaseParams;
        INonfungiblePositionManager.CollectParams memory collectParams;
        uint256 numPositions = nfpManager.balanceOf(address(this));
        for (uint256 i = 0; i < numPositions; i++) {
            uint256 positionId = nfpManager.tokenOfOwnerByIndex(
                address(this),
                i
            );

            (, , , , , , , uint128 positionLiquidity, , , , ) = nfpManager
                .positions(positionId);
            decreaseParams.tokenId = positionId;
            decreaseParams.liquidity = positionLiquidity;
            decreaseParams.amount0Min = 0;
            decreaseParams.amount1Min = 0;
            decreaseParams.deadline = block.timestamp;
            nfpManager.decreaseLiquidity(decreaseParams);

            collectParams.tokenId = positionId;
            collectParams.recipient = address(this);
            collectParams.amount0Max = type(uint128).max;
            collectParams.amount1Max = type(uint128).max;
            nfpManager.collect(collectParams);
            nfpManager.burn(positionId);
        }
    }

    function _harvest() internal override {
        INonfungiblePositionManager.CollectParams memory collectParams;
        uint256 numPositions = nfpManager.balanceOf(address(this));
        for (uint256 i = 0; i < numPositions; i++) {
            uint256 positionId = nfpManager.tokenOfOwnerByIndex(
                address(this),
                i
            );

            collectParams.tokenId = positionId;
            collectParams.recipient = address(this);
            collectParams.amount0Max = type(uint128).max;
            collectParams.amount1Max = type(uint128).max;
            nfpManager.collect(collectParams);
        }
        _withdrawFunds();
    }

    function _withdrawFunds() internal override {
        withdrawERC20(USDC);
        withdrawERC20(USDT);
    }
}

interface INonfungiblePositionManager is IERC721Enumerable {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);

    function burn(uint256 tokenId) external payable;

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function collect(CollectParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);
}

