// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;
pragma abicoder v2;

import {     IUniswapV3Pool } from "./IUniswapV3Pool.sol";
import {IPokeMe} from "./IPokeMe.sol";
import {IEjectResolver} from "./IEjectResolver.sol";
import {IEjectLP} from "./IEjectLP.sol";
import {     IERC20,     SafeERC20 } from "./SafeERC20.sol";
import {     INonfungiblePositionManager,     PoolAddress } from "./INonfungiblePositionManager.sol";
import {Order, OrderParams} from "./SEject.sol";

contract EjectLP is IEjectLP {
    using SafeERC20 for IERC20;

    INonfungiblePositionManager public immutable override nftPositions;
    address internal immutable _factory;
    IPokeMe public immutable override pokeMe;
    address internal immutable _gelato;

    mapping(uint256 => bytes32) public hashById;
    mapping(uint256 => bytes32) public taskById;
    event LogSetEject(
        uint256 indexed tokenId,
        OrderParams orderParams,
        address sender
    );
    event LogEject(
        uint256 indexed tokenId,
        uint256 amount0Out,
        uint256 amount1Out,
        uint256 feeAmount
    );
    event LogCancelEject(uint256 indexed tokenId);

    modifier onlyPokeMe() {
        require(
            msg.sender == address(pokeMe),
            "EjectLP::onlyPokeMe: only pokeMe"
        );
        _;
    }

    modifier onlyGelato() {
        require(msg.sender == _gelato, "EjectLP::onlyPokeMe: only gelato");
        _;
    }

    modifier isApproved(uint256 tokenId_) {
        require(
            nftPositions.getApproved(tokenId_) == address(this),
            "EjectLP::isApproved: EjectLP should be a operator"
        );
        _;
    }

    modifier onlyPositionOwner(uint256 tokenId_, address owner_) {
        require(
            nftPositions.ownerOf(tokenId_) == owner_,
            "EjectLP:schedule:: only owner"
        );
        _;
    }

    constructor(
        INonfungiblePositionManager nftPositions_,
        address factory_,
        IPokeMe pokeMe_,
        address gelato_
    ) {
        nftPositions = nftPositions_;
        _factory = factory_;
        pokeMe = pokeMe_;
        _gelato = gelato_;
    }

    function schedule(OrderParams memory orderParams_)
        external
        override
        isApproved(orderParams_.tokenId)
        onlyPositionOwner(orderParams_.tokenId, msg.sender)
    {
        Order memory order = Order({
            tickThreshold: orderParams_.tickThreshold,
            ejectAbove: orderParams_.ejectAbove,
            ejectDust: orderParams_.ejectDust,
            amount0Min: orderParams_.amount0Min,
            amount1Min: orderParams_.amount1Min,
            receiver: orderParams_.receiver,
            owner: msg.sender,
            maxFeeAmount: orderParams_.maxFeeAmount
        });

        hashById[orderParams_.tokenId] = keccak256(abi.encode(order));
        taskById[orderParams_.tokenId] = pokeMe.createTaskNoPrepayment(
            address(this),
            this.eject.selector,
            orderParams_.resolver,
            abi.encodeWithSelector(
                IEjectResolver.checker.selector,
                orderParams_.tokenId,
                order,
                orderParams_.feeToken
            ),
            orderParams_.feeToken
        );

        emit LogSetEject(orderParams_.tokenId, orderParams_, msg.sender);
    }

    // solhint-disable-next-line function-max-lines
    function eject(uint256 tokenId_, Order memory order_)
        external
        override
        onlyPokeMe
    {
        (uint256 feeAmount, address feeToken) = pokeMe.getFeeDetails();

        require(
            feeAmount < order_.maxFeeAmount,
            "EjectLP::eject: fee > maxFeeAmount"
        );

        (address token0, address token1, uint128 liquidity) = canEject(
            tokenId_,
            order_,
            feeToken
        );

        (uint256 amount0, uint256 amount1) = _collect(tokenId_, liquidity);

        if (feeToken == token0) {
            amount0 -= feeAmount;
        } else {
            amount1 -= feeAmount;
        }
        require(
            amount0 >= order_.amount0Min && amount1 >= order_.amount1Min,
            "EjectLP::eject: received below minimum"
        );

        pokeMe.cancelTask(taskById[tokenId_]); // Cancel to desactivate the task.

        delete hashById[tokenId_];
        delete taskById[tokenId_];

        // handle payouts
        if (order_.ejectAbove ? amount0 > 0 && order_.ejectDust : amount0 > 0) {
            IERC20(token0).safeTransfer(order_.receiver, amount0);
        }
        if (order_.ejectAbove ? amount1 > 0 : amount1 > 0 && order_.ejectDust) {
            IERC20(token1).safeTransfer(order_.receiver, amount1);
        }

        // gelato fee
        IERC20(feeToken).safeTransfer(_gelato, feeAmount);

        emit LogEject(tokenId_, amount0, amount1, feeAmount);
    }

    // solhint-disable-next-line function-max-lines
    function cancel(uint256 tokenId_, Order memory order_)
        external
        override
        isApproved(tokenId_)
        onlyPositionOwner(tokenId_, msg.sender)
    {
        require(
            hashById[tokenId_] == keccak256(abi.encode(order_)),
            "EjectLP::cancel: invalid hash"
        );

        (
            ,
            ,
            address token0,
            address token1,
            uint24 feeTier,
            ,
            ,
            uint128 liquidity,
            ,
            ,
            ,

        ) = nftPositions.positions(tokenId_);

        (, int24 tick, , , , , ) = _pool(token0, token1, feeTier).slot0();

        if (order_.ejectAbove) {
            require(tick < order_.tickThreshold, "EjectLP::cancel: price met");
        } else {
            require(tick > order_.tickThreshold, "EjectLP::cancel: price met");
        }

        pokeMe.cancelTask(taskById[tokenId_]);

        delete hashById[tokenId_];
        delete taskById[tokenId_];

        (uint256 amount0, uint256 amount1) = _collect(tokenId_, liquidity);

        if (order_.ejectAbove ? amount0 > 0 : amount0 > 0 && order_.ejectDust) {
            IERC20(token0).safeTransfer(order_.receiver, amount0);
        }
        if (order_.ejectAbove ? amount1 > 0 && order_.ejectDust : amount1 > 0) {
            IERC20(token1).safeTransfer(order_.receiver, amount1);
        }

        emit LogCancelEject(tokenId_);
    }

    function mulipleRetrieveDust(address[] calldata tokens_, address recipient_)
        external
        onlyGelato
    {
        for (uint256 i = 0; i < tokens_.length; i++) {
            retrieveDust(tokens_[i], recipient_);
        }
    }

    function retrieveDust(address token_, address recipient_)
        public
        onlyGelato
    {
        IERC20 token = IERC20(token_);
        uint256 balance = token.balanceOf(address(this));

        if (balance > 0) token.safeTransfer(recipient_, balance);
    }

    // solhint-disable-next-line function-max-lines
    function canEject(
        uint256 tokenId_,
        Order memory order_,
        address feeToken_
    )
        public
        view
        override
        isApproved(tokenId_)
        onlyPositionOwner(tokenId_, order_.owner)
        returns (
            address,
            address,
            uint128
        )
    {
        require(
            hashById[tokenId_] == keccak256(abi.encode(order_)),
            "EjectLP::canEject: incorrect task hash"
        );
        address token0;
        address token1;
        uint128 liquidity;
        IUniswapV3Pool pool;
        {
            uint24 feeTier;
            (, , token0, token1, feeTier, , , liquidity, , , , ) = nftPositions
                .positions(tokenId_);
            pool = _pool(token0, token1, feeTier);
        }
        require(
            feeToken_ == token0 || feeToken_ == token1,
            "EjectLP::canEject: wrong fee token"
        );

        {
            (, int24 tick, , , , , ) = pool.slot0();
            int24 tickSpacing = pool.tickSpacing();

            if (order_.ejectAbove) {
                require(
                    tick > order_.tickThreshold + tickSpacing,
                    "EjectLP::canEject: price not met"
                );
            } else {
                require(
                    tick < order_.tickThreshold - tickSpacing,
                    "EjectLP::canEject: price not met"
                );
            }
        }

        return (token0, token1, liquidity);
    }

    function _collect(uint256 tokenId_, uint128 liquidity_)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        nftPositions.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId_,
                liquidity: liquidity_,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp // solhint-disable-line not-rely-on-time
            })
        );
        (amount0, amount1) = nftPositions.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId_,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
    }

    function _pool(
        address tokenIn_,
        address tokenOut_,
        uint24 fee_
    ) internal view returns (IUniswapV3Pool) {
        return
            IUniswapV3Pool(
                PoolAddress.computeAddress(
                    _factory,
                    PoolAddress.PoolKey({
                        token0: tokenIn_ < tokenOut_ ? tokenIn_ : tokenOut_,
                        token1: tokenIn_ < tokenOut_ ? tokenOut_ : tokenIn_,
                        fee: fee_
                    })
                )
            );
    }
}

