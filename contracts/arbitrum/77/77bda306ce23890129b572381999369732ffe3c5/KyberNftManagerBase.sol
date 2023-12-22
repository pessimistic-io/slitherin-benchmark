// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./IERC721Receiver.sol";
import "./IERC721.sol";
import "./IKyberLiquidityMining.sol";
import "./IKyberElasticPool.sol";
import "./IKyberElasticRouter.sol";
import "./IKyberElasticFactory.sol";
import "./IKyberPositionManager.sol";
import "./IKyberMathHelper.sol";
import "./TokenHelper.sol";
import "./ArrayLib.sol";
import "./Math.sol";

abstract contract KyberNftManagerBase is TokenHelper, IERC721Receiver {
    using Math for uint256;

    enum KyberLiquidityMiningStatus {
        ACTIVE,
        INACTIVE, // phase settled or range removed
        EMERGENCY
    }

    error InvalidNft(uint256 tokenId);

    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;
    uint256 public constant DEFAULT_POSITION_TOKEN_ID = type(uint256).max;

    address public immutable pool;
    int24 public immutable tickLower;
    int24 public immutable tickUpper;

    address public immutable positionManager;
    address public immutable router;
    address public immutable factory;

    address public immutable liquidityMining;
    uint256 public immutable farmId;
    uint256 public immutable rangeId;

    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;

    address public immutable kyberMathHelper;

    uint256 public positionTokenId = DEFAULT_POSITION_TOKEN_ID;

    struct KyberNftManagerConstructorParams {
        address pool;
        int24 tickLower;
        int24 tickUpper;
        // position related
        address positionManager;
        address router;
        address factory;
        // farming related
        address liquidityMining;
        uint256 farmId;
        uint256 rangeId;
        // math helper
        address kyberMathHelper;
    }

    constructor(KyberNftManagerConstructorParams memory params) {
        pool = params.pool;
        tickLower = params.tickLower;
        tickUpper = params.tickUpper;

        positionManager = params.positionManager;
        router = params.router;
        factory = params.factory;

        liquidityMining = params.liquidityMining;
        farmId = params.farmId;
        rangeId = params.rangeId;

        kyberMathHelper = params.kyberMathHelper;

        _validateFarmInfo(
            params.pool,
            params.tickLower,
            params.tickUpper,
            params.liquidityMining,
            params.farmId,
            params.rangeId
        );

        token0 = IKyberElasticPool(pool).token0();
        token1 = IKyberElasticPool(pool).token1();
        fee = IKyberElasticPool(pool).swapFeeUnits();

        _safeApproveInf(token0, positionManager);
        _safeApproveInf(token1, positionManager);
        _safeApproveInf(token0, router);
        _safeApproveInf(token1, router);
    }

    /*///////////////////////////////////////////////////////////////
                                NFT RELATED
    //////////////////////////////////////////////////////////////*/

    /**
     *
     * @param tokenId The tokenId of the position to be deposited
     * @dev in case position not initialized, a minimum amount of liquidity will be locked
     * to prevent Kyber pool ticks from being deleted
     */
    function _depositNft(uint256 tokenId) internal returns (uint256 sharesMinted) {
        uint128 liquidity = _validateTokenIdAndGetLiquidity(tokenId);
        IERC721(positionManager).safeTransferFrom(msg.sender, address(this), tokenId);

        if (positionTokenId == DEFAULT_POSITION_TOKEN_ID) {
            positionTokenId = tokenId;
            require(liquidity > MINIMUM_LIQUIDITY, "minimum liquidity not met");
            sharesMinted = liquidity - MINIMUM_LIQUIDITY;

            // It's okay to revert due to Kyber emergency or inactive farm in this initialization step
            _depositNftToFarm();
        } else {
            // Tho most of the case sharesMinted = liquidity
            // should re-calc it to prevent any precision issue
            sharesMinted = _mergeNft(tokenId, liquidity);
        }
    }

    function _withdrawNft(
        uint256 amountSharesToWithdraw,
        address receipent
    ) internal returns (uint256 tokenId) {
        (uint256 amount0, uint256 amount1) = _removeLiquidity(amountSharesToWithdraw.Uint128());
        return _mintKyberNft(amount0, amount1, receipent);
    }

    function _mergeNft(uint256 tokenId, uint128 liquidity) private returns (uint256 sharesMinted) {
        (uint256 amount0, uint256 amount1, ) = IKyberPositionManager(positionManager)
            .removeLiquidity(
                IKyberPositionManager.RemoveLiquidityParams({
                    tokenId: tokenId,
                    liquidity: liquidity,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: type(uint256).max
                })
            );

        IKyberPositionManager(positionManager).burn(tokenId);
        return _addLiquidity(amount0, amount1);
    }

    /*///////////////////////////////////////////////////////////////
                            ZAP RELATED
    //////////////////////////////////////////////////////////////*/

    function _zapIn(
        address tokenIn,
        uint256 amountTokenIn
    ) internal returns (uint256 amountSharesOut) {
        uint256 amountToSwap = IKyberMathHelper(kyberMathHelper).getSingleSidedSwapAmount(
            pool,
            amountTokenIn,
            tokenIn == token0,
            tickLower,
            tickUpper
        );

        address tokenOut = tokenIn == token0 ? token1 : token0;
        uint256 amountOut = _swap(tokenIn, tokenOut, amountToSwap);

        (uint256 amount0, uint256 amount1) = tokenIn == token0
            ? (amountTokenIn - amountToSwap, amountOut)
            : (amountOut, amountTokenIn - amountToSwap);

        return _addLiquidity(amount0, amount1);
    }

    function _zapOut(
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal returns (uint256 amountTokenOut) {
        (uint256 amount0, uint256 amount1) = _removeLiquidity(amountSharesToRedeem.Uint128());
        bool isToken0 = tokenOut == token0;
        address tokenIn = isToken0 ? token1 : token0;
        uint256 amountIn = isToken0 ? amount1 : amount0;
        uint256 amountOut = _swap(tokenIn, tokenOut, amountIn);

        return amountOut + (isToken0 ? amount0 : amount1);
    }

    /*///////////////////////////////////////////////////////////////
                            REWARD RELATED
    //////////////////////////////////////////////////////////////*/

    function _claimKyberRewards() internal {
        uint256 tokenId = positionTokenId;

        // NOTE: Kyber LM reverts if there's no rTOKEN to be burned
        // Kyber also doesnt allow calling syncFee() for unauthorized address so there is no good way to check if there's any rTOKEN to be burned
        // Thus IKyberLiquidityMining.claimFee() should only be called after this painful process of [withdraw nft -> syncFee -> deposit -> claimFee]
        // smh very gas-inefficient

        // Should verify this assumption that positions.rTokenOwed is always 0 before _claimKyberRewards is called
        // If not, there's a workaround to just fetch the whole IKyberPositionManager.positions() and use the according rTokenOwed

        KyberLiquidityMiningStatus status = _getKyberLiquidityMiningStatus();
        bool nftInLm = _isNftInLiquidityMining();

        if (nftInLm) {
            _withdrawNftFromFarm(status); // withdraw nft (without emergency) should also claim reward
        }

        uint256 additionalRTokenOwed = IKyberPositionManager(positionManager).syncFeeGrowth(
            tokenId
        );

        if (additionalRTokenOwed > 0) {
            IKyberPositionManager(positionManager).burnRTokens(
                IKyberPositionManager.BurnRTokenParams({
                    tokenId: tokenId,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: type(uint256).max
                })
            );
            _collectPositionManagerFloatingTokens();
        }

        if (status == KyberLiquidityMiningStatus.ACTIVE) {
            _depositNftToFarm();
        }
    }

    function _depositNftToFarm() internal {
        uint256 tokenId = positionTokenId;
        IERC721(positionManager).approve(liquidityMining, tokenId);
        IKyberLiquidityMining(liquidityMining).deposit(
            farmId,
            rangeId,
            ArrayLib.create(tokenId),
            address(this)
        );
    }

    function _withdrawNftFromFarm(KyberLiquidityMiningStatus status) internal {
        if (status == KyberLiquidityMiningStatus.EMERGENCY) {
            IKyberLiquidityMining(liquidityMining).withdrawEmergency(
                ArrayLib.create(positionTokenId)
            );
        } else {
            IKyberLiquidityMining(liquidityMining).withdraw(
                farmId,
                ArrayLib.create(positionTokenId)
            );
        }
    }

    /*///////////////////////////////////////////////////////////////
                            BASE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _addLiquidity(uint256 amount0, uint256 amount1) private returns (uint128 liquidity) {
        uint256 tokenId = positionTokenId;
        assert(tokenId != DEFAULT_POSITION_TOKEN_ID);

        (liquidity, , , ) = IKyberPositionManager(positionManager).addLiquidity(
            IKyberPositionManager.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: type(uint256).max,
                ticksPrevious: [tickLower, tickUpper] // doesnt matter as the ticks should always be initialized
            })
        );

        if (_isAddLiquidityValid()) {
            IKyberLiquidityMining(liquidityMining).addLiquidity(
                farmId,
                rangeId,
                ArrayLib.create(tokenId)
            );
        }
    }

    function _removeLiquidity(
        uint128 liquidity
    ) private returns (uint256 amount0, uint256 amount1) {
        uint256 tokenId = positionTokenId;
        assert(tokenId != DEFAULT_POSITION_TOKEN_ID);

        if (_isNftInLiquidityMining()) {
            uint256 prevBalance0 = _selfBalance(token0);
            uint256 prevBalance1 = _selfBalance(token1);
            IKyberLiquidityMining(liquidityMining).removeLiquidity(
                tokenId,
                liquidity,
                0,
                0,
                type(uint256).max,
                false,
                false
            );
            amount0 = _selfBalance(token0) - prevBalance0;
            amount1 = _selfBalance(token1) - prevBalance1;
        } else {
            // TODO: remove using position manager
            IKyberPositionManager(positionManager).removeLiquidity(
                IKyberPositionManager.RemoveLiquidityParams({
                    tokenId: tokenId,
                    liquidity: liquidity,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: type(uint256).max
                })
            );
            (amount0, amount1) = _collectPositionManagerFloatingTokens();
        }
    }

    function _mintKyberNft(
        uint256 amount0,
        uint256 amount1,
        address receipent
    ) private returns (uint256 tokenId) {
        (tokenId, , , ) = IKyberPositionManager(positionManager).mint(
            IKyberPositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: fee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                ticksPrevious: [tickLower, tickUpper], // does matter, explained in _addLiquidity
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: receipent,
                deadline: type(uint256).max
            })
        );
    }

    function _swap(address tokenIn, address tokenOut, uint256 amountIn) private returns (uint256) {
        if (amountIn == 0) return 0;
        return
            IKyberElasticRouter(router).swapExactInputSingle(
                IKyberElasticRouter.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: fee,
                    recipient: address(this),
                    deadline: type(uint256).max,
                    amountIn: amountIn,
                    minAmountOut: 0,
                    limitSqrtP: 0 // Kyber router shall assign the appropriate inf price limit if set to 0
                })
            );
    }

    /*///////////////////////////////////////////////////////////////
                            VALIDATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/


    function _validateFarmInfo(
        address _pool,
        int24 _tickLower,
        int24 _tickUpper,
        address _liquidityMining,
        uint256 _farmId,
        uint256 _rangeId
    ) private view {
        (
            address farmPool,
            IKyberLiquidityMining.RangeInfo[] memory farmRanges,
            ,
            ,
            ,
            ,

        ) = IKyberLiquidityMining(_liquidityMining).getFarm(_farmId);

        require(
            _pool == farmPool &&
                _tickLower == farmRanges[_rangeId].tickLower &&
                _tickUpper == farmRanges[_rangeId].tickUpper,
            "invalid pool info"
        );
    }

    function _getKyberLiquidityMiningStatus() private view returns (KyberLiquidityMiningStatus) {
        if (IKyberLiquidityMining(liquidityMining).emergencyEnabled()) {
            return KyberLiquidityMiningStatus.EMERGENCY;
        }

        (
            ,
            IKyberLiquidityMining.RangeInfo[] memory ranges,
            IKyberLiquidityMining.PhaseInfo memory phase,
            ,
            ,
            ,

        ) = IKyberLiquidityMining(liquidityMining).getFarm(farmId); // expensive call urg... but no other way

        if (rangeId >= ranges.length || ranges[rangeId].isRemoved) {
            return KyberLiquidityMiningStatus.INACTIVE;
        }

        if (phase.endTime < block.timestamp || phase.isSettled) {
            return KyberLiquidityMiningStatus.INACTIVE;
        }
        return KyberLiquidityMiningStatus.ACTIVE;
    }

    function _isNftInLiquidityMining() private view returns (bool) {
        return IERC721(positionManager).ownerOf(positionTokenId) == liquidityMining;
    }

    function _isAddLiquidityValid() private view returns (bool) {
        return
            _getKyberLiquidityMiningStatus() == KyberLiquidityMiningStatus.ACTIVE &&
            _isNftInLiquidityMining();
    }

    function _validateTokenIdAndGetLiquidity(
        uint256 tokenId
    ) private view returns (uint128 liquidity) {
        (
            IKyberPositionManager.Position memory position,
            IKyberPositionManager.PoolInfo memory poolInfo
        ) = IKyberPositionManager(positionManager).positions(tokenId);

        if (
            IKyberElasticFactory(factory).getPool(
                poolInfo.token0,
                poolInfo.token1,
                poolInfo.fee
            ) != pool
        ) revert InvalidNft(tokenId);

        if (position.tickLower != tickLower || position.tickUpper != tickUpper)
            revert InvalidNft(tokenId);

        return position.liquidity;
    }


    /*///////////////////////////////////////////////////////////////
                            MISC FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _collectPositionManagerFloatingTokens()
        private
        returns (uint256 amount0, uint256 amount1)
    {
        amount0 = IERC20(token0).balanceOf(positionManager);
        amount1 = IERC20(token1).balanceOf(positionManager);

        IKyberPositionManager(positionManager).transferAllTokens(token0, amount0, address(this));
        IKyberPositionManager(positionManager).transferAllTokens(token1, amount1, address(this));
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

