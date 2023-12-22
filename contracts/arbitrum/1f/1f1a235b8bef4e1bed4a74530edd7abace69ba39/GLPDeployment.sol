// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./ERC20_IERC20.sol";
import "./ITreasury.sol";
import "./IDeployment.sol";
import "./IUniswapV2Router.sol";
import "./Deployment.sol";

import "./UmamiAccessControlled.sol";


interface IRewardRouterV2 {
    function unstakeAndRedeemGlp(
        address _tokenOut,
        uint256 _glpAmount,
        uint256 _minOut,
        address _receiver
    ) external returns (uint256);
    function mintAndStakeGlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minGlp
    ) external returns (uint256);
    function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external;
    function claimEsGmx() external;
}

interface IVester {
    function deposit(uint256 _amount) external;
}

interface IRewardTracker {
    function claimable(address _account) external view returns (uint256);
}

contract GLPDeployment is Deployment {
    using SafeERC20 for IERC20;

    address constant usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address constant esGmx = 0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA;
    address constant gmx = 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a;
    address constant vGmx = 0x199070DDfd1CFb69173aa2F7e20906F26B363004;
    address constant sbfGmx = 0xd2D1162512F927a7e282Ef43a362659E4F2a728F;
    address constant fGlp = 0x4e971a87900b931fF39d1Aad67697F49835400b6;
    address constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; 
    address constant glpRewardRouter = 0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1;
    address constant stakedGlp = 0x1aDDD80E6039594eE970E5872D247bf0414C8903;
    address constant vester = 0xA75287d2f8b217273E7FCD7E86eF07D33972042E;
    address constant glpManager = 0x321F653eED006AD1C29D174e17d96351BDe22649;

    constructor(
        IDeploymentManager manager, 
        ITreasury treasury, 
        address sushiRouter) Deployment(manager, treasury, sushiRouter) {}

    function deposit(uint256 amount, bool fromTreasury) external override onlyDepositWithdrawer {
        if (fromTreasury) {
            treasury.manage(usdc, amount);
        } else {
            IERC20(usdc).safeTransferFrom(msg.sender, address(this), amount);
        }

        _deposit(amount);
    }

    function _deposit(uint256 amount) internal {
        IERC20(usdc).approve(glpManager, amount);
        uint256 amountWithSlippage = getSlippageAdjustedAmount(amount, 10 /* 1% */);
        IRewardRouterV2(glpRewardRouter).mintAndStakeGlp(usdc, amount, amountWithSlippage, 0 /* _minGlp */);

        emit Deposit(amount);
    }

    function withdraw(uint256 amount) public override onlyDepositWithdrawer {
        uint256 outputAmount = IRewardRouterV2(glpRewardRouter).unstakeAndRedeemGlp(usdc, amount, 0, address(this));
        IERC20(usdc).safeTransfer(address(treasury), outputAmount);

        emit Withdraw(amount);
    }

    function withdrawAll(bool dumpTokensForWeth) external override onlyDepositWithdrawer {
        uint256 glpAmount = IERC20(stakedGlp).balanceOf(address(this));
        withdraw(glpAmount);
        harvest(dumpTokensForWeth);
    }

    function harvest(bool dumpTokensForWeth) public override onlyDepositWithdrawerOrAutomation {
        uint256 wethAmount = IERC20(weth).balanceOf(address(this));
        uint256 gmxAmount = IERC20(gmx).balanceOf(address(this));

        // Claim GMX and WETH rewards, restake esGMX
        IRewardRouterV2(glpRewardRouter).handleRewards(true, false, true, true, true, true, false);

        wethAmount = IERC20(weth).balanceOf(address(this)) - wethAmount;
        gmxAmount = IERC20(gmx).balanceOf(address(this)) - gmxAmount;

        if (dumpTokensForWeth && gmxAmount > 0) {
            address[] memory path = new address[](2);
            path[0] = gmx;
            path[1] = weth;
            uint256 soldEthAmount = swapToken(path, gmxAmount, 0);
            uint256 totalEthAmount = soldEthAmount + wethAmount;
            distributeToken(weth, totalEthAmount);
        }
        else {
            distributeToken(weth, wethAmount);
            distributeToken(gmx, gmxAmount);
        }

        emit Harvest(dumpTokensForWeth);
    }

    function vestEsGmx() public onlyDepositWithdrawerOrAutomation {
        uint256 esGmxAmount = IERC20(esGmx).balanceOf(address(this));
        require(esGmxAmount > 0, "No esGMX to vest");
        IVester(vester).deposit(esGmxAmount);
    }

    function claimEsGmx() public onlyDepositWithdrawerOrAutomation {
        IRewardRouterV2(glpRewardRouter).handleRewards(false, false, true, false, false, false, false);
    }

    function compound() external override onlyDepositWithdrawerOrAutomation {
        IRewardRouterV2(glpRewardRouter).handleRewards(true, true, true, true, true, true, false);
    }

    function balance(address token) view public override returns (uint256) {
        if (token == stakedGlp) {
            // Normal GLP balance
            return IERC20(stakedGlp).balanceOf(address(this));
        }
        else if (token == vGmx) {
            // Vesting esGMX
            return IERC20(vGmx).balanceOf(address(this));
        }
        return 0;
    }

    function pendingRewards(address token) view public override returns (uint256) {
        if (token == weth) {
            // wETH rewards come from fGLP and sbfGMX
            uint256 fglpRewards = IRewardTracker(fGlp).claimable(address(this));
            uint256 sbfgmxRewards = IRewardTracker(sbfGmx).claimable(address(this));
            return fglpRewards + sbfgmxRewards;
        }
        return 0;
    }
}
