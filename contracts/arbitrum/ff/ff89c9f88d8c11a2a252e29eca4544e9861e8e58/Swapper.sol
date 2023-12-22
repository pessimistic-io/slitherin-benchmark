// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./OwnableUpgradeable.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Address.sol";
import "./IOracle.sol";
import "./ISwapper.sol";
import "./IAddressProvider.sol";
import "./ILendVault.sol";
import "./AccessControl.sol";

/**
 * @notice Swapper acts as a wrapper for interacting with a DEX
 */
contract Swapper is AccessControl, ISwapper {
    using SafeERC20 for IERC20;
    using Address for address;

    /// @notice Address of uniswap v2 like router used for swaps
    IUniswapV2Router02 public router;

    /**
     * @notice Initialize function used in place of constructor for updgradeable contract
     * @dev router.factory is called as input validation
     */
    function initialize(address _router, address _addressProvider) external initializer {
        __AccessControl_init(_addressProvider);
        router = IUniswapV2Router02(_router);
        router.factory();
    }

    /**
     * @notice Set router address
     */
    function setRouter(address _router) external restrictAccess(GOVERNOR) {
        router = IUniswapV2Router02(_router);
        router.factory();
    }

    /// @inheritdoc ISwapper
    function getETHValue(address token, uint amount) external view returns (uint value) {
        value = IOracle(provider.oracle()).getValueInTermsOf(token, amount, provider.networkToken());
    }

    /// @inheritdoc ISwapper
    function getETHValue(address[] memory tokens, uint[] memory amounts)
        public
        view
        returns (uint256 totalEthValue)
    {
        require(tokens.length == amounts.length, "Mismatched input arrays");

        for (uint256 i = 0; i < tokens.length; i++) {
            totalEthValue+=IOracle(provider.oracle()).getValueInTermsOf(tokens[i], amounts[i], provider.networkToken());
        }
    }

    /// @inheritdoc ISwapper
    function getAmountIn(address tokenIn, uint amountOut, address tokenOut) external view returns (uint amountIn) {
        if (tokenIn==tokenOut) return amountOut;
        if (amountOut>0) {
            amountIn = router.getAmountsIn(amountOut, _getPathForSwap(tokenIn, tokenOut))[0];
        }
    }

    /// @inheritdoc ISwapper
    function getAmountOut(address tokenIn, uint amountIn, address tokenOut) public view returns (uint amountOut) {
        if (tokenIn==tokenOut) return amountIn;
        if (amountIn>0) {
            amountOut = router.getAmountsOut(amountIn, _getPathForSwap(tokenIn, tokenOut))[1];
        }
    }

    /// @inheritdoc ISwapper
    function swapExactTokensForTokens(address tokenIn, uint amountIn, address tokenOut, uint slippage) external returns (uint amountOut){
        if (tokenIn==tokenOut) return amountIn;
        uint allowance = IERC20(tokenIn).allowance(address(this), address(router));
        if(allowance<amountIn) {
            IERC20(tokenIn).safeIncreaseAllowance(address(router), 2**256-1-allowance);
        }

        uint minOut = IOracle(provider.oracle()).getValueInTermsOf(tokenIn, amountIn, tokenOut)*(PRECISION-slippage)/PRECISION;
        uint expectedOut = getAmountOut(tokenIn, amountIn, tokenOut);
        if (expectedOut>0) {
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
            amountOut = router.swapExactTokensForTokens(
                amountIn,
                minOut,
                _getPathForSwap(tokenIn, tokenOut),
                msg.sender,
                block.timestamp
            )[1];
        }
    }

    /// @inheritdoc ISwapper
    function swapTokensForExactTokens(address tokenIn, uint amountOut, address tokenOut, uint slippage) external returns (uint amountIn) {
        if (tokenIn==tokenOut) return amountOut;
        uint maxIn = IOracle(provider.oracle()).getValueInTermsOf(tokenOut, amountOut, tokenIn)*PRECISION/(PRECISION-slippage) + 10;
        amountIn = router.getAmountsIn(amountOut, _getPathForSwap(tokenIn, tokenOut))[0];
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        uint allowance = IERC20(tokenIn).allowance(address(this), address(router));
        if(allowance<amountIn) {
            IERC20(tokenIn).safeIncreaseAllowance(address(router), 2**256-1-allowance);
        }
        router.swapTokensForExactTokens(amountOut, maxIn, _getPathForSwap(tokenIn, tokenOut), msg.sender, block.timestamp);
    }

    /**
     * @notice Internal helper function to get the token path needed for swapping with uniswap v2 router
     */
    function _getPathForSwap(address tokenIn, address tokenOut) internal pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        return path;
    }
}
