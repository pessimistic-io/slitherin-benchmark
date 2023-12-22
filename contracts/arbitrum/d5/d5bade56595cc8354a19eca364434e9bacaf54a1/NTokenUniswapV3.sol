// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {IERC20} from "./IERC20.sol";
import {IERC721} from "./IERC721.sol";
import {IERC1155} from "./IERC1155.sol";
import {IERC721Metadata} from "./IERC721Metadata.sol";
import {Address} from "./Address.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SafeCast} from "./SafeCast.sol";
import {Errors} from "./Errors.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {IPool} from "./IPool.sol";
import {NToken} from "./NToken.sol";
import {DataTypes} from "./DataTypes.sol";
import {INonfungiblePositionManager} from "./INonfungiblePositionManager.sol";
import {IWETH} from "./IWETH.sol";
import {XTokenType} from "./IXTokenType.sol";
import {INTokenUniswapV3} from "./INTokenUniswapV3.sol";
import {Helpers} from "./Helpers.sol";

/**
 * @title UniswapV3 NToken
 *
 * @notice Implementation of the interest bearing token for the ParaSpace protocol
 */
contract NTokenUniswapV3 is NToken, INTokenUniswapV3 {
    using SafeERC20 for IERC20;

    /**
     * @dev Constructor.
     * @param pool The address of the Pool contract
     */
    constructor(IPool pool, address delegateRegistry)
        NToken(pool, true, delegateRegistry)
    {
        _ERC721Data.balanceLimit = 30;
    }

    function getXTokenType() external pure override returns (XTokenType) {
        return XTokenType.NTokenUniswapV3;
    }

    /**
     * @notice A function that decreases the current liquidity.
     * @param tokenId The id of the erc721 token
     * @param liquidityDecrease The amount of liquidity to remove of LP
     * @param amount0Min The minimum amount to remove of token0
     * @param amount1Min The minimum amount to remove of token1
     * @param receiveEthAsWeth If convert weth to ETH
     * @return amount0 The amount received back in token0
     * @return amount1 The amount returned back in token1
     */
    function _decreaseLiquidity(
        address user,
        uint256 tokenId,
        uint128 liquidityDecrease,
        uint256 amount0Min,
        uint256 amount1Min,
        bool receiveEthAsWeth
    ) internal returns (uint256 amount0, uint256 amount1) {
        if (liquidityDecrease > 0) {
            // amount0Min and amount1Min are price slippage checks
            // if the amount received after burning is not greater than these minimums, transaction will fail
            INonfungiblePositionManager.DecreaseLiquidityParams
                memory params = INonfungiblePositionManager
                    .DecreaseLiquidityParams({
                        tokenId: tokenId,
                        liquidity: liquidityDecrease,
                        amount0Min: amount0Min,
                        amount1Min: amount1Min,
                        deadline: block.timestamp
                    });

            INonfungiblePositionManager(_ERC721Data.underlyingAsset)
                .decreaseLiquidity(params);
        }

        (
            ,
            ,
            address token0,
            address token1,
            ,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = INonfungiblePositionManager(_ERC721Data.underlyingAsset).positions(
                tokenId
            );

        address weth = _addressesProvider.getWETH();
        receiveEthAsWeth = (receiveEthAsWeth &&
            (token0 == weth || token1 == weth));

        INonfungiblePositionManager.CollectParams
            memory collectParams = INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: receiveEthAsWeth ? address(this) : user,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (amount0, amount1) = INonfungiblePositionManager(
            _ERC721Data.underlyingAsset
        ).collect(collectParams);

        if (receiveEthAsWeth) {
            uint256 balanceWeth = IERC20(weth).balanceOf(address(this));
            if (balanceWeth > 0) {
                IWETH(weth).withdraw(balanceWeth);
                Helpers.safeTransferETH(user, balanceWeth);
            }

            address pairToken = (token0 == weth) ? token1 : token0;
            uint256 balanceToken = IERC20(pairToken).balanceOf(address(this));
            if (balanceToken > 0) {
                IERC20(pairToken).safeTransfer(user, balanceToken);
            }
        }
    }

    /// @inheritdoc INTokenUniswapV3
    function decreaseUniswapV3Liquidity(
        address user,
        uint256 tokenId,
        uint128 liquidityDecrease,
        uint256 amount0Min,
        uint256 amount1Min,
        bool receiveEthAsWeth
    ) external onlyPool nonReentrant {
        require(user == ownerOf(tokenId), Errors.NOT_THE_OWNER);

        // interact with Uniswap V3
        _decreaseLiquidity(
            user,
            tokenId,
            liquidityDecrease,
            amount0Min,
            amount1Min,
            receiveEthAsWeth
        );
    }

    function setTraitsMultipliers(uint256[] calldata, uint256[] calldata)
        external
        override
        onlyPoolAdmin
        nonReentrant
    {
        revert();
    }

    receive() external payable {}
}

