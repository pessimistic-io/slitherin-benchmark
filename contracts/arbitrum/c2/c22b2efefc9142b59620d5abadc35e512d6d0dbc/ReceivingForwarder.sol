//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";

import "./IERC20.sol";
import "./SafeERC20.sol";

import "./SwapCalldataUtils.sol";

contract ReceivingForwarder is Initializable, AccessControlUpgradeable {
    using SwapCalldataUtils for bytes;
    using SafeERC20 for IERC20;

    address public constant NATIVE_TOKEN = address(0);

    /* ========== INITIALIZERS ========== */

    function initialize() external initializer {
        __ReceivingForwarder_init();
    }

    function __ReceivingForwarder_init()
        internal
        initializer
    {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
    }

    /* ========== FORWARDER METHOD ========== */

    function forward(
        address _dstTokenIn,
        address _router,
        bytes memory _routerCalldata,
        address _dstTokenOut,
        address _fallbackAddress
    ) external payable {
        if (_dstTokenIn == NATIVE_TOKEN) {
            return _forwardFromETH(
                _router,
                _routerCalldata,
                _dstTokenOut,
                _fallbackAddress
            );
        }
        else {
            return _forwardFromERC20(
                IERC20(_dstTokenIn),
                _router,
                _routerCalldata,
                _dstTokenOut,
                _fallbackAddress
            );
        }
    }

    /* ========== HELPER METHODS ========== */

    function _forwardFromETH(
        address _router,
        bytes memory _routerCalldata,
        address _dstTokenOut,
        address _fallbackAddress
    ) internal {
        uint correction = address(this).balance - msg.value;
        uint dstTokenInAmount = msg.value;

        _forward(
            dstTokenInAmount,
            _router,
            _routerCalldata,
            _dstTokenOut,
            _fallbackAddress
        );

        if(address(this).balance > correction) {
            payable(_fallbackAddress).transfer(address(this).balance - correction);
        }
    }

    function _forwardFromERC20(
        IERC20 dstTokenIn,
        address _router,
        bytes memory _routerCalldata,
        address _dstTokenOut,
        address _fallbackAddress
    ) internal {
        // 1. Grab tokens from the gate
        uint correction = dstTokenIn.balanceOf(address(this));
        uint dstTokenInAmount = dstTokenIn.balanceOf(msg.sender);
        dstTokenIn.safeTransferFrom(
            msg.sender,
            address(this),
            dstTokenInAmount
        );

        dstTokenInAmount = dstTokenIn.balanceOf(address(this)) - correction;
        dstTokenIn.approve(_router, dstTokenInAmount);

        _forward(
            dstTokenInAmount,
            _router,
            _routerCalldata,
            _dstTokenOut,
            _fallbackAddress
        );

        // finalize
        dstTokenIn.approve(_router, 0);
        uint postBalance = dstTokenIn.balanceOf(address(this));
        if (postBalance > correction) {
            dstTokenIn.transfer(_fallbackAddress, postBalance - correction);
        }
    }

    function _forwardToETH(
        address _router,
        bytes memory _routerCalldata,
        address _fallbackAddress
    ) internal {
        uint balanceBefore = address(this).balance;

        // value=0 because it's obvious that we won't need ETH to swap to ETH
        // (i.e., impossible: dstTokenIn == dstTokenOut == address(0))
        externalCall(_router, _routerCalldata, 0);

        uint balanceAfter = address(this).balance;

        if (balanceAfter > balanceBefore)
            payable(_fallbackAddress).transfer(balanceAfter - balanceBefore);
    }

    function _forwardToERC20(
        uint256 dstAmountIn,
        address _router,
        bytes memory _routerCalldata,
        IERC20 dstTokenOut,
        address _fallbackAddress
    ) internal {
        uint balanceBefore = dstTokenOut.balanceOf(address(this));

        externalCall(_router, _routerCalldata, dstAmountIn);

        uint balanceAfter = dstTokenOut.balanceOf(address(this));

        if (balanceAfter > balanceBefore) {
            dstTokenOut.transfer(
                _fallbackAddress,
                balanceAfter - balanceBefore
            );
        }
    }

    function _forward(
        uint256 dstAmountIn,
        address _router,
        bytes memory _routerCalldata,
        address _dstTokenOut,
        address _fallbackAddress
    ) internal {
        (bytes memory patchedCalldata, bool success) = _routerCalldata.patch(
            dstAmountIn
        );

        if (!success) {
            return;
        }

        if (_dstTokenOut == NATIVE_TOKEN) {
            return _forwardToETH(
                 _router,
                 patchedCalldata,
                 _fallbackAddress
            );
        }
        else {
            return _forwardToERC20(
                 dstAmountIn,
                 _router,
                 patchedCalldata,
                 IERC20(_dstTokenOut),
                 _fallbackAddress
            );
        }
    }

    function externalCall(address destination, bytes memory data, uint value)
        internal
        returns (bool result)
    {
        uint256 dataLength = data.length;
        assembly {
            let x := mload(0x40) // "Allocate" memory for output (0x40 is where "free memory" pointer is stored by convention)
            let d := add(data, 32) // First 32 bytes are the padded length of data, so exclude that
            result := call(
                gas(), // pass all gas to external call
                destination,
                value,
                d,
                dataLength, // Size of the input (in bytes) - this is what fixes the padding problem
                x,
                0 // Output is ignored, therefore the output size is zero
            )
        }
    }
}

