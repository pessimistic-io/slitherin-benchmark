//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "./IERC20.sol";
import "./SafeERC20.sol";

import "./SwapCalldataUtils.sol";
import "./BaseForwarder.sol";

contract ReceivingForwarder is BaseForwarder {
    using SwapCalldataUtils for bytes;
    using SafeERC20 for IERC20;

    function initialize() external initializer {
        __BaseForwarder_init();
    }

    function unwrapAndForward(
        address _wrappedToken,
        uint256 _minUnwrapAmount,
        address _router,
        bytes memory _routerCalldata,
        address _targetToken,
        address _fallbackAddress
    ) external {
        // grab tokens from the gate
        IERC20 wrappedToken = IERC20(_wrappedToken);
        wrappedToken.safeTransferFrom(
            msg.sender,
            address(this),
            wrappedToken.balanceOf(msg.sender)
        );

        // try to unwrap
        (address token_, uint256 amount, bool success) = _swapFrom(
            wrappedToken,
            wrappedToken.balanceOf(address(this)),
            _minUnwrapAmount
        );

        // unwrap failed, transfer wrapped tokens and exit
        if (!success) {
            wrappedToken.safeTransfer(
                _fallbackAddress,
                wrappedToken.balanceOf(address(this))
            );
            return;
        }

        _forward(
            IERC20(token_),
            amount,
            _router,
            _routerCalldata,
            IERC20(_targetToken),
            _fallbackAddress
        );
    }

    function forward(
        address _wrappedToken,
        address _router,
        bytes memory _routerCalldata,
        address _targetToken,
        address _fallbackAddress
    ) external {
        // grab tokens from the gate
        IERC20 wrappedToken = IERC20(_wrappedToken);
        wrappedToken.safeTransferFrom(
            msg.sender,
            address(this),
            wrappedToken.balanceOf(msg.sender)
        );

        _forward(
            wrappedToken,
            wrappedToken.balanceOf(address(this)),
            _router,
            _routerCalldata,
            IERC20(_targetToken),
            _fallbackAddress
        );
    }

    function _forward(
        IERC20 token,
        uint256 amount,
        address _router,
        bytes memory _routerCalldata,
        IERC20 targetToken,
        address _fallbackAddress
    ) internal {
        (bytes memory patchedCalldata, bool success) = _routerCalldata.patch(
            amount
        );
        if (success) {
            token.approve(_router, amount);
            externalCall(_router, patchedCalldata);
            token.approve(_router, 0);
        }

        // check balances, if they are not empty
        if (token.balanceOf(address(this)) > 0) {
            token.transfer(_fallbackAddress, token.balanceOf(address(this)));
        }

        if (targetToken.balanceOf(address(this)) > 0) {
            targetToken.transfer(
                _fallbackAddress,
                targetToken.balanceOf(address(this))
            );
        }
    }
}

