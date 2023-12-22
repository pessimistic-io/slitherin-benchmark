pragma solidity ^0.8.0;

import "./IVault.sol";
import "./IFlashLoanRecipient.sol";
import "./IUniswapV2.sol";
import "./IUniswapV3.sol";
import "./ISushiswapV2.sol";
import {TransferHelper} from "./Interfaces.sol";

import "./console.sol";

contract Flashloan is IFlashLoanRecipient {
    IVault private constant vault =
        IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    // IUniswapV2Router02 private constant uniswapRouterV2 = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    // ISushiV2Router02 private constant sushiswapV2 = ISushiV2Router02(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);
    ISwapRouter private constant uniswapRouterV3 =
        ISwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    // address constant swapRouterAddressV2 = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    // address constant uniswapRouterV2 = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    // ISwapRouter private constant sushiSwapRouter = ISwapRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    address constant swapRouterAddressV2 =
        0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address constant sushiSwapRouterV2 =
        address(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    uint256 amount;
    bytes uniswav3Path;
    address[] uniswapv2Path;
    string side;

    function makeFlashLoan(
        address _assetToBorrow,
        uint256 _amountToBorrow,
        uint256 _amount,
        bytes memory _uniswap3Path,
        address[] memory _uniswapv2Path,
        string memory _side
    ) external {
        amount = _amount;
        uniswav3Path = _uniswap3Path;
        uniswapv2Path = _uniswapv2Path;
        side = _side;
        FlashLoanCall(_assetToBorrow, _amountToBorrow);
    }

    function FlashLoanCall(address asset, uint256 amount) internal {
        IFlashLoanRecipient receiverAddress = IFlashLoanRecipient(
            address(this)
        );

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(asset);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        // 0 = no debt, 1 = stable, 2 = variable
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        address onBehalfOf = address(this);
        bytes memory params = "";
        uint16 referralCode = 0;
        vault.flashLoan(receiverAddress, assets, amounts, params);
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        require(msg.sender == address(vault));
        if (
            keccak256(abi.encodePacked((side))) ==
            keccak256(abi.encodePacked(("uniswapv3")))
        ) {
            // Swap on Uniswapv2 First
            ISwapRouter routerv3 = ISwapRouter(swapRouterAddressV2);
            IUniswapV2Router02 routerv2 = IUniswapV2Router02(sushiSwapRouterV2);
            address usdt = uniswapv2Path[0];
            address usdc = uniswapv2Path[1];

            uint24 poolfee = 500;
            bytes memory _path = abi.encodePacked(usdc, poolfee, usdt);

            TransferHelper.safeApprove(usdc, swapRouterAddressV2, amount);
            TransferHelper.safeApprove(usdt, swapRouterAddressV2, amount);

            uint256 resultswap1 = routerv3.exactInput(
                ISwapRouter.ExactInputParams({
                    path: _path,
                    recipient: address(this),
                    amountIn: amount,
                    amountOutMinimum: 0
                })
            );

            console.log("V3");
            console.log(resultswap1);
            TransferHelper.safeApprove(usdc, sushiSwapRouterV2, amount);
            TransferHelper.safeApprove(usdt, sushiSwapRouterV2, amount);
            routerv2.swapExactTokensForTokens(
                resultswap1,
                0,
                uniswapv2Path,
                address(this),
                block.timestamp
            );
            console.log("IF Completed");
        } else {
            ISwapRouter routerv3 = ISwapRouter(swapRouterAddressV2);
            IUniswapV2Router02 routerv2 = IUniswapV2Router02(sushiSwapRouterV2);
            address usdt = uniswapv2Path[1];
            address usdc = uniswapv2Path[0];
            TransferHelper.safeApprove(usdc, swapRouterAddressV2, amount);
            TransferHelper.safeApprove(usdt, swapRouterAddressV2, amount);
            TransferHelper.safeApprove(usdc, sushiSwapRouterV2, amount);
            TransferHelper.safeApprove(usdt, sushiSwapRouterV2, amount);
            uint[] memory resultswap1 = routerv2.swapExactTokensForTokens(
                amount,
                0,
                uniswapv2Path,
                address(this),
                block.timestamp
            );
            console.log("Else");
            console.log(resultswap1[0]);
            console.log(resultswap1[1]);

            uint resultswap2 = routerv3.exactInput(
                ISwapRouter.ExactInputParams({
                    path: uniswav3Path,
                    recipient: address(this),
                    amountIn: resultswap1[0],
                    amountOutMinimum: 0
                })
            );
            console.log("V3");
            console.log(resultswap2);
        }
        for (uint i = 0; i < tokens.length; i++) {
            uint256 amountOwing = amounts[i];
            TransferHelper.safeTransfer(
                address(tokens[i]),
                msg.sender,
                amountOwing
            );
        }
    }
}

