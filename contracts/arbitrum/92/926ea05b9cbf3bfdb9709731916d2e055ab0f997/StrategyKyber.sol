// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Strategy} from "./Strategy.sol";
import {ERC721TokenReceiver} from "./ERC721TokenReceiver.sol";
import {TickLib} from "./TickLib.sol";
import {TickMath} from "./TickMath.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";
import {IERC20} from "./IERC20.sol";
import {IKyberPool} from "./IKyberPool.sol";
import {IKyberRouter} from "./IKyberRouter.sol";
import {IKyberStaking} from "./IKyberStaking.sol";
import {IKyberPositionManager} from "./IKyberPositionManager.sol";

contract StrategyKyber is Strategy, ERC721TokenReceiver {
    string public name;
    IKyberPositionManager public immutable pm;
    IKyberPool public immutable pool;
    IKyberStaking public immutable staking;
    uint256 public stakingPoolId;
    int24 public tickScale;
    uint256 public tokenId;

    IERC20 public immutable token0;
    IERC20 public immutable token1;
    uint24 public immutable fee;
    int24 public immutable tickSpacing;
    int24 public minTick;
    int24 public maxTick;
    uint160 public minSqrtRatio;
    uint160 public maxSqrtRatio;

    event SetStakingPoolId(uint256 stakingPoolId);

    constructor(
        address _strategyHelper,
        address _pm,
        address _staking,
        address _pool,
        int24 _tickScale
    ) Strategy(_strategyHelper) {
        pm = IKyberPositionManager(_pm);
        pool = IKyberPool(_pool);
        staking = IKyberStaking(_staking);
        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());
        fee = pool.swapFeeUnits();
        tickSpacing = pool.tickDistance();
        tickScale = _tickScale;
        minTick = TickLib.nearestUsableTick(TickMath.MIN_TICK, tickSpacing);
        maxTick = TickLib.nearestUsableTick(TickMath.MAX_TICK, tickSpacing);
        if (_tickScale > 0) {
            (minTick, maxTick) = getTickRange(_tickScale);
        }
        minSqrtRatio = TickMath.getSqrtRatioAtTick(minTick);
        maxSqrtRatio = TickMath.getSqrtRatioAtTick(maxTick);
        name = string(abi.encodePacked("Kyber ", token0.symbol(), "/", token1.symbol()));
    }

    function setStakingPoolId(uint256 _stakingPoolId) external auth {
        stakingPoolId = _stakingPoolId;
        emit SetStakingPoolId(_stakingPoolId);
    }

    function _rate(uint256 sha) internal view override returns (uint256) {
        if (sha == 0 || totalShares == 0) return 0;
        (uint160 sqrtP, int24 tick,,) = pool.getPoolState();
        (IKyberPositionManager.Position memory p,) = pm.positions(tokenId);

        (uint256 amt0, uint256 amt1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtP, minSqrtRatio, maxSqrtRatio, p.liquidity
        );

        uint256 val0 = strategyHelper.value(address(token0), amt0);
        uint256 val1 = strategyHelper.value(address(token1), amt1);
        return sha * (val0 + val1) / totalShares;
    }

    function _mint(address ast, uint256 amt, bytes calldata dat) internal override returns (uint256) {
        earn();
        pull(IERC20(ast), msg.sender, amt);
        uint256 slp = getSlippage(dat);
        (IKyberPositionManager.Position memory p,) = pm.positions(tokenId);
        uint256 tma = p.liquidity;
        uint256 haf = amt / 2;
        IERC20(ast).approve(address(strategyHelper), amt);
        strategyHelper.swap(ast, address(token0), haf, slp, address(this));
        strategyHelper.swap(ast, address(token1), amt-haf, slp, address(this));
        uint256 liqBefore = getLiquidity();
        _earn();
        uint256 liq = getLiquidity() - liqBefore;
        return tma == 0 ? liq : liq * totalShares / tma;
    }

    function _burn(address ast, uint256 amt, bytes calldata dat) internal override returns (uint256) {
        earn();
        uint256 slp = getSlippage(dat);
        uint256 tma = getLiquidity();
        uint128 liq = uint128(amt * tma / totalShares);
        if (liq == 0) return 0;

        _stakingExit(tma);
        pm.removeLiquidity(IKyberPositionManager.RemoveLiquidityParams({
            tokenId: tokenId,
            liquidity: liq,
            amount0Min: 0,
            amount1Min: 0,
            deadline: type(uint256).max
        }));
        uint256 bal0 = token0.balanceOf(address(pm));
        uint256 bal1 = token1.balanceOf(address(pm));
        pm.transferAllTokens(address(token0), bal0, address(this));
        pm.transferAllTokens(address(token1), bal1, address(this));
        _stakingEnter(getLiquidity());

        token0.approve(address(strategyHelper), bal0);
        token1.approve(address(strategyHelper), bal1);
        uint256 amt0 = strategyHelper.swap(address(token0), ast, bal0, slp, msg.sender);
        uint256 amt1 = strategyHelper.swap(address(token1), ast, bal1, slp, msg.sender);
        return amt0 + amt1;
    }

    function _earn() internal override {
        uint256 slp = slippage;

        if (tokenId != 0) {
            (IKyberPositionManager.Position memory p,) = pm.positions(tokenId);
            _stakingExit(p.liquidity);
            pm.removeLiquidity(IKyberPositionManager.RemoveLiquidityParams({
                tokenId: tokenId,
                liquidity: p.liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: type(uint256).max
            }));
            if (p.rTokenOwed > 0) {
                pm.burnRTokens(IKyberPositionManager.BurnRTokenParams({
                    tokenId: tokenId,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: type(uint256).max
                }));
            }
            pm.transferAllTokens(address(token0), token0.balanceOf(address(pm)), address(this));
            pm.transferAllTokens(address(token1), token1.balanceOf(address(pm)), address(this));
        }

        if (tickScale > 0) {
            (minTick, maxTick) = getTickRange(tickScale);
            minSqrtRatio = TickMath.getSqrtRatioAtTick(minTick);
            maxSqrtRatio = TickMath.getSqrtRatioAtTick(maxTick);
        }

        (uint160 sqrtP,,,) = pool.getPoolState();
        uint256 bal0 = token0.balanceOf(address(this));
        uint256 bal1 = token1.balanceOf(address(this));
        uint128 liq0 = LiquidityAmounts.getLiquidityForAmount0(sqrtP, maxSqrtRatio, bal0);
        uint128 liq1 = LiquidityAmounts.getLiquidityForAmount1(minSqrtRatio, sqrtP, bal1);

        if (liq0 > liq1) {
            uint128 liqDiff = (liq0 - liq1) / 2;
            uint256 amt = LiquidityAmounts.getAmount0ForLiquidity(sqrtP, maxSqrtRatio, liqDiff);
            if (strategyHelper.value(address(token0), amt) > 5e17) { //.5$
                token0.approve(address(strategyHelper), amt);
                strategyHelper.swap(address(token0), address(token1), amt, slippage, address(this));
            }
        } else {
            uint128 liqDiff = (liq1 - liq0) / 2;
            uint256 amt = LiquidityAmounts.getAmount1ForLiquidity(minSqrtRatio, sqrtP, liqDiff);
            if (strategyHelper.value(address(token1), amt) > 5e17) { //.5$
                token1.approve(address(strategyHelper), amt);
                strategyHelper.swap(address(token1), address(token0), amt, slippage, address(this));
            }
        }

        _mintPosition(slp);
    }

    function _mintPosition(uint256 slp) internal returns (uint256) {
        uint256 amt0 = token0.balanceOf(address(this));
        uint256 amt1 = token1.balanceOf(address(this));
        token0.approve(address(pm), amt0);
        token1.approve(address(pm), amt1);
        int24 prevT = 0;
        int24 prev0 = minTick;
        int24 prev1 = maxTick;
        for (uint256 i = 100; i > 0; i--) {
            (prevT,) = pool.initializedTicks(prev0);
            if (prevT != 0) {
                prev0 = prevT;
                break;
            }
            prev0 -= tickSpacing;
        }
        for (uint256 i = 100; i > 0; i--) {
            (prevT,) = pool.initializedTicks(prev1);
            if (prevT != 0) {
                prev1 = prevT;
                break;
            }
            prev1 -= tickSpacing;
        }
        int24[2] memory ticksPrevious = [prev0, prev1];
        (uint256 tid, uint256 liq,,) = pm.mint(IKyberPositionManager.MintParams({
            token0: address(token0),
            token1: address(token1),
            fee: fee,
            tickLower: minTick,
            tickUpper: maxTick,
            ticksPrevious: ticksPrevious,
            amount0Desired: amt0,
            amount1Desired: amt1,
            amount0Min: amt0 * (10000-slp) / 10000,
            amount1Min: amt1 * (10000-slp) / 10000,
            recipient: address(this),
            deadline: type(uint256).max
        }));
        tokenId = tid;
        _stakingEnter(liq);
        return liq;
    }

    function _stakingEnter(uint256 liq) internal {
        if (stakingPoolId > 0) {
            uint256[] memory nftIds = new uint256[](1);
            nftIds[0] = tokenId;
            uint256[] memory liqs = new uint256[](1);
            liqs[0] = liq;
            staking.deposit(nftIds);
            staking.join(stakingPoolId, nftIds, liqs);
        }
    }

    function _stakingExit(uint256 liq) internal {
        if (stakingPoolId > 0) {
            uint256[] memory nftIds = new uint256[](1);
            nftIds[0] = tokenId;
            uint256[] memory liqs = new uint256[](1);
            liqs[0] = liq;
            staking.exit(stakingPoolId, nftIds, liqs);
            staking.withdraw(nftIds);
        }
    }

    function getLiquidity() internal view returns (uint256) {
        if (tokenId == 0) return 0;
        (IKyberPositionManager.Position memory p,) = pm.positions(tokenId);
        return p.liquidity;
    }

    function getTickRange(int24 scale) internal view returns (int24, int24) {
        (, int24 tick,,) = pool.getPoolState();
        int24 scaleMod = tick < 0 ? -int24(1) : int24(1);
        int24 targetMinTick = int24(int256(tick) * (1e5 - (scale * scaleMod)) / 1e5);
        int24 targetMaxTick = int24(int256(tick) * (1e5 + (scale * scaleMod)) / 1e5);
        int24 activeMinTick = TickLib.nearestUsableTick(targetMinTick, tickSpacing);
        int24 activeMaxTick = TickLib.nearestUsableTick(targetMaxTick, tickSpacing);
        return (activeMinTick, activeMaxTick);
    }

    function _exit(address str) internal override {
        if (tokenId > 0) {
            _stakingExit(getLiquidity());
            pm.safeTransferFrom(address(this), str, tokenId, "");
        }
    }

    function _move(address old) internal override {
        tokenId = StrategyKyber(old).tokenId();
        if (tokenId > 0) {
            _stakingEnter(getLiquidity());
        }
    }
}

