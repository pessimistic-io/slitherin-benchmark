// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20Upgradeable as IERC20} from "./ERC20_IERC20Upgradeable.sol";
import {Ownable2StepUpgradeable} from "./Ownable2StepUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./MathUpgradeable.sol";
import "./IPlatformAdapter.sol";
import "./IAdapter.sol";
import "./IUniswapV3Adapter.sol";
import "./IUniswapV3Router.sol";
import "./IQuoterV2.sol";
import "./BytesLib.sol";
import "./ITraderWallet.sol";

contract UniswapV3Adapter is Ownable2StepUpgradeable {
    using BytesLib for bytes;
    using MathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event Buy(
        address tokenIn,
        address tokenOut,
        uint256 boughtAmount,
        uint256 soldAmount
    );
    event Sell(
        address tokenIn,
        address tokenOut,
        uint256 boughtAmount,
        uint256 soldAmount
    );

    IUniswapV3Router public constant uniswapV3Router =
        IUniswapV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IQuoterV2 public constant quoter =
        IQuoterV2(0x61fFE014bA17989E743c5F6cB21bF9697530B21e);

    uint256 public constant ratioDenominator = 1e18;

    /// @notice The maximum slippage allowance
    uint128 public constant slippageAllowanceMax = 3e17; // 30%

    /// @notice The minimum slippage allowance
    uint128 public constant slippageAllowanceMin = 1e15; // 0.1%

    /// @notice The current slippage allowance
    uint256 public slippage;

    error AddressZero();
    error InvalidOperationId();
    error InvalidSlippage();
    error NotSupportedTokens(address, address);

    event SlippageAllowance(uint256 slippage);

    function initialize() external initializer {
        __Ownable2Step_init();
        uint256 _slippage = 4e16; // 4%
        setSlippageAllowance(_slippage);
    }

    /// @notice Executes operation with external protocol
    /// @param isTraderWallet The flag, 'true' if caller is TraderWallet (and it will calculate ratio for UsersVault)
    /// @param traderWallet The address of TraderWallet contract
    /// @param usersVault The address of UsersVault contract (linked to TraderWallet)
    /// @param ratio Scaling ratio to
    /// @param traderOperation Encoded operation data
    /// @return bool 'true' if the operation completed successfully
    /// @return uint256 Calculated scale ratio for further UsersVault's trade

    function executeOperation(
        bool isTraderWallet,
        address traderWallet,
        address usersVault,
        uint256 ratio,
        IAdapter.AdapterOperation memory traderOperation
    ) external returns (bool, uint256) {
        if (traderOperation.operationId == 0) {
            return
                _buy(
                    isTraderWallet,
                    traderWallet,
                    usersVault,
                    ratio,
                    traderOperation.data
                );
        } else if (traderOperation.operationId == 1) {
            return
                _sell(
                    isTraderWallet,
                    traderWallet,
                    usersVault,
                    ratio,
                    traderOperation.data
                );
        }

        revert InvalidOperationId();
    }

    /// @notice Swaps as little as possible of one token (tokenIn) for exact `amountOut` of another token
    ///         It's recommended to use sell() function for the trading due to easiest slippage config
    /// @dev swap path must be reversed (tokenOut <- fee <- tokenIn)
    /// @param isTraderWallet The flag, 'true' if caller is TraderWallet (and it will calculate ratio for UsersVault)
    /// @param traderWallet The address of TraderWallet contract
    /// @param usersVault The address of UsersVault contract (linked to TraderWallet)
    /// @param ratio The coefficient to scale amounts. Necessary for UsersVault only (when 'isTrader'=false)
    /// @param tradeData The bytes representation of trade parameters
    /// @return true if swap successful
    /// @return ratio_ Calculated scale ratio for further UsersVault's trade
    function _buy(
        bool isTraderWallet,
        address traderWallet,
        address usersVault,
        uint256 ratio,
        bytes memory tradeData
    ) internal returns (bool, uint256 ratio_) {
        // exact output swap to ensure exact amount of tokens are received
        (bytes memory path, uint256 amountOut, uint256 amountInMaximum) = abi
            .decode(tradeData, (bytes, uint256, uint256));
        // output swaps requires reversed path, thus 'tokenIn' is last one
        address tokenIn = path.toAddress(path.length - 20);
        address tokenOut = path.toAddress(0);

        if (isTraderWallet) {
            if (!_validateTradeTokens(traderWallet, tokenIn, tokenOut)) {
                revert NotSupportedTokens(tokenIn, tokenOut);
            }
            // calculate ratio for userVault
            uint256 traderBalance = IERC20(tokenIn).balanceOf(traderWallet);
            uint256 vaultBalance = IERC20(tokenIn).balanceOf(usersVault);
            ratio_ = vaultBalance.mulDiv(
                ratioDenominator,
                traderBalance,
                MathUpgradeable.Rounding.Up
            );
        } else {
            // scaling for Vault execution
            // be careful - more amount requires more available balance due to price impact
            amountOut = (amountOut * ratio) / ratioDenominator;

            // increasing slippage allowance due to higher amounts
            amountInMaximum =
                (amountInMaximum * ratio) /
                (ratioDenominator - slippage);

            uint256 amountInAvailable = IERC20(tokenIn).balanceOf(msg.sender);
            // trying to decrease amountIn according to current balance
            if (amountInAvailable <= amountInMaximum) {
                amountInMaximum = amountInAvailable;
            }
        }

        IERC20(tokenIn).safeTransferFrom(
            msg.sender,
            address(this),
            amountInMaximum
        );
        _checkUpdateAllowance(
            tokenIn,
            address(uniswapV3Router),
            amountInMaximum
        );

        IUniswapV3Router.ExactOutputParams memory params = IUniswapV3Router
            .ExactOutputParams({
                path: path,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: amountInMaximum
            });
        uint256 soldAmount = uniswapV3Router.exactOutput(params);

        // case when 'amountInMaximum' was not reach entirely
        uint256 leftovers = IERC20(tokenIn).balanceOf(address(this));
        if (leftovers > 0) {
            IERC20(tokenIn).safeTransfer(msg.sender, leftovers);
        }

        emit Buy(tokenIn, tokenOut, amountOut, soldAmount);
        return (true, ratio_);
    }

    /// @notice Swaps exact `amountIn` of input token for as much as possible of another along the specified path
    /// @param isTraderWallet The flag, 'true' if caller is TraderWallet (and it will calculate ratio for UsersVault)
    /// @param traderWallet The address of TraderWallet contract (can be Zero  when 'isTrader'=false)
    /// @param usersVault The address of UsersVault contract (linked to TraderWallet)
    /// @param ratio The coefficient to scale amounts. Necessary for UsersVault only (when 'isTrader'=false)
    /// @param ratio The coefficient to scale amounts (necessary for Vault)
    /// @param tradeData The bytes representation of trade parameters
    /// @return true if swap successful
    /// @return ratio_ Calculated scale ratio for further UsersVault's trade
    function _sell(
        bool isTraderWallet,
        address traderWallet,
        address usersVault,
        uint256 ratio,
        bytes memory tradeData
    ) internal returns (bool, uint256 ratio_) {
        // exact input swap to convert exact amount of tokens into usdc
        (bytes memory path, uint256 amountIn, uint256 amountOutMinimum) = abi
            .decode(tradeData, (bytes, uint256, uint256));

        address tokenIn = path.toAddress(0);
        address tokenOut = path.toAddress(path.length - 20);

        if (isTraderWallet) {
            if (!_validateTradeTokens(traderWallet, tokenIn, tokenOut)) {
                revert NotSupportedTokens(tokenIn, tokenOut);
            }
            // calculate ratio for userVault
            uint256 traderBalance = IERC20(tokenIn).balanceOf(traderWallet);
            uint256 vaultBalance = IERC20(tokenIn).balanceOf(usersVault);
            // we сan safely use Rounding.Up because any excess will be correctly handled
            ratio_ = vaultBalance.mulDiv(
                ratioDenominator,
                traderBalance,
                MathUpgradeable.Rounding.Up
            );
        } else {
            // scaling for Vault execution
            amountIn = (amountIn * ratio) / ratioDenominator;
            // increasing slippage allowance due to higher amounts
            amountOutMinimum =
                (amountOutMinimum * ratio) /
                (ratioDenominator + slippage);

            uint256 amountInAvailable = IERC20(tokenIn).balanceOf(msg.sender);
            // decrease amountIn according to current balance
            if (amountInAvailable <= amountIn) {
                amountIn = amountInAvailable;
            }
        }

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        _checkUpdateAllowance(tokenIn, address(uniswapV3Router), amountIn);

        IUniswapV3Router.ExactInputParams memory params = IUniswapV3Router
            .ExactInputParams({
                path: path,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum
            });

        // since exact input swap tokens used = token amount passed
        uint256 boughtAmount = uniswapV3Router.exactInput(params);

        emit Sell(tokenIn, tokenOut, boughtAmount, amountIn);
        return (true, ratio_);
    }

    /// @notice Returns the amount out received for a given exact input swap without executing the swap
    /// @param path The path of the swap, i.e. each token pair and the pool fee
    /// @param amountIn The amount of the first token to swap
    /// @return amountOut The amount of the last token that would be received
    /// @return sqrtPriceX96AfterList List of the sqrt price after the swap for each pool in the path
    /// @return initializedTicksCrossedList List of the initialized ticks that the swap crossed for each pool in the path
    /// @return gasEstimate The estimate of the gas that the swap consumes
    function getAmountOut(
        bytes memory path,
        uint256 amountIn
    )
        external
        returns (
            uint256 amountOut,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        )
    {
        return quoter.quoteExactInput(path, amountIn);
    }

    /// @notice Returns the amount in required for a given exact output swap without executing the swap
    /// @param path The path of the swap, i.e. each token pair and the pool fee. Path must be provided in reverse order
    /// @param amountOut The amount of the last token to receive
    /// @return amountIn The amount of first token required to be paid
    /// @return sqrtPriceX96AfterList List of the sqrt price after the swap for each pool in the path
    /// @return initializedTicksCrossedList List of the initialized ticks that the swap crossed for each pool in the path
    /// @return gasEstimate The estimate of the gas that the swap consumes
    function getAmountIn(
        bytes memory path,
        uint256 amountOut
    )
        external
        returns (
            uint256 amountIn,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        )
    {
        return quoter.quoteExactOutput(path, amountOut);
    }

    function _checkUpdateAllowance(
        address token,
        address spender,
        uint256 amount
    ) internal {
        if (IERC20(token).allowance(address(this), spender) < amount) {
            IERC20(token).forceApprove(spender, type(uint256).max);
        }
    }

    function _validateTradeTokens(
        address traderWallet,
        address tokenIn,
        address tokenOut
    ) internal view returns (bool) {
        if (
            ITraderWallet(traderWallet).isAllowedTradeToken(tokenIn) &&
            ITraderWallet(traderWallet).isAllowedTradeToken(tokenOut)
        ) {
            return true;
        }
        return false;
    }

    /// @notice Sets new slippage allowance value for scaling operations
    /// @param _slippage Slippage value represented in wei (1e17 means 10% slippage allowance)
    function setSlippageAllowance(uint256 _slippage) public onlyOwner {
        if (
            _slippage < slippageAllowanceMin || _slippage > slippageAllowanceMax
        ) revert InvalidSlippage();

        emit SlippageAllowance(_slippage);
        slippage = _slippage;
    }
}

