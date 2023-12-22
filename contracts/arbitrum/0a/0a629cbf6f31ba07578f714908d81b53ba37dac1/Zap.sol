// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "./IERC20.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Babylonian.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router02.sol";
import "./IWETH.sol";
import "./IVault.sol";
import "./IZap.sol";

contract Zap is IZap {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address immutable WETH;
    address immutable router;

    constructor(address _WETH, address _router) public {
        WETH = _WETH;
        router = _router;
    }

    receive() external payable {
        assert(msg.sender == WETH);
    }

    function zapInSingle(
        address vault,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin
    ) external payable override {
        require(vault != address(0), "Zero Address");
        address _WETH = WETH;
        _pullToken(tokenIn, amountIn, _WETH);
        (uint256 lpAmount, address token0,uint256 amount0,address token1, uint256 amount1) = _performZapIn(
            vault,
            tokenIn,
            amountIn,
            amountOutMin,
            _WETH
        );
        Deposited(msg.sender, vault, token0,amount0, token1,amount1, lpAmount);
    }

    function zapInDual(
        address vault,
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1
    ) external payable override {
        require(vault != address(0), "Zero Address");
        address _WETH = WETH;
        _pullToken(token0, amount0, _WETH);
        _pullToken(token1, amount1, _WETH);
        (
            uint256 lpAmount,
            uint256 amountA,
            uint256 amountB
        ) = _performZapInDual(vault, token0, amount0, token1, amount1, _WETH);
        Deposited(msg.sender, vault,token0, amountA,token1,amountB,lpAmount);
    }

    function zapOut(address vault, uint256 amount) external override {
        require(vault != address(0), "Zero Address");
        require(amount > 0, "Zero Amount");
        (uint256 amount0, uint256 amount1) = _performZapOut(
            vault,
            amount,
            msg.sender
        );
        Withdrawn(msg.sender, vault, amount0, amount1);
    }

    function zapOutAndSwap(
        address vault,
        uint256 amount,
        address desiredToken,
        uint256 desiredTokenOutMin
    ) external override {
        require(
            vault != address(0) && desiredToken != address(0),
            "Zero Address"
        );
        require(amount > 0 && desiredTokenOutMin > 0, "Zero Amount");
        address _WETH = WETH;
        (uint256 amount0, uint256 amount1) = _performZapOut(
            vault,
            amount,
            address(this)
        );
        _performSwap(
            IVault(vault).asset(),
            desiredToken,
            desiredTokenOutMin,
            _WETH
        );
        Withdrawn(msg.sender, vault, amount0, amount1);
    }

    function _performZapIn(
        address vault,
        address tokenIn,
        uint256 amount,
        uint256 amountOutMin,
        address _WETH
    ) internal returns (uint256 lpAmount,address, uint256 amount0,address, uint256 amount1) {
        (
            address pair,
            address[] memory path,
            uint256 amountToSwap
        ) = _generateZapInObject(vault, tokenIn, amount);

        uint256[] memory swapedAmounts = _swap(
            amountToSwap,
            amountOutMin,
            path
        );
        (lpAmount, amount0, amount1) = _addLiquidity(
            tokenIn,
            path[1],
            amount - swapedAmounts[0],
            swapedAmounts[1]
        );
        _approveToken(pair, vault);
        IVault(vault).deposit(lpAmount, msg.sender);
        _returnAssets([tokenIn, path[1]], _WETH);
        return(lpAmount,tokenIn,amount0,path[1],amount1);
    }

    function _performZapInDual(
        address vault,
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1,
        address _WETH
    ) internal returns (uint256 lpAmount, uint256 amountA, uint256 amountB) {
        (lpAmount, amountA, amountB) = _addLiquidity(
            token0,
            token1,
            amount0,
            amount1
        );
        _approveToken(IVault(vault).asset(), vault);
        IVault(vault).deposit(lpAmount, msg.sender);
        _returnAssets([token0, token1], _WETH);
    }

    function _performSwap(
        address pair,
        address desiredToken,
        uint256 desiredTokenOutMin,
        address _WETH
    ) internal {
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        address swapToken = token1 == desiredToken ? token0 : token1;
        uint256 amount = IERC20(swapToken).balanceOf(address(this));
        address[] memory path = new address[](2);
        path[0] = swapToken;
        path[1] = desiredToken;
        _swap(amount, desiredTokenOutMin, path);
        _returnAssets([token0, token1], _WETH);
    }

    function _performZapOut(
        address vault,
        uint256 amount,
        address to
    ) internal returns (uint256 amount0, uint256 amount1) {
        address pair = IVault(vault).asset();
        IERC20(vault).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(pair).safeTransfer(
            pair,
            IVault(vault).withdraw(amount, address(this))
        );
        (amount0, amount1) = IUniswapV2Pair(pair).burn(to);
    }

    function _generateZapInObject(
        address vault,
        address tokenIn,
        uint256 amount
    )
        internal
        view
        returns (address pair, address[] memory, uint256 amountToSwap)
    {
        address[] memory path = new address[](2);
        pair = IVault(vault).asset();
        (uint112 res0, uint112 res1, ) = IUniswapV2Pair(pair).getReserves();
        bool isInputA = IUniswapV2Pair(pair).token0() == tokenIn;
        amountToSwap = isInputA
            ? _calculateSwapInAmount(res0, amount)
            : _calculateSwapInAmount(res1, amount);
        path[0] = tokenIn;
        path[1] = isInputA
            ? IUniswapV2Pair(pair).token1()
            : IUniswapV2Pair(pair).token0();
        return (pair, path, amountToSwap);
    }

    function _swap(
        uint256 amountToSwap,
        uint256 amountOutMin,
        address[] memory path
    ) internal returns (uint256[] memory swapedAmounts) {
        address _router = router;
        _approveToken(path[0], _router);
        (swapedAmounts) = IUniswapV2Router02(_router).swapExactTokensForTokens(
            amountToSwap,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );
    }

    function _addLiquidity(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 lpAmount, uint256, uint256) {
        address _router = router;
        _approveToken(token0, _router);
        _approveToken(token1, _router);
        (amount0, amount1, lpAmount) = IUniswapV2Router02(_router).addLiquidity(
            token0,
            token1,
            amount0,
            amount1,
            (amount0 * 100) / 10_000,
            (amount1 * 100) / 10_000,
            address(this),
            block.timestamp
        );
        return (lpAmount, amount0, amount1);
    }

    function _pullToken(address token, uint256 amount, address _WETH) internal {
        require(token != address(0), "Zero Address");
        require(amount > 0, "Zero Amount");
        if (token == _WETH) {
            IWETH(_WETH).deposit{value: amount}();
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    function _approveToken(address token, address to) internal {
        if (IERC20(token).allowance(address(this), to) == 0)
            IERC20(token).safeApprove(to, uint256(type(uint256).max));
    }

    function _returnAssets(address[2] memory tokens, address _WETH) internal {
        uint256 balance;
        for (uint256 i; i < tokens.length; ++i) {
            balance = IERC20(tokens[i]).balanceOf(address(this));
            if (balance > 0) {
                if (tokens[i] == _WETH) {
                    IWETH(_WETH).withdraw(balance);
                    (bool success, ) = payable(msg.sender).call{value: balance}(
                        ""
                    );
                    require(success, "Transfer Failed");
                } else {
                    IERC20(tokens[i]).safeTransfer(msg.sender, balance);
                }
            }
        }
    }

    function _calculateSwapInAmount(
        uint256 reserveIn,
        uint256 userIn
    ) private pure returns (uint256) {
        return
            Babylonian
                .sqrt(
                    reserveIn.mul(userIn.mul(3988000) + reserveIn.mul(3988009))
                )
                .sub(reserveIn.mul(1997)) / 1994;
    }
}

