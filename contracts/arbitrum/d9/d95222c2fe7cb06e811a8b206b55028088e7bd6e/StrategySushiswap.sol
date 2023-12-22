// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {IPairUniV2} from "./IPairUniV2.sol";
import {Strategy} from "./Strategy.sol";
import {IRewarderMiniChefV2} from "./IRewarderMiniChefV2.sol";

contract StrategySushiswap is Strategy {
    string public name;
    IRewarderMiniChefV2 public rewarder;
    IPairUniV2 public pool;
    uint256 poolId;

    constructor(address _strategyHelper, address _rewarder, uint256 _poolId) Strategy(_strategyHelper) {
        rewarder = IRewarderMiniChefV2(_rewarder);
        poolId = _poolId;
        pool = IPairUniV2(rewarder.lpToken(poolId));
        name = string(abi.encodePacked("SushiSwap ", IERC20(pool.token0()).symbol(), "/", IERC20(pool.token1()).symbol()));
    }

    function _rate(uint256 sha) internal view override returns (uint256) {
        if (sha == 0 || totalShares == 0) return 0;
        IPairUniV2 pair = pool;
        uint256 tot = pair.totalSupply();
        uint256 amt = totalManagedAssets();
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 val = strategyHelper.value(pair.token0(), reserve0) +
            strategyHelper.value(pair.token1(), reserve1);
        return sha * (val * amt / tot) / totalShares;
    }

    function _mint(address ast, uint256 amt, bytes calldata dat) internal override returns (uint256) {
        earn();
        pull(IERC20(ast), msg.sender, amt);
        IPairUniV2 pair = pool;
        IERC20 tok0 = IERC20(pair.token0());
        IERC20 tok1 = IERC20(pair.token1());
        uint256 slp = getSlippage(dat);
        uint256 tma = totalManagedAssets();
        {
            uint256 haf = amt / 2;
            IERC20(ast).approve(address(strategyHelper), amt);
            strategyHelper.swap(ast, address(tok0), haf, slp, address(this));
            strategyHelper.swap(ast, address(tok1), amt-haf, slp, address(this));
            push(tok0, address(pair), tok0.balanceOf(address(this)));
            push(tok1, address(pair), tok1.balanceOf(address(this)));
        }
        pair.mint(address(this));
        pair.skim(address(this));
        uint256 liq = IERC20(address(pair)).balanceOf(address(this));
        IERC20(address(pair)).approve(address(rewarder), liq);
        rewarder.deposit(poolId, liq, address(this));
        return tma == 0 ? liq : liq * totalShares / tma;
    }

    function _burn(address ast, uint256 sha, bytes calldata dat) internal override returns (uint256) {
        earn();
        IPairUniV2 pair = pool;
        uint256 slp = getSlippage(dat);
        {
            uint256 tma = totalManagedAssets();
            uint256 amt = sha * tma / totalShares;
            rewarder.withdraw(poolId, amt, address(pair));
            pair.burn(address(this));
        }
        IERC20 tok0 = IERC20(pair.token0());
        IERC20 tok1 = IERC20(pair.token1());
        uint256 bal0 = tok0.balanceOf(address(this));
        uint256 bal1 = tok1.balanceOf(address(this));
        tok0.approve(address(strategyHelper), bal0);
        tok1.approve(address(strategyHelper), bal1);
        uint256 amt0 = strategyHelper.swap(address(tok0), ast, bal0, slp, msg.sender);
        uint256 amt1 = strategyHelper.swap(address(tok1), ast, bal1, slp, msg.sender);
        return amt0 + amt1;
    }

    function _earn() internal override {
        IPairUniV2 pair = pool;
        IERC20 rew = IERC20(rewarder.SUSHI());
        rewarder.harvest(poolId, address(this));
        uint256 amt = rew.balanceOf(address(this));
        uint256 haf = amt / 2;
        if (strategyHelper.value(address(rew), amt) < 0.5e18) return;
        rew.approve(address(strategyHelper), amt);
        strategyHelper.swap(address(rew), pair.token0(), haf, slippage, address(pair));
        strategyHelper.swap(address(rew), pair.token1(), amt-haf, slippage, address(pair));
        pair.mint(address(this));
        pair.skim(address(this));
        uint256 liq = IERC20(address(pair)).balanceOf(address(this));
        rewarder.deposit(poolId, liq, address(this));
    }

    function totalManagedAssets() public view returns (uint256) {
        (uint256 amt,) = rewarder.userInfo(poolId, address(this));
        return amt;
    }

    function _exit(address str) internal override {
        IERC20 lp = IERC20(address(pool));
        rewarder.withdraw(poolId, totalShares, address(pool));
        push(lp, str, lp.balanceOf(address(this)));
    }
}

