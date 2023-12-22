// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "./ERC20_IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { Address } from "./Address.sol";

import { IOneInchRouterV5 } from "./IOneInchRouterV5.sol";
import { Access } from "./Access.sol";

abstract contract Aggregator is Access {
    using SafeERC20 for IERC20;
    using Address for address;

    error InvalidRecipient();

    struct OneInchData {
        address token;
        bytes data;
    }

    address public oneInchRouter = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    event OneInchRouterChanged(address indexed caller, address oldRouter, address newRouter);

    function setOneInchRouter(address _router) external onlyRole(ADMIN_ROLE) {
        address oldRouter = oneInchRouter;
        oneInchRouter = _router;
        emit OneInchRouterChanged(msg.sender, oldRouter, _router);
    }

    function approveToken(address _token, uint256 _allowance) external onlyRole(ADMIN_ROLE) {
        _approveToken(_token, oneInchRouter, _allowance);
    }

    function _approveToken(address _token, address _spender, uint256 _allowance) internal {
        IERC20(_token).approve(_spender, _allowance);
    }

    function _1inchSwap(bytes calldata _data) internal virtual {
        bytes4 selector = bytes4(_data[:4]);

        if (selector == IOneInchRouterV5.swap.selector) {
            (, IOneInchRouterV5.SwapDescription memory desc, , ) = abi.decode(
                _data[4:],
                (address, IOneInchRouterV5.SwapDescription, bytes, bytes)
            );
            _checkRecipient(desc.dstReceiver);
        } else if (selector == IOneInchRouterV5.uniswapV3SwapTo.selector) {
            (address _recipient, , , ) = abi.decode(_data[4:], (address, uint256, uint256, uint256[]));
            _checkRecipient(_recipient);
        } else if (selector == IOneInchRouterV5.unoswapTo.selector) {
            (address _recipient, , , , ) = abi.decode(_data[4:], (address, address, uint256, uint256, uint256[]));
            _checkRecipient(_recipient);
        } else if (selector == IOneInchRouterV5.fillOrderTo.selector) {
            (, , , , , , address _recipient) = abi.decode(
                _data[4:],
                (IOneInchRouterV5.Order, bytes, bytes, uint256, uint256, uint256, address)
            );
            _checkRecipient(_recipient);
        } else if (selector == IOneInchRouterV5.fillOrderRFQTo.selector) {
            (, , , address _recipient) = abi.decode(_data[4:], (IOneInchRouterV5.OrderRFQ, bytes, uint256, address));
            _checkRecipient(_recipient);
        } else if (selector == IOneInchRouterV5.clipperSwapTo.selector) {
            (, address _recipient, , , , , , , ) = abi.decode(
                _data[4:],
                (address, address, address, address, uint256, uint256, uint256, bytes32, bytes32)
            );
            _checkRecipient(_recipient);
        }
        oneInchRouter.functionCall(_data);
    }

    function _checkRecipient(address _recipient) internal view {
        if (_recipient != address(this)) {
            revert InvalidRecipient();
        }
    }
}

