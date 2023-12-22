// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Strategy} from "./Strategy.sol";
import {IERC20} from "./IERC20.sol";

interface IRewardRouter {
    function mlpManager() external view returns (address);
    function feeMlpTracker() external view returns (address);
    function stakedMlpTracker() external view returns (address);
    function mintAndStakeMlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minGlp
    )
        external
        returns (uint256);
    function unstakeAndRedeemMlp(
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
        bool _shouldConvertWethToEth,
        bool _shouldBuyMlpWithWeth
    ) external;
}

interface IGlpManager {
    function getAumInUsdg(bool) external view returns (uint256);
    function mlp() external view returns (address);
    function vault() external view returns (address);
}

interface IRewardTracker {
    function claimable(address) external view returns (uint256);
    function depositBalances(address _account, address _depositToken) external view returns (uint256);
}

interface IVault {
    function mintBurnFeeBasisPoints() external view returns (uint256);
    function stableTaxBasisPoints() external view returns (uint256);
    function getFeeBasisPoints(address token, uint256 amt, uint256 fee, uint256 tax, bool increment) external view returns (uint256);
}

interface IOracle {
    function latestAnswer() external view returns (int256);
}

contract StrategyMycelium is Strategy {
    string public constant name = "Mycelium MLP";
    IRewardRouter public rewardRouter;
    IRewardRouter public rewardRouterClaiming;
    IGlpManager public glpManager;
    IVault public vault;
    IERC20 public stakedGlp;
    IERC20 public glp;
    IERC20 public usdc;

    constructor(
        address _strategyHelper,
        address _rewardRouter,
        address _rewardRouterClaiming,
        address _stakedGlp,
        address _usdc
    ) Strategy(_strategyHelper) {
        rewardRouter = IRewardRouter(_rewardRouter);
        rewardRouterClaiming = IRewardRouter(_rewardRouterClaiming);
        stakedGlp = IERC20(_stakedGlp);
        glpManager = IGlpManager(rewardRouter.mlpManager());
        glp = IERC20(glpManager.mlp());
        vault = IVault(glpManager.vault());
        usdc = IERC20(_usdc);
    }

    function _rate(uint256 sha) internal view override returns (uint256) {
        if (sha == 0 || totalShares == 0) return 0;
        uint256 tot = glp.totalSupply();
        uint256 amt = IERC20(rewardRouter.stakedMlpTracker()).balanceOf(address(this));
        uint256 val = glpManager.getAumInUsdg(false);
        uint256 fee = vault.getFeeBasisPoints(address(usdc), val, vault.mintBurnFeeBasisPoints(), vault.stableTaxBasisPoints(), false);
        val = val * (10000 - fee) / 10000;
        uint256 amtval = val * amt / tot;
        return sha * amtval / totalShares;
    }

    function _mint(address ast, uint256 amt, bytes calldata dat) internal override returns (uint256) {
        earn();
        pull(IERC20(ast), msg.sender, amt);
        uint256 slp = getSlippage(dat);
        uint256 tma = IERC20(rewardRouter.stakedMlpTracker()).balanceOf(address(this));
        IERC20(ast).approve(address(strategyHelper), amt);
        uint256 bal = strategyHelper.swap(ast, address(usdc), amt, slp, address(this));
        uint256 pri = glpManager.getAumInUsdg(true) * 1e18 / glp.totalSupply();
        uint256 minUsd = strategyHelper.value(ast, bal) * slp / 10000;
        uint256 minGlp = minUsd * 1e18 / pri;
        IERC20(ast).approve(address(glpManager), bal);
        uint256 out = rewardRouter.mintAndStakeMlp(ast, bal, minUsd, minGlp);
        return tma == 0 ? out : out * totalShares / tma;
    }

    function _burn(address ast, uint256 sha, bytes calldata dat) internal override returns (uint256) {
        earn();
        uint256 slp = getSlippage(dat);
        uint256 tma = IERC20(rewardRouter.stakedMlpTracker()).balanceOf(address(this));
        uint256 amt = sha * tma / totalShares;
        uint256 pri = glpManager.getAumInUsdg(false) * 1e18 / glp.totalSupply();
        uint256 min = (amt * pri / 1e18) * slp / 10000;
        min = min * (10 ** IERC20(ast).decimals()) / 1e18;
        uint256 out = rewardRouter.unstakeAndRedeemMlp(ast, amt, min, msg.sender);
        usdc.approve(address(strategyHelper), usdc.balanceOf(address(this)));
        return strategyHelper.swap(address(usdc), ast, out, slp, msg.sender);
    }

    function _earn() internal override {
        rewardRouterClaiming.handleRewards(true, true, true, true, true, true, false, true);
    }

    function _exit(address str) internal override {
        _earn();
        push(stakedGlp, str, stakedGlp.balanceOf(address(this)));
    }
}

