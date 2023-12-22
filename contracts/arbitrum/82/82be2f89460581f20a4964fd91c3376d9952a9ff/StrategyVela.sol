// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Strategy} from "./Strategy.sol";
import {IERC20} from "./IERC20.sol";

interface IVault {
    function getVLPPrice() external view returns (uint256);
    function stake(address usr, address tkn, uint256 amt) external;
    function unstake(address tkn, uint256 amt, address usr) external;
}

contract StrategyVela is Strategy {
    string public constant name = "Vela VLP";
    IVault public vault;
    IERC20 public lp;
    IERC20 public usdc;

    constructor(
        address _strategyHelper,
        address _vault,
        address _lp,
        address _usdc
    ) Strategy(_strategyHelper) {
        vault = IVault(_vault);
        lp = IERC20(_lp);
        usdc = IERC20(_usdc);
    }

    function _rate(uint256 sha) internal view override returns (uint256) {
        uint256 amt = lp.balanceOf(address(this)) * 1e6 / 1e18;
        uint256 pri = vault.getVLPPrice();
        uint256 val = strategyHelper.value(address(usdc), amt * pri / 100000);
        return sha * val / totalShares;
    }

    function _mint(address ast, uint256 amt, bytes calldata dat) internal override returns (uint256) {
        pull(IERC20(ast), msg.sender, amt);
        uint256 tma = lp.balanceOf(address(this));
        uint256 slp = getSlippage(dat);
        IERC20(ast).approve(address(strategyHelper), amt);
        uint256 bal = strategyHelper.swap(ast, address(usdc), amt, slp, address(this));
        usdc.approve(address(vault), amt);
        vault.stake(address(this), address(usdc), bal);
        uint256 out = lp.balanceOf(address(this)) - tma;
        return tma == 0 ? out : out * totalShares / tma;
    }

    function _burn(address ast, uint256 sha, bytes calldata dat) internal override returns (uint256) {
        uint256 tma = lp.balanceOf(address(this));
        uint256 slp = getSlippage(dat);
        uint256 amt = sha * tma / totalShares;
        vault.unstake(address(usdc), amt, address(this));
        usdc.approve(address(strategyHelper), usdc.balanceOf(address(this)));
        return strategyHelper.swap(address(usdc), ast, amt, slp, msg.sender);
    }

    function _earn() internal override {}

    function _exit(address str) internal override {
        push(lp, str, lp.balanceOf(address(this)));
    }
}

