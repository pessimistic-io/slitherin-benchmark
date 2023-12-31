// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IWETH9 } from "./IWETH9.sol";
import { IERC4626 } from "./IERC4626.sol";
import { IERC20 } from "./IERC20.sol";

import { ISwapRouter } from "./ISwapRouter.sol";

import { ILPPriceGetter } from "./ILPPriceGetter.sol";
import { ICurveStableSwap } from "./ICurveStableSwap.sol";

import { AggregatorV3Interface } from "./AggregatorV3Interface.sol";

import { FullMath } from "./FullMath.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";

/* solhint-disable not-rely-on-time */

contract VaultPeriphery is OwnableUpgradeable {
    using FullMath for uint256;

    error ZeroValue();
    error OutOfBounds();
    error NegativePrice();
    error SlippageToleranceBreached(uint256 crv3received, uint256 lpPrice, uint256 inputAmount);

    event DepositPeriphery(address indexed owner, address indexed token, uint256 amount, uint256 asset, uint256 shares);

    event SlippageToleranceUpdated(uint256 oldTolerance, uint256 newTolerance);

    event SwapRouterUpdated(address indexed oldSwapRouter, address indexed newSwapRouter);

    event EthOracleUpdated(address indexed oldEthOracle, address indexed newEthOracle);

    IERC20 public usdc;
    IERC20 public usdt;
    IWETH9 public weth;
    IERC20 public lpToken;

    IERC4626 public vault;

    ISwapRouter public swapRouter;
    ILPPriceGetter public lpOracle;
    ICurveStableSwap public stableSwap;

    AggregatorV3Interface internal ethOracle;

    /// @dev sum of fees + slippage when swapping usdc to usdt
    /* solhint-disable var-name-mixedcase */
    uint256 public MAX_TOLERANCE = 100;
    /* solhint-disable var-name-mixedcase */
    uint256 public MAX_BPS = 10_000;

    function initialize(
        IERC20 _usdc,
        IERC20 _usdt,
        IWETH9 _weth,
        IERC20 _lpToken,
        IERC4626 _vault,
        ISwapRouter _swapRouter,
        ILPPriceGetter _lpOracle,
        ICurveStableSwap _stableSwap,
        AggregatorV3Interface _ethOracle
    ) external initializer {
        __Ownable_init();

        usdc = _usdc;
        usdt = _usdt;
        weth = _weth;
        vault = _vault;
        lpToken = _lpToken;

        lpOracle = _lpOracle;
        stableSwap = _stableSwap;
        swapRouter = _swapRouter;

        ethOracle = _ethOracle;

        weth.approve(address(stableSwap), type(uint256).max);
        usdt.approve(address(stableSwap), type(uint256).max);

        usdc.approve(address(swapRouter), type(uint256).max);

        lpToken.approve(address(vault), type(uint256).max);
    }

    function _getEthPrice(AggregatorV3Interface crvOracle) internal view returns (uint256) {
        (, int256 answer, , , ) = crvOracle.latestRoundData();
        if (answer < 0) revert NegativePrice();
        return (uint256(answer));
    }

    function depositUsdc(uint256 amount) external returns (uint256 sharesMinted) {
        if (amount == 0) revert ZeroValue();
        usdc.transferFrom(msg.sender, address(this), amount);

        bytes memory path = abi.encodePacked(usdc, uint24(500), usdt);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            amountIn: amount,
            amountOutMinimum: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        uint256 usdtOut = swapRouter.exactInput(params);

        uint256 beforeSwapLpPrice = lpOracle.lp_price();

        stableSwap.add_liquidity([usdtOut, 0, 0], 0);

        uint256 balance = lpToken.balanceOf(address(this));

        /// @dev checks combined slippage of uni v3 swap and add liquidity
        if (balance.mulDiv(beforeSwapLpPrice, 10**18) < (amount * (MAX_BPS - MAX_TOLERANCE) * 10**12) / MAX_BPS) {
            revert SlippageToleranceBreached(balance, beforeSwapLpPrice, amount);
        }

        sharesMinted = vault.deposit(balance, msg.sender);
        emit DepositPeriphery(msg.sender, address(usdc), amount, balance, sharesMinted);
    }

    function depositWeth(uint256 amount) public returns (uint256 sharesMinted) {
        if (amount == 0) revert ZeroValue();
        weth.transferFrom(msg.sender, address(this), amount);

        uint256 beforeSwapLpPrice = lpOracle.lp_price();

        stableSwap.add_liquidity([0, 0, amount], 0);

        uint256 balance = lpToken.balanceOf(address(this));

        if (
            balance.mulDiv(beforeSwapLpPrice, 10**18) <
            _getEthPrice(ethOracle).mulDiv(amount * (MAX_BPS - MAX_TOLERANCE), 10**8 * MAX_BPS)
        ) {
            revert SlippageToleranceBreached(balance, beforeSwapLpPrice, amount);
        }

        sharesMinted = vault.deposit(lpToken.balanceOf(address(this)), msg.sender);
        emit DepositPeriphery(msg.sender, address(weth), amount, balance, sharesMinted);
    }

    function depositEth() external payable returns (uint256 sharesMinted) {
        weth.deposit{ value: msg.value }();

        uint256 beforeSwapLpPrice = lpOracle.lp_price();

        stableSwap.add_liquidity([0, 0, msg.value], 0);

        uint256 balance = lpToken.balanceOf(address(this));

        if (
            balance.mulDiv(beforeSwapLpPrice, 10**18) <
            _getEthPrice(ethOracle).mulDiv(msg.value * (MAX_BPS - MAX_TOLERANCE), 10**8 * MAX_BPS)
        ) {
            revert SlippageToleranceBreached(balance, beforeSwapLpPrice, msg.value);
        }

        sharesMinted = vault.deposit(lpToken.balanceOf(address(this)), msg.sender);
        emit DepositPeriphery(msg.sender, address(0), msg.value, balance, sharesMinted);
    }

    function updateTolerance(uint256 newTolerance) external onlyOwner {
        if (newTolerance > MAX_BPS) revert OutOfBounds();
        emit SlippageToleranceUpdated(MAX_TOLERANCE, newTolerance);
        MAX_TOLERANCE = newTolerance;
    }

    function updateSwapRouter(address newRouter) external onlyOwner {
        if (newRouter == address(0)) revert ZeroValue();
        usdc.approve(newRouter, 0);
        usdc.approve(newRouter, type(uint256).max);
        emit SwapRouterUpdated(address(swapRouter), newRouter);
        swapRouter = ISwapRouter(newRouter);
    }

    function updateEthOracle(address newOracle) external onlyOwner {
        if (newOracle == address(0)) revert ZeroValue();
        emit EthOracleUpdated(address(ethOracle), newOracle);
        ethOracle = AggregatorV3Interface(newOracle);
    }
}

