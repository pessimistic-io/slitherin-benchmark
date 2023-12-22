// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {AccessControl} from "./AccessControl.sol";
import {IUniswapV3Router, ExactInputSingleParams, ExactInputParams} from "./IUniswapRouter.sol";
import {     SwapOperation,     SwapProtocol,     InToken,     InInformation,     OutInformation,     InteractionOperation,     Operation,     InteractionOperation } from "./structs.sol";

abstract contract SwapHelper is AccessControl {
    address constant nativeToken = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    using SafeERC20 for IERC20;

    // Mapping of router type to router address
    mapping(SwapProtocol => address) swapRouters;

    /// ============ MODIFIERS ============

    modifier onlyOwner() {
        _checkRole(DEFAULT_ADMIN_ROLE);
        _;
    }

    /// ============ Errors ============
    error FeeToHigh();
    error OnlyOneOperationTypePer();
    error AtLeastOneOperationTypePer();
    error ProtocolNotSupported();
    error TokenSwapFailed();
    error TokenNotContract();
    error TransferFromFailed();

    /// ============ Admin Functions ============

    function removeTokens(address _to, address _token, bool _native) external onlyOwner {
        if (_native) {
            payable(_to).transfer(address(this).balance);
        } else {
            _safeTransferFrom(_token, address(this), _to, IERC20(_token).balanceOf(address(this)));
        }
    }

    function registerSwaps(SwapProtocol[] calldata _swapProtocols, address[] calldata _routers) external onlyOwner {
        uint256 n = _swapProtocols.length;
        for (uint256 i; i < n; ++i) {
            swapRouters[_swapProtocols[i]] = _routers[i];
        }
    }

    function _registerSwaps(SwapProtocol[] memory _swapProtocols, address[] memory _routers) internal {
        uint256 n = _swapProtocols.length;
        for (uint256 i; i < n; ++i) {
            swapRouters[_swapProtocols[i]] = _routers[i];
        }
    }

    /// ============ Internal Functions ============

    function _transferFromContract(address token, address to, uint256 amount) internal {
        // 1.a
        if (amount == 0) {
            return;
        }
        if (to == address(0)) {
            to = msg.sender;
        }
        if (token != nativeToken) {
            IERC20(token).safeTransfer(to, amount);
        } else {
            payable(to).transfer(amount);
        }
    }

    function _isSwapOperation(Operation memory operation) internal pure returns (bool isSwap) {
        if (operation.swap.length != 0 && operation.interaction.length != 0) revert OnlyOneOperationTypePer();
        if (operation.swap.length == 0 && operation.interaction.length == 0) revert AtLeastOneOperationTypePer();

        if (operation.swap.length != 0) {
            return true;
        } else {
            return false;
        }
    }

    function _swapWithCalldata(SwapOperation memory _swap, uint256 amount)
        internal
        returns (bool success, uint256 swapAmount)
    {
        uint256 value;
        if (_swap.inToken == nativeToken) {
            value = amount;
        }
        bytes memory returnBytes;
        (success, returnBytes) = swapRouters[_swap.protocol].call{value: value}(_swap.args);
        swapAmount = abi.decode(returnBytes, (uint256));
    }

    function _swapUniswapV3(SwapOperation memory _swap, uint256 amount)
        internal
        returns (bool success, uint256 swapAmount)
    {
        ExactInputSingleParams memory params = ExactInputSingleParams({
            tokenIn: _swap.inToken,
            tokenOut: _swap.outToken,
            fee: abi.decode(_swap.args, (uint24)),
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amount,
            amountOutMinimum: _swap.minOutAmount,
            sqrtPriceLimitX96: 0
        });

        uint256 value;
        if (_swap.inToken == nativeToken) {
            value = amount;
        }

        swapAmount = IUniswapV3Router(swapRouters[SwapProtocol.UniswapV3]).exactInputSingle{value: value}(params);

        success = true;
    }

    function swap(SwapOperation memory _swap, uint256 amount) internal returns (uint256 returnAmount) {
        bool success = true;
        address routerAddress = swapRouters[_swap.protocol];
        // If we have an ERC20 Token, we need to approve the contract that will execute the swap

        // We approve for the max amount once
        // This is similar to :
        // (https://github.com/AngleProtocol/angle-core/blob/53c9d93eb1adf4fda4be8bd5b2ea09f237a6b408/contracts/router/AngleRouter.sol#L1364)
        _approveIfNecessary(routerAddress, _swap.inToken, amount);

        if (_swap.protocol == SwapProtocol.UniswapV3) {
            // UniswapV3 swap can be done at any time
            (success, returnAmount) = _swapUniswapV3(_swap, amount);
        } else if (_swap.protocol == SwapProtocol.OneInch || _swap.protocol == SwapProtocol.ZeroX) {
            // OneInch and ZeroX swaps work in the same way
            (success, returnAmount) = _swapWithCalldata(_swap, amount);
        } else if (_swap.protocol == SwapProtocol.None) {
            // We don't do any swap here, hence an empty body
        } else {
            revert ProtocolNotSupported();
        }

        if (!success) revert TokenSwapFailed();
    }

    function _approveIfNecessary(address contractAddress, address token, uint256 amountMinimum) internal {
        if (token != nativeToken) {
            uint256 currentApproval = IERC20(token).allowance(address(this), contractAddress);
            if (currentApproval == 0) {
                IERC20(token).safeApprove(contractAddress, type(uint256).max);
            } else if (currentApproval < amountMinimum) {
                IERC20(token).safeIncreaseAllowance(contractAddress, type(uint256).max - currentApproval);
            }
        }
    }

    /// @dev We choose to not user OZ interface for gas optimisation purposes
    /// @dev This router doesn't need to be safe on token transfers as its storage nevers depends on transfer parameters
    function _safeTransferFrom(address token, address from, address to, uint256 value) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }
}

