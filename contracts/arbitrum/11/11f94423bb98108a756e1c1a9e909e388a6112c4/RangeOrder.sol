// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import {     IUniswapV3Pool } from "./IUniswapV3Pool.sol";
import {     INonfungiblePositionManager } from "./INonfungiblePositionManager.sol";
import {     IERC721Receiver } from "./IERC721Receiver.sol";
import {IWETH9} from "./IWETH9.sol";
import {IEjectLP} from "./IEjectLP.sol";
import {     IERC20,     SafeERC20 } from "./SafeERC20.sol";
import {Order, OrderParams} from "./SEject.sol";
import {RangeOrderParams} from "./SRangeOrder.sol";

contract RangeOrder is IERC721Receiver {
    using SafeERC20 for IERC20;

    IEjectLP public immutable eject;
    IWETH9 public immutable WETH9; // solhint-disable-line var-name-mixedcase
    address public immutable rangeOrderResolver;

    event LogSetRangeOrder(
        uint256 indexed tokenId,
        address pool,
        uint256 amountIn
    );

    // solhint-disable-next-line var-name-mixedcase, func-param-name-mixedcase
    constructor(
        IEjectLP eject_,
        IWETH9 WETH9_, // solhint-disable-line var-name-mixedcase, func-param-name-mixedcase
        address rangeOrderResolver_
    ) {
        eject = eject_;
        WETH9 = WETH9_;
        rangeOrderResolver = rangeOrderResolver_;
    }

    // solhint-disable-next-line function-max-lines
    function setRangeOrder(RangeOrderParams calldata params_) external payable {
        uint256 tokenId;
        address token0;
        address token1;
        uint24 fee;
        {
            int24 lowerTick;
            int24 upperTick;
            {
                int24 tickSpacing = params_.pool.tickSpacing();

                require(
                    params_.tickThreshold % tickSpacing == 0,
                    "RangeOrder:setRangeOrder:: threshold must be initializable tick"
                );

                lowerTick = params_.zeroForOne
                    ? params_.tickThreshold
                    : params_.tickThreshold - tickSpacing;
                upperTick = params_.zeroForOne
                    ? params_.tickThreshold + tickSpacing
                    : params_.tickThreshold;
            }

            _requireThresholdNotInRange(params_.pool, lowerTick, upperTick);

            token0 = params_.pool.token0();
            token1 = params_.pool.token1();
            fee = params_.pool.fee();

            INonfungiblePositionManager positions = eject.nftPositions();

            {
                IERC20 tokenIn = IERC20(params_.zeroForOne ? token0 : token1);

                if (msg.value > 0) {
                    require(
                        msg.value == params_.amountIn,
                        "RangeOrder:setRangeOrder:: Invalid amount in."
                    );
                    require(
                        address(tokenIn) == address(WETH9),
                        "RangeOrder:setRangeOrder:: ETH range order should use WETH token."
                    );

                    WETH9.deposit{value: msg.value}();
                } else
                    tokenIn.safeTransferFrom(
                        msg.sender,
                        address(this),
                        params_.amountIn
                    );

                tokenIn.safeApprove(address(positions), params_.amountIn);
            }

            (tokenId, , , ) = positions.mint(
                INonfungiblePositionManager.MintParams({
                    token0: token0,
                    token1: token1,
                    fee: fee,
                    tickLower: lowerTick,
                    tickUpper: upperTick,
                    amount0Desired: params_.zeroForOne ? params_.amountIn : 0,
                    amount1Desired: params_.zeroForOne ? 0 : params_.amountIn,
                    amount0Min: params_.zeroForOne ? params_.amountIn : 0,
                    amount1Min: params_.zeroForOne ? 0 : params_.amountIn,
                    recipient: address(this),
                    deadline: block.timestamp // solhint-disable-line not-rely-on-time
                })
            );
            positions.approve(address(eject), tokenId);
            eject.schedule(
                OrderParams({
                    tokenId: tokenId,
                    tickThreshold: params_.zeroForOne ? lowerTick : upperTick,
                    ejectAbove: params_.zeroForOne,
                    ejectDust: params_.ejectDust,
                    amount0Min: params_.zeroForOne ? 0 : params_.minAmountOut,
                    amount1Min: params_.zeroForOne ? params_.minAmountOut : 0,
                    receiver: params_.receiver,
                    feeToken: params_.zeroForOne ? token1 : token0,
                    resolver: rangeOrderResolver,
                    maxFeeAmount: params_.maxFeeAmount
                })
            );
        }

        emit LogSetRangeOrder(tokenId, address(params_.pool), params_.amountIn);
    }

    function cancelRangeOrder(
        uint256 tokenId_,
        RangeOrderParams calldata params_
    ) external {
        require(
            params_.receiver == msg.sender,
            "RangeOrder::cancelRangeOrder: only receiver."
        );

        int24 tickSpacing = params_.pool.tickSpacing();

        int24 lowerTick = params_.zeroForOne
            ? params_.tickThreshold
            : params_.tickThreshold - tickSpacing;
        int24 upperTick = params_.zeroForOne
            ? params_.tickThreshold + tickSpacing
            : params_.tickThreshold;
        _requireThresholdNotInRange(params_.pool, lowerTick, upperTick);

        eject.cancel(
            tokenId_,
            Order({
                tickThreshold: params_.zeroForOne ? lowerTick : upperTick,
                ejectAbove: params_.zeroForOne,
                ejectDust: params_.ejectDust,
                amount0Min: params_.zeroForOne ? 0 : params_.minAmountOut,
                amount1Min: params_.zeroForOne ? params_.minAmountOut : 0,
                receiver: params_.receiver,
                owner: address(this),
                maxFeeAmount: params_.maxFeeAmount
            })
        );
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function _requireThresholdNotInRange(
        IUniswapV3Pool pool_,
        int24 lowerTick_,
        int24 upperTick_
    ) internal view {
        (, int24 tick, , , , , ) = pool_.slot0();

        require(
            tick < lowerTick_ || tick > upperTick_,
            "RangeOrder:_requireThresholdInRange:: eject tick in range"
        );
    }
}

