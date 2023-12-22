// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";

import "./IWETH.sol";
import "./ISwapRouter.sol";
import "./IUniswapV2Factory.sol";
import "./IBalancerV2Vault.sol";
import "./Multicall.sol";
// TODO
// import '../libraries/BytesLib.sol';
import "./TOKordinatorLibrary.sol";
import "./TransferHelper.sol";

// TOKordinator
/// @title TokenStand Coordinator - Fantastic coordinator for swapping
/// @author Anh Dao Tuan <anh.dao@sotatek.com>

// DEXes supported on Arbitrum:
//      1. Uniswap V3
//      2. Sushiswap
//      3. Balancer V2

contract TOKordinatorV2ARBI is Ownable, ReentrancyGuard, Multicall {
    using SafeMath for uint256;
    using UniswapV2Library for IUniswapV2Pair;
    // using BytesLib for bytes;
    using TOKordinatorLibrary for address;

    IWETH internal weth = IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    // IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    // UniswapV3
    ISwapRouter internal swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    // ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IUniswapV2Factory internal sushiswap = IUniswapV2Factory(0xc35DADB65012eC5796536bD9864eD8773aBc74C4);
    // IUniswapV2Factory(0xc35DADB65012eC5796536bD9864eD8773aBc74C4);
    IBalancerV2Vault internal balancer = IBalancerV2Vault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    // IBalancerV2Vault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    event SwappedOnTheOther(
        IERC20 indexed fromToken,
        IERC20 indexed destToken,
        uint256 fromTokenAmount,
        uint256 destTokenAmount,
        uint256 minReturn,
        uint256[] distribution
    );
    event SwappedOnUniswapV3(
        IERC20 indexed fromToken,
        IERC20 indexed toToken,
        uint256 fromTokenAmount,
        uint256 destTokenAmount,
        uint256 minReturn
    );
    event SingleSwappedOnBalancerV2(
        IERC20 indexed fromToken,
        IERC20 indexed toToken,
        uint256 fromTokenAmount,
        uint256 destTokenAmount,
        uint256 minReturn
    );
    event BatchSwappedOnBalancerV2(
        IERC20 indexed fromToken,
        IERC20 indexed toToken,
        uint256 fromTokenAmount,
        uint256 destTokenAmount
    );

    // Number of DEX base on Uniswap V2
    uint256 internal constant DEXES_COUNT = 1;

    constructor(
    ) public {
    }

    receive() external payable {}

    function swapOnTheOther(
        IERC20[][] calldata path,
        uint256 amount,
        uint256 minReturn,
        uint256[] memory distribution
    ) public payable nonReentrant returns (uint256 returnAmount) {
        function(IERC20[] calldata, uint256)[DEXES_COUNT] memory reserves = [
            _swapOnSushiswap
            // _swapOnBalancerV2,
        ];

        require(
            distribution.length <= reserves.length,
            'TOKordinator: distribution array should not exceed reserves array size.'
        );

        uint256 parts = 0;
        uint256 lastNonZeroIndex = 0;
        for (uint256 i = 0; i < distribution.length; i++) {
            if (distribution[i] > 0) {
                parts = parts.add(distribution[i]);
                lastNonZeroIndex = i;
            }
        }

        IERC20 fromToken = IERC20(path[lastNonZeroIndex][0]);
        IERC20 destToken = IERC20(path[lastNonZeroIndex][path[lastNonZeroIndex].length - 1]);

        if (parts == 0) {
            if (address(fromToken) == address(0)) {
                (bool success, ) = msg.sender.call{value: msg.value}('');
                require(success, 'TOKordinator: transfer failed');
                return msg.value;
            }
            return amount;
        }

        if (address(fromToken) != address(0)) {
            TransferHelper.safeTransferFrom(address(fromToken), msg.sender, address(this), amount);
        }

        uint256 remainingAmount = address(fromToken) == address(0)
            ? address(this).balance
            : fromToken.balanceOf(address(this));

        for (uint256 i = 0; i < distribution.length; i++) {
            if (distribution[i] == 0) {
                continue;
            }

            uint256 swapAmount = amount.mul(distribution[i]).div(parts);
            if (i == lastNonZeroIndex) {
                swapAmount = remainingAmount;
            }
            remainingAmount -= swapAmount;
            reserves[i](path[i], swapAmount);
        }

        returnAmount = address(destToken) == address(0) ? address(this).balance : destToken.balanceOf(address(this));
        require(returnAmount >= minReturn, 'TOKordinator: return amount was not enough');

        if (address(destToken) == address(0)) {
            (bool success, ) = msg.sender.call{value: returnAmount}('');
            require(success, 'TOKordinator: transfer failed');
        } else {
            TransferHelper.safeTransfer(address(destToken), msg.sender, returnAmount);
        }

        // uint256 remainingFromToken = address(fromToken) == address(0)
        //     ? address(this).balance
        //     : fromToken.balanceOf(address(this));
        // if (remainingFromToken > 0) {
        //     if (address(fromToken) == address(0)) {
        //         msg.sender.transfer(remainingFromToken);
        //     } else {
        //         fromToken.safeTransfer(msg.sender, remainingFromToken);
        //     }
        // }

        emit SwappedOnTheOther(fromToken, destToken, amount, returnAmount, minReturn, distribution);
    }

    function getSushiswapAmountsOut(uint256 amountIn, IERC20[] memory path) public view returns (uint256[] memory) {
        IERC20[] memory realPath = formatPath(path);
        return UniswapV2Library.getAmountsOut(sushiswap, amountIn, realPath);
    }

    function formatPath(IERC20[] memory path) public view returns (IERC20[] memory realPath) {
        realPath = new IERC20[](path.length);

        for (uint256 i; i < path.length; i++) {
            if (address(path[i]) == address(0)) {
                realPath[i] = weth;
                continue;
            }
            realPath[i] = path[i];
        }
    }

    function _swapOnSushiswap(IERC20[] calldata path, uint256 amount) internal {
        IERC20[] memory realPath = formatPath(path);

        IUniswapV2Pair pair = sushiswap.getPair(realPath[0], realPath[1]);
        uint256[] memory amounts = UniswapV2Library.getAmountsOut(sushiswap, amount, realPath);

        if (address(path[0]) == address(0)) {
            weth.deposit{value: amounts[0]}();
            assert(weth.transfer(address(pair), amounts[0]));
        } else {
            TransferHelper.safeTransfer(address(path[0]), address(pair), amounts[0]);
        }

        for (uint256 i; i < realPath.length - 1; i++) {
            (address input, address output) = (address(realPath[i]), address(realPath[i + 1]));
            (address token0, ) = TOKordinatorLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < realPath.length - 2
                ? address(sushiswap.getPair(IERC20(output), realPath[i + 2]))
                : address(this);
            sushiswap.getPair(IERC20(input), IERC20(output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }

        if (address(path[path.length - 1]) == address(0)) {
            weth.withdraw(weth.balanceOf(address(this)));
        }
    }

    function swapOnUniswapV3(
        IERC20 tokenIn,
        IERC20 tokenOut,
        bytes memory path,
        uint256 deadline,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) public payable nonReentrant returns (uint256 returnAmount) {
        if (address(tokenIn) == address(0)) {
            require(msg.value >= amountIn, 'TOKordinator: value does not enough');
        }

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams(
            path,
            address(this),
            deadline,
            amountIn,
            amountOutMinimum
        );

        if (address(tokenIn) == address(0)) {
            returnAmount = swapRouter.exactInput{value: amountIn}(params);
            swapRouter.refundETH();
        } else {
            TransferHelper.safeTransferFrom(address(tokenIn), msg.sender, address(this), amountIn);
            TransferHelper.safeApprove(address(tokenIn), address(swapRouter), amountIn);

            returnAmount = swapRouter.exactInput(params);
        }

        if (address(tokenOut) == address(0)) {
            weth.withdraw(returnAmount);
            (bool success, ) = msg.sender.call{value: returnAmount}('');
            require(success, 'TOKordinator: transfer failed');
        } else {
            TransferHelper.safeTransfer(address(tokenOut), msg.sender, returnAmount);
        }

        emit SwappedOnUniswapV3(tokenIn, tokenOut, amountIn, returnAmount, amountOutMinimum);
    }

    function singleSwapOnBalancerV2(
        bytes32 poolId,
        IAsset assetIn,
        IAsset assetOut,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint256 deadline
    ) public payable nonReentrant returns (uint256 returnAmount) {
        if (address(assetIn) == address(0)) {
            require(msg.value >= amountIn, 'TOKordinator: value does not enough');
        }

        IBalancerV2Vault.SingleSwap memory singleSwap = IBalancerV2Vault.SingleSwap(
            poolId,
            IBalancerV2Vault.SwapKind.GIVEN_IN,
            assetIn,
            assetOut,
            amountIn,
            '0x'
        );

        IBalancerV2Vault.FundManagement memory funds = IBalancerV2Vault.FundManagement(
            address(this),
            false,
            address(this),
            false
        );

        if (address(assetIn) == address(0)) {
            returnAmount = balancer.swap{value: amountIn}(
                singleSwap,
                funds,
                amountOutMinimum,
                deadline
            );
        } else {
            TransferHelper.safeTransferFrom(address(singleSwap.assetIn), msg.sender, address(this), amountIn);
            TransferHelper.safeApprove(address(assetIn), address(balancer), amountIn);
            returnAmount = balancer.swap(
                singleSwap,
                funds,
                amountOutMinimum,
                deadline
            );
        }

        require(returnAmount >= amountOutMinimum, "TOKordinator: return amount was not enough");
        if (address(assetOut) == address(0)) {
            (bool success, ) = msg.sender.call{value: returnAmount}('');
            require(success, 'TOKordinator: transfer failed');
        } else {
            TransferHelper.safeTransfer(address(assetOut), msg.sender, returnAmount);
        }

        emit SingleSwappedOnBalancerV2(IERC20(address(assetIn)), IERC20(address(assetOut)), amountIn, returnAmount, amountOutMinimum);
    }

    function batchSwapOnBalancerV2(
        IERC20 tokenIn,
        IERC20 tokenOut,
        IBalancerV2Vault.BatchSwapStep[] memory swaps,
        IAsset[] memory assets,
        int256[] memory limits,
        uint256 amountOutMinimum,
        uint256 deadline
    ) public payable nonReentrant returns (uint256 returnAmount) {
        uint256 amountIn = swaps[0].amount;
        int256[] memory returnAmounts;
        if (address(tokenIn) == address(0)) {
            require(msg.value >= amountIn, 'TOKordinator: value does not enough');
        }

        IBalancerV2Vault.FundManagement memory funds = IBalancerV2Vault.FundManagement(
            address(this),
            false,
            address(this),
            false
        );

        if (address(tokenIn) == address(0)) {
            returnAmounts = balancer.batchSwap{value: amountIn}(
                IBalancerV2Vault.SwapKind.GIVEN_IN,
                swaps,
                assets,
                funds,
                limits,
                deadline
            );
        } else {
            TransferHelper.safeTransferFrom(address(tokenIn), msg.sender, address(this), amountIn);
            TransferHelper.safeApprove(address(tokenIn), address(balancer), amountIn);

            returnAmounts = balancer.batchSwap(
                IBalancerV2Vault.SwapKind.GIVEN_IN,
                swaps,
                assets,
                funds,
                limits,
                deadline
            );
        }

        if (returnAmounts[returnAmounts.length - 1] < 0) {
          returnAmount = uint256(returnAmounts[returnAmounts.length - 1] * -1);
        } else {
          returnAmount = uint256(returnAmounts[returnAmounts.length - 1]);
        }

        require(returnAmount >= amountOutMinimum, "TOKordinator: return amount was not enough");
        if (address(tokenOut) == address(0)) {
            (bool success, ) = msg.sender.call{value: returnAmount}('');
            require(success, 'TOKordinator: transfer failed');
        } else {
            TransferHelper.safeTransfer(address(tokenOut), msg.sender, returnAmount);
        }

        emit BatchSwappedOnBalancerV2(tokenIn, tokenOut, amountIn, returnAmount);
    }

    // emergency case
    function rescueFund(IERC20 token) public onlyOwner {
        if (address(token) == address(0)) {
            (bool success, ) = msg.sender.call{value: address(this).balance}('');
            require(success, 'TOKordinator: fail to rescue Ether');
        } else {
            TransferHelper.safeTransfer(address(token), msg.sender, token.balanceOf(address(this)));
        }
    }
}

