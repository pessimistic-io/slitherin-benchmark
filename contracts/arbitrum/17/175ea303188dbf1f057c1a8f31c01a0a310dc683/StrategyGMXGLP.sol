// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Strategy} from "./Strategy.sol";
import {IERC20} from "./IERC20.sol";

interface IRewardRouter {
    function glpManager() external view returns (address);
    function feeGlpTracker() external view returns (address);
    function stakedGlpTracker() external view returns (address);
    function mintAndStakeGlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minGlp
    )
        external
        returns (uint256);
    function unstakeAndRedeemGlp(
        address _tokenOut,
        uint256 _glpAmount,
        uint256 _minOut,
        address _receiver
    )
        external
        returns (uint256);
    function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external;
}

interface IGlpManager {
    function getAumInUsdg(bool) external view returns (uint256);
    function glp() external view returns (address);
    function vault() external view returns (address);
}

interface IRewardTracker {
    function claimable(address) external view returns (uint256);
    function depositBalances(address _account, address _depositToken) external view returns (uint256);
}

interface IVault {
    function mintBurnFeeBasisPoints() external view returns (uint256);
    function taxBasisPoints() external view returns (uint256);
    function getFeeBasisPoints(address token, uint256 amt, uint256 fee, uint256 tax, bool increment) external view returns (uint256);
}

interface IOracle {
    function latestAnswer() external view returns (int256);
}

contract StrategyGMXGLP is Strategy {
    string public constant name = "GMX GLP";
    IRewardRouter public rewardRouter;
    IRewardRouter public rewardRouterClaiming;
    IGlpManager public glpManager;
    IVault public vault;
    IERC20 public stakedGlp;
    IERC20 public glp;
    IERC20 public weth;

    constructor(
        address _strategyHelper,
        address _rewardRouter,
        address _rewardRouterClaiming,
        address _stakedGlp,
        address _weth
    ) Strategy(_strategyHelper) {
        rewardRouter = IRewardRouter(_rewardRouter);
        rewardRouterClaiming = IRewardRouter(_rewardRouterClaiming);
        stakedGlp = IERC20(_stakedGlp);
        glpManager = IGlpManager(rewardRouter.glpManager());
        glp = IERC20(glpManager.glp());
        vault = IVault(glpManager.vault());
        weth = IERC20(_weth);
    }

    function _rate(uint256 sha) internal view override returns (uint256) {
        if (sha == 0 || totalShares == 0) return 0;
        uint256 tot = glp.totalSupply();
        uint256 amt = IERC20(rewardRouter.stakedGlpTracker()).balanceOf(address(this));
        uint256 val = glpManager.getAumInUsdg(false);
        uint256 fee = vault.getFeeBasisPoints(address(weth), val, vault.mintBurnFeeBasisPoints(), vault.taxBasisPoints(), false);
        val = val * (10000 - fee) / 10000;
        uint256 rew = IRewardTracker(rewardRouter.feeGlpTracker()).claimable(address(this));
        uint256 amtval = (val * amt / tot) + strategyHelper.value(address(weth), rew);
        return sha * amtval / totalShares;
    }

    function _mint(address ast, uint256 amt, bytes calldata dat) internal override returns (uint256) {
        earn();
        pull(IERC20(ast), msg.sender, amt);
        uint256 slp = getSlippage(dat);
        uint256 tma = IERC20(rewardRouter.stakedGlpTracker()).balanceOf(address(this));
        uint256 pri = glpManager.getAumInUsdg(true) * 1e18 / glp.totalSupply();
        uint256 minUsd = strategyHelper.value(ast, amt) * slp / 10000;
        uint256 minGlp = minUsd * 1e18 / pri;
        IERC20(ast).approve(address(glpManager), amt);
        uint256 out = rewardRouter.mintAndStakeGlp(ast, amt, minUsd, minGlp);
        return tma == 0 ? out : out * totalShares / tma;
    }

    function _burn(address ast, uint256 sha, bytes calldata dat) internal override returns (uint256) {
        earn();
        uint256 slp = getSlippage(dat);
        uint256 tma = IERC20(rewardRouter.stakedGlpTracker()).balanceOf(address(this));
        uint256 amt = sha * tma / totalShares;
        uint256 pri = glpManager.getAumInUsdg(false) * 1e18 / glp.totalSupply();
        uint256 min = (amt * pri / 1e18) * slp / 10000;
        min = min * (10 ** IERC20(ast).decimals()) / 1e18;
        return rewardRouter.unstakeAndRedeemGlp(ast, amt, min, msg.sender);
    }

    function _earn() internal override {
        rewardRouterClaiming.handleRewards(true, true, true, true, true, true, false);
        uint256 amt = weth.balanceOf(address(this));
        if (amt > 0) {
            weth.approve(address(glpManager), amt);
            rewardRouter.mintAndStakeGlp(address(weth), amt, 0, 0);
        }
    }

    function _exit(address str) internal override {
        _earn();
        push(stakedGlp, str, stakedGlp.balanceOf(address(this)));
    }
}

