// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import { IERC20 } from "./IERC20.sol";
import { IERC4626 } from "./ERC4626.sol";
import { ISwapRouter } from "./ISwapRouter.sol";
import { FullMath } from "./FullMath.sol";
import { ICurveStableSwap } from "./ICurveStableSwap.sol";

interface ICurvePool {
    function exchange_multiple(
        address[9] memory _route,
        uint256[3][4] memory _swapParams,
        uint256 amount,
        uint256 expected,
        address[4] memory _pools,
        address _receiver
    ) external returns (uint256);

    function get_exchange_amount(
        address _poolAddress,
        address _fromToken,
        address _toToken,
        uint256 amount
    ) external returns (uint256);
}

interface ICurveVault {
    function deposit(
        uint256[3] calldata amounts,
        uint256 min_mint_amount
    ) external;
}

interface IRageTradeCurveVault {
    function deposit(
        uint256 amount,
        address receiver
    ) external returns (uint256 shares);
}

interface IPriceOracle {
    function lp_price() external returns (uint256);
}

contract RageTriCryptoDepositor {

    using FullMath for uint256;

    event Completed(address indexed receiver, uint256 lpTokenAmount);
    event DepositPeriphery(address indexed owner, address indexed token, uint256 amount, uint256 asset, uint256 shares);
    event WithdrawCompleted(address indexed receiver, uint256 shares, uint256 crv3Amount, uint256 amountOut);

    error ZeroValue();
    error SlippageToleranceBreached(uint256 crv3received, uint256 lpPrice, uint256 inputAmount);
    error MinAmountNotMet(uint256 amountOut, uint256 minAmountOut);
    error BalanceMismatch(uint256 crv3Balance, uint256 balanceOf);

    address public constant CURVE_SWAP_POOL =
        0x4c2Af2Df2a7E567B5155879720619EA06C5BB15D;
    address public constant CURVE_USDC_USDTPOOL = 0x7f90122BF0700F9E7e1F688fe926940E8839F353;
    address public constant CURVE_TRICRYPTO =
        0xF97c707024ef0DD3E77a0824555a46B622bfB500; // Curve Finance Tricrypto Vault address
    address public constant RAGE_CRV_YIELD_STRATEGY =
        0x1d42783E7eeacae12EbC315D1D2D0E3C6230a068; // RageTrade Curve Tricrypto Vault address
    address public constant RAGE_LP_TOKEN =
        0x1d42783E7eeacae12EbC315D1D2D0E3C6230a068; // LP Token contract address

    IERC20 public usdc = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IERC20 public usdt = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    IERC20 public crv3Crypto = IERC20(0x8e0B8c8BB9db49a46697F3a5Bb8A308e744821D2);
    ISwapRouter public swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    ICurveStableSwap public stableSwap = ICurveStableSwap(0x960ea3e3C7FB317332d990873d354E18d7645590);
    IERC4626 public rage3CryptoVault = IERC4626(0x1d42783E7eeacae12EbC315D1D2D0E3C6230a068);
    IPriceOracle public lpOracle = IPriceOracle(0x2C2FC48c3404a70F2d33290d5820Edf49CBf74a5);

    /// @dev sum of fees + slippage when swapping usdc to usdt
    /* solhint-disable var-name-mixedcase */
    uint256 public MAX_TOLERANCE = 100;
    /* solhint-disable var-name-mixedcase */
    uint256 public MAX_BPS = 10_000;

    function depositUsdc(uint256 amount, address receiver) external returns (uint256 sharesMinted) {
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

        usdc.approve(address(swapRouter), amount);
        uint256 usdtOut = swapRouter.exactInput(params);

        uint256 beforeSwapLpPrice = lpOracle.lp_price();
        usdt.approve(address(stableSwap), usdtOut);
        stableSwap.add_liquidity([usdtOut, 0, 0], 0);

        uint256 crv3Balance = crv3Crypto.balanceOf(address(this));

        // TODO: Remove this line if you want to do rage deposit
        // otherwise transfer curve3Crypto to receiver
        crv3Crypto.transfer(receiver, crv3Balance);

        /// @dev checks combined slippage of uni v3 swap and add liquidity
        if (crv3Balance.mulDiv(beforeSwapLpPrice, 10**18) < (amount * (MAX_BPS - MAX_TOLERANCE) * 10**12) / MAX_BPS) {
            revert SlippageToleranceBreached(crv3Balance, beforeSwapLpPrice, amount);
        }
        crv3Crypto.approve(address(rage3CryptoVault), crv3Balance);
        sharesMinted = rage3CryptoVault.deposit(crv3Balance, receiver);
        emit DepositPeriphery(msg.sender, address(usdc), amount, crv3Balance, sharesMinted);
    }

    // TODO:
    // try deposit and withdraw only from Curve

    function withdrawUsdt(uint256 shares, address receiver, uint256 minAmountOut) external {
        rage3CryptoVault.transferFrom(receiver, address(this), shares);
        uint256 crv3Balance = rage3CryptoVault.redeem(shares, address(this), address(this));
        uint256 usdtTokenIndex = 0; // check
        uint256 balanceOf = crv3Crypto.balanceOf(address(this));
        if (crv3Balance != balanceOf) {
            revert BalanceMismatch(crv3Balance, balanceOf);
        }
        crv3Crypto.approve(address(stableSwap), crv3Balance);
        uint256 usdtAmount = stableSwap.remove_liquidity_one_coin(crv3Balance, usdtTokenIndex, minAmountOut);
        if (usdtAmount < minAmountOut) {
            revert MinAmountNotMet(usdtAmount, minAmountOut);
        }
        if (usdtAmount == 0) {
            revert ZeroValue();
        }

        usdt.transfer(receiver, usdtAmount);

        emit WithdrawCompleted(receiver, shares, crv3Balance, usdtAmount);
    }

    function withdrawCryptos(uint256 shares, address receiver, uint256 minAmountOut) external {
        rage3CryptoVault.transferFrom(receiver, address(this), shares);// added this
        uint256 crv3Balance = rage3CryptoVault.redeem(shares, address(this), address(this));
        crv3Crypto.approve(address(stableSwap), crv3Balance);
        uint256 balanceOf = crv3Crypto.balanceOf(address(this));
        if (crv3Balance != balanceOf) {
            revert BalanceMismatch(crv3Balance, balanceOf);
        }

        uint256[3] memory minAmountsOut = [uint(0), 0, 0];
        uint256[3] memory amounts = stableSwap.remove_liquidity(crv3Balance, minAmountsOut);
        for (uint256 i = 0; i < amounts.length; i++) {
            if (amounts[i] == 0) {
                revert ZeroValue();
            }
        }
        
        address[3] memory tokens = [address(0), address(0), address(0)]; 
        // TODO: transer 3 tokens to receiver
        for (uint256 i = 0; i < amounts.length; i++) {
            IERC20(tokens[i]).transfer(receiver, amounts[i]);
        }
    }

    function swapUSDCforUSDT(uint256 usdcAmount) public returns (uint256) {
        // Approve CurvePool to spend the USDC tokens
        usdc.approve(CURVE_SWAP_POOL, usdcAmount);

        // Create a reference to the CurvePool contract
        ICurvePool curvePool = ICurvePool(CURVE_SWAP_POOL);

        // Calculate the minimum USDT amount to receive
        uint256 minUsdtAmount = curvePool.get_exchange_amount(
            CURVE_USDC_USDTPOOL,
            address(usdc),
            address(usdt),
            usdcAmount
        );

        address[9] memory route;
        route[0] = address(usdc);
        route[1] = CURVE_USDC_USDTPOOL;
        route[2] = address(usdt);

        uint256[3][4] memory swapParams = [
            [uint(0), 1, 1],
            [uint(0), 0, 0],
            [uint(0), 0, 0],
            [uint(0), 0, 0]
        ];
        address zeroAddress = address(0x0);
        address[4] memory pools = [zeroAddress, zeroAddress, zeroAddress, zeroAddress];
        // Swap USDC for USDT
        uint256 usdtReceived = curvePool.exchange_multiple(
            route,
            swapParams,
            usdcAmount,
            minUsdtAmount,
            pools,
            address(this)
        );

        return usdtReceived;

        // Transfer the received USDT tokens to the caller
        // IERC20(usdtAddress).transfer(
        //     msg.sender,
        //     IERC20(usdtAddress).balanceOf(usdtReceived)
        // );
    }
}

