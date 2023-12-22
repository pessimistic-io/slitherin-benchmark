// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

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
}

interface IRewardTracker {
    function claimable(address) external view returns (uint256);
    function depositBalances(address _account, address _depositToken) external view returns (uint256);
}

interface IOracle {
    function latestAnswer() external view returns (int256);
}

contract StrategyGMXGLP is Strategy {
    uint256 public constant bipsDivisor = 10000;

    string public name = "GMX GLP";
    uint256 public slippage = 9900;
    IRewardRouter public rewardRouter;
    IGlpManager public glpManager;
    IERC20 public glp;
    IOracle public oracle; // Chainlink for ETH fee reward token
    address public weth;

    constructor(
        address _asset,
        address _investor,
        address _rewardRouter,
        address _oracle,
        address _weth
    )
        Strategy(_asset, _investor)
    {
        rewardRouter = IRewardRouter(_rewardRouter);
        glpManager = IGlpManager(rewardRouter.glpManager());
        glp = IERC20(glpManager.glp());
        oracle = IOracle(_oracle);
        weth = _weth;
    }

    function setSlippage(uint256 _slippage) external auth {
        slippage = _slippage;
    }

    function rate(uint256 sha) external view override returns (uint256) {
        uint256 tma = IERC20(rewardRouter.stakedGlpTracker()).balanceOf(address(this));
        uint256 aumInUsdg = glpManager.getAumInUsdg(false);
        uint256 glpSupply = glp.totalSupply();
        uint256 usdgAmount = tma * aumInUsdg / glpSupply;

        uint256 ethRewards =
            IRewardTracker(rewardRouter.feeGlpTracker()).claimable(address(this));
        uint256 ethPrice = uint256(oracle.latestAnswer());
        // GLP is 1e18, while oracle price is 1e8, so division by 1e20 is required to get to 1e6 for USDC
        uint256 feesUsd = ethRewards * ethPrice / 1e20;
        uint256 valueUsd = (usdgAmount / 1e12) + feesUsd;

        return sha * valueUsd / totalShares;
    }

    function _mint(uint256 amt) internal override returns (uint256) {
        compound();

        uint256 glpPrice =
            glpManager.getAumInUsdg(true) * 1e18 / glp.totalSupply();
        uint256 minGlp = ((amt * 1e30 / glpPrice) * slippage) / bipsDivisor;
        uint256 minUsdg = amt * 1e12 * slippage / bipsDivisor;

        uint256 tma = IERC20(rewardRouter.stakedGlpTracker()).balanceOf(address(this));

        asset.approve(address(glpManager), amt);
        uint256 newGlp =
            rewardRouter.mintAndStakeGlp(address(asset), amt, minUsdg, minGlp);

        return tma == 0 ? newGlp : newGlp * totalShares / tma;
    }

    function _burn(uint256 sha) internal override returns (uint256) {
        compound();

        uint256 tma = IERC20(rewardRouter.stakedGlpTracker()).balanceOf(address(this));
        uint256 glpAmount = sha * tma / totalShares;

        uint256 glpPrice =
            glpManager.getAumInUsdg(false) * 1e18 / glp.totalSupply();
        uint256 minAmt = ((glpAmount * glpPrice / 1e30) * slippage) / bipsDivisor;

        return rewardRouter.unstakeAndRedeemGlp(
            address(asset), glpAmount, minAmt, address(this)
        );
    }

    function compound() public {
        rewardRouter.handleRewards(true, true, true, true, true, true, false);

        uint256 wethBalance = IERC20(weth).balanceOf(address(this));

        if (wethBalance > 0) {
            IERC20(weth).approve(address(glpManager), wethBalance);
            rewardRouter.mintAndStakeGlp(weth, wethBalance, 0, 0);
        }
    }
}

