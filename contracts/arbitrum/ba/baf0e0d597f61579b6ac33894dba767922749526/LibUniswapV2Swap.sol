// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import {IWETH} from "./IWETH.sol";
import {NATIVE_TOKEN} from "./CTokens.sol";
import {LibExecAccess} from "./LibExecAccess.sol";
import {IUniswapV2Router02} from "./IUniswapV2Router02.sol";
import {IJoeRouter02} from "./IJoeRouter02.sol";
import {GelatoString} from "./GelatoString.sol";
import {IERC20, SafeERC20} from "./SafeERC20.sol";

library LibUniswapV2Swap {
    struct UniswapV2SwapStorage {
        address routerAddress;
        //bool shouldSwapRevertOnFailure;
    }

    bytes32 private constant _UNISWAPV2SWAP_STORAGE_POSITION =
        keccak256("gelato.diamond.uniswapv2swap.storage");

    function setRouterAddress(address _newRouterAddress) internal {
        uniswapV2SwapStorage().routerAddress = _newRouterAddress;
    }

    /*function setShouldSwapRevertOnFailure(bool _shouldSwapRevertOnFailure)
        internal
    {
        uniswapV2SwapStorage()
            .shouldSwapRevertOnFailure = _shouldSwapRevertOnFailure;
    }*/

    // solhint-disable-next-line function-max-lines, code-complexity
    function uniswapV2TokenForETH(
        address inputToken,
        uint256 inputAmount,
        uint256 minReturn,
        address receiver,
        bool _shouldSwapRevertOnFailure
    ) internal returns (uint256 bought) {
        bool isAVAX = isAvalanche();

        address routerAddress_ = routerAddress();

        if (isAVAX) {
            IJoeRouter02 traderJoeRouter = IJoeRouter02(routerAddress_);

            SafeERC20.safeIncreaseAllowance(
                IERC20(inputToken),
                routerAddress_,
                inputAmount
            );

            address wavax = traderJoeRouter.WAVAX();
            address[] memory path = new address[](2);
            path[0] = inputToken;
            path[1] = wavax;

            try
                traderJoeRouter.swapExactTokensForAVAX(
                    inputAmount,
                    minReturn,
                    path,
                    receiver,
                    block.timestamp + 1 // solhint-disable-line not-rely-on-time
                )
            returns (uint256[] memory amounts) {
                bought = amounts[amounts.length - 1];
            } catch Error(string memory error) {
                if (_shouldSwapRevertOnFailure)
                    GelatoString.revertWithInfo(
                        error,
                        "swapExactTokensForAVAX"
                    );
            } catch {
                if (_shouldSwapRevertOnFailure)
                    revert("swapExactTokensForAVAX:undefined");
            }
        } else {
            IUniswapV2Router02 uniswapV2Router = IUniswapV2Router02(
                routerAddress_
            );

            SafeERC20.safeIncreaseAllowance(
                IERC20(inputToken),
                routerAddress_,
                inputAmount
            );

            address weth = uniswapV2Router.WETH();
            address[] memory path = new address[](2);
            path[0] = inputToken;
            path[1] = weth;

            try
                uniswapV2Router.swapExactTokensForETH(
                    inputAmount,
                    minReturn,
                    path,
                    receiver,
                    block.timestamp + 1 // solhint-disable-line not-rely-on-time
                )
            returns (uint256[] memory amounts) {
                bought = amounts[amounts.length - 1];
            } catch Error(string memory error) {
                if (_shouldSwapRevertOnFailure)
                    GelatoString.revertWithInfo(error, "swapExactTokensForETH");
            } catch {
                if (_shouldSwapRevertOnFailure)
                    revert("swapExactTokensForETH:undefined");
            }
        }
    }

    // solhint-disable-next-line function-max-lines, code-complexity
    function uniswapV2TokenForToken(
        address inputToken,
        uint256 inputAmount,
        address outputToken,
        uint256 minReturn,
        address receiver,
        bool _shouldSwapRevertOnFailure
    ) internal returns (uint256 bought) {
        address routerAddress_ = routerAddress();
        // Works for both UniswapV2Router and TraderJoeRouter
        IUniswapV2Router02 uniswapV2Router = IUniswapV2Router02(routerAddress_);
        SafeERC20.safeIncreaseAllowance(
            IERC20(inputToken),
            routerAddress_,
            inputAmount
        );

        address[] memory path = new address[](2);
        path[0] = inputToken;
        path[1] = outputToken;

        try
            uniswapV2Router.swapExactTokensForTokens(
                inputAmount,
                minReturn,
                path,
                receiver,
                block.timestamp + 1 // solhint-disable-line not-rely-on-time
            )
        returns (uint256[] memory amounts) {
            bought = amounts[amounts.length - 1];
        } catch Error(string memory error) {
            if (_shouldSwapRevertOnFailure)
                GelatoString.revertWithInfo(error, "swapExactTokensForTokens");
        } catch {
            if (_shouldSwapRevertOnFailure)
                revert("swapExactTokensForTokens:undefined");
        }
    }

    /*// solhint-disable-next-line function-max-lines, code-complexity
    function simulateAndExecFeeSwap(
        address _routerAddress,
        address _creditToken,
        uint256 _credit,
        address _executor
    )
        internal
        returns (
            bool,
            address,
            uint256 paymentAmount
        )
    {
        if (_credit == 0) return (false, address(0), 0);

        if (_creditToken == NATIVE_TOKEN) {
            (bool success, ) = _executor.call{value: _credit}("");
            return (success, NATIVE_TOKEN, success ? _credit : 0);
        }

        address wnative = getWrappedNativeToken(_routerAddress);

        if (_creditToken == wnative) {
            IWETH(wnative).withdraw(_credit);
            (bool success, ) = _executor.call{value: _credit}("");
            return (success, NATIVE_TOKEN, success ? _credit : 0);
        }

        address[] memory creditTokens_ = LibExecAccess.creditTokens();

        for (uint256 i; i < creditTokens_.length; i++) {
            if (creditTokens_[i] == _creditToken) {
                return (true, _creditToken, _credit);
            }
        }

        address[] memory path = new address[](2);
        path[0] = _creditToken;
        uint256 creditOut;

        path[1] = wnative;

        creditOut = getAmountOut(_routerAddress, _credit, path);

        bool shouldSwapRevertOnFailure_ = shouldSwapRevertOnFailure();

        if (creditOut > 0) {
            paymentAmount = uniswapV2TokenForETH(
                _creditToken,
                _credit,
                0,
                _executor,
                shouldSwapRevertOnFailure_
            );
            return (paymentAmount > 0, NATIVE_TOKEN, paymentAmount);
        }

        for (uint256 i; i < creditTokens_.length; i++) {
            path[1] = creditTokens_[i];

            creditOut = getAmountOut(_routerAddress, _credit, path);

            if (creditOut > 0) {
                paymentAmount = uniswapV2TokenForToken(
                    _creditToken,
                    _credit,
                    path[1],
                    0,
                    address(this), // non-native token payments are kept in the Diamond
                    shouldSwapRevertOnFailure_
                );
                return (paymentAmount > 0, path[1], paymentAmount);
            }
        }

        return (false, address(0), 0);
    }*/

    function isAvalanche() internal view returns (bool isAVAX) {
        uint256 chainId;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            chainId := chainid()
        }

        isAVAX = chainId == 43114;
    }

    function getWrappedNativeToken(address _routerAddress)
        internal
        view
        returns (address wnative)
    {
        wnative = isAvalanche()
            ? IJoeRouter02(_routerAddress).WAVAX()
            : IUniswapV2Router02(_routerAddress).WETH();
    }

    function getAmountOut(
        address _routerAddress,
        uint256 _inputAmount,
        address[] memory _path
    ) internal view returns (uint256 amount) {
        // Works for both UniswapV2Router and TraderJoeRouter
        try
            IUniswapV2Router02(_routerAddress).getAmountsOut(
                _inputAmount,
                _path
            )
        returns (uint256[] memory amounts) {
            amount = amounts[amounts.length - 1];
        } catch {} //solhint-disable-line no-empty-blocks
    }

    function routerAddress() internal view returns (address) {
        return uniswapV2SwapStorage().routerAddress;
    }

    /*function shouldSwapRevertOnFailure() internal view returns (bool) {
        return uniswapV2SwapStorage().shouldSwapRevertOnFailure;
    }*/

    function uniswapV2SwapStorage()
        internal
        pure
        returns (UniswapV2SwapStorage storage univ2swapstorage)
    {
        bytes32 position = _UNISWAPV2SWAP_STORAGE_POSITION;
        assembly {
            univ2swapstorage.slot := position
        }
    }
}

