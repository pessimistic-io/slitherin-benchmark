// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Strategy} from "./Strategy.sol";
import {IGlpManager, IRewardRouter} from "./IGMX.sol";
import {IERC20} from "./IERC20.sol";
import {PartnerProxy} from "./PartnerProxy.sol";

interface IPlutusDepositor {
    function sGLP() external view returns (address);
    function fsGLP() external view returns (address);
    function vault() external view returns (address);
    function minter() external view returns (address);
    function deposit(uint256 amount) external;
    function redeem(uint256 amount) external;
}

interface IPlutusFarm {
    function pls() external view returns (address);
    function userInfo(address) external view returns (uint96, int128);
    function deposit(uint96) external;
    function withdraw(uint96) external;
    function harvest() external;
}

interface IPlutusVault {
    function convertToAssets(uint256 shares) external view returns (uint256 assets);
}

contract StrategyPlutusPlvGlp is Strategy {
    error MintedTooLittle();

    string public constant name = "PlutusDAO plvGLP";
    PartnerProxy public proxy;
    IRewardRouter public glpRouter;
    IGlpManager public glpManager;
    IPlutusDepositor public plsDepositor;
    IPlutusFarm public plsFarm;

    IERC20 public usdc;
    IERC20 public glp;
    IERC20 public sGlp;
    IERC20 public fsGlp;
    IERC20 public pls;
    IERC20 public plvGlp;

    constructor(address _strategyHelper, address _proxy, address _glpRouter, address _plsDepositor, address _plsFarm, address _usdc)
        Strategy(_strategyHelper)
    {
        proxy = PartnerProxy(_proxy);
        glpRouter = IRewardRouter(_glpRouter);
        glpManager = IGlpManager(glpRouter.glpManager());
        glp = IERC20(glpManager.glp());
        plsDepositor = IPlutusDepositor(_plsDepositor);
        plsFarm = IPlutusFarm(_plsFarm);
        usdc = IERC20(_usdc);
        sGlp = IERC20(plsDepositor.sGLP());
        fsGlp = IERC20(plsDepositor.fsGLP());
        pls = IERC20(plsFarm.pls());
        plvGlp = IERC20(plsDepositor.vault());
    }

    function setGlp(address _glpRouter) public auth {
        glpRouter = IRewardRouter(_glpRouter);
        glpManager = IGlpManager(glpRouter.glpManager());
        glp = IERC20(glpManager.glp());
    }

    function setDepositor(address _plsDepositor) public auth {
        plsDepositor = IPlutusDepositor(_plsDepositor);
        sGlp = IERC20(plsDepositor.sGLP());
        fsGlp = IERC20(plsDepositor.fsGLP());
        plvGlp = IERC20(plsDepositor.vault());
    }

    function setFarm(address _plsFarm) public auth {
        plsFarm = IPlutusFarm(_plsFarm);
        pls = IERC20(plsFarm.pls());
    }

    function _rate(uint256 sha) internal view override returns (uint256) {
        uint256 amt = IPlutusVault(address(plvGlp)).convertToAssets(totalManagedAssets());
        uint256 pri = glpManager.getPrice(false);
        uint256 tot = amt * pri / glpManager.PRICE_PRECISION();
        return sha * tot / totalShares;
    }

    function _mint(address ast, uint256 amt, bytes calldata dat) internal override returns (uint256) {
        earn();
        uint256 slp = getSlippage(dat);
        uint256 tma = totalManagedAssets();
        pull(IERC20(ast), msg.sender, amt);
        IERC20(ast).approve(address(strategyHelper), amt);
        strategyHelper.swap(ast, address(usdc), amt, slp, address(this));
        uint256 qty = _mintGlpAndPlvGlp(slp);
        if (qty == 0) revert MintedTooLittle();
        return tma == 0 ? qty : (qty * totalShares) / tma;
    }

    function _burn(address ast, uint256 sha, bytes calldata dat) internal override returns (uint256) {
        uint256 slp = getSlippage(dat);
        uint256 amt = (sha * totalManagedAssets()) / totalShares;
        proxy.call(address(plsFarm), 0, abi.encodeWithSignature("withdraw(uint96)", amt));
        proxy.call(address(plvGlp), 0, abi.encodeWithSignature("approve(address,uint256)", address(plsDepositor), amt));
        proxy.call(address(plsDepositor), 0, abi.encodeWithSignature("redeem(uint256)", amt));
        amt = fsGlp.balanceOf(address(proxy));
        proxy.call(address(sGlp), 0, abi.encodeWithSignature("transfer(address,uint256)", address(this), amt));
        uint256 pri = (glpManager.getAumInUsdg(false) * 1e18) / glp.totalSupply();
        uint256 min = (((amt * pri) / 1e18) * (10000 - slp)) / 10000;
        min = (min * (10 ** IERC20(usdc).decimals())) / 1e18;
        amt = glpRouter.unstakeAndRedeemGlp(address(usdc), amt, min, address(this));
        usdc.approve(address(strategyHelper), amt);
        return strategyHelper.swap(address(usdc), ast, amt, slp, msg.sender);
    }

    function _earn() internal override {
        proxy.call(address(plsFarm), 0, abi.encodeWithSignature("harvest()"));
        proxy.pull(address(pls));
        uint256 amt = pls.balanceOf(address(this));
        if (strategyHelper.value(address(pls), amt) < 0.5e18) return;
        pls.approve(address(strategyHelper), amt);
        strategyHelper.swap(address(pls), address(usdc), amt, slippage, address(this));
        _mintGlpAndPlvGlp(slippage);
    }

    function _exit(address str) internal override {
        push(IERC20(address(pls)), str, pls.balanceOf(address(this)));
        proxy.setExec(str, true);
        proxy.setExec(address(this), false);
    }

    function _move(address) internal override {
        // proxy already owns farm deposit
    }

    function _mintGlpAndPlvGlp(uint256 slp) private returns (uint256) {
        _mintGlp(slp);
        _mintPlvGlp();
        return _depositIntoFarm();
    }

    function _mintPlvGlp() private returns (uint256) {
        uint256 amt = fsGlp.balanceOf(address(this));
        if (amt <= 1e18) return 0;
        sGlp.transfer(address(proxy), amt);
        proxy.call(address(sGlp), 0, abi.encodeWithSignature("approve(address,uint256)", address(plsDepositor), amt));
        proxy.call(address(plsDepositor), 0, abi.encodeWithSignature("deposit(uint256)", amt));
        return amt;
    }

    function _depositIntoFarm() private returns (uint256) {
        uint256 amt = plvGlp.balanceOf(address(proxy));
        if (amt == 0) return 0;
        proxy.call(address(plvGlp), 0, abi.encodeWithSignature("approve(address,uint256)", address(plsFarm), amt));
        proxy.call(address(plsFarm), 0, abi.encodeWithSignature("deposit(uint96)", uint96(amt)));
        return amt;
    }

    function _mintGlp(uint256 slp) private {
        uint256 amt = usdc.balanceOf(address(this));
        uint256 pri = (glpManager.getAumInUsdg(true) * 1e18) / glp.totalSupply();
        uint256 minUsd = (strategyHelper.value(address(usdc), amt) * (10000 - slp)) / 10000;
        uint256 minGlp = (minUsd * 1e18) / pri;
        usdc.approve(address(glpManager), amt);
        glpRouter.mintAndStakeGlp(address(usdc), amt, minUsd, minGlp);
    }


    function totalManagedAssets() internal view returns (uint256) {
        (uint96 tma,) = plsFarm.userInfo(address(proxy));
        return uint256(tma);
    }
}

