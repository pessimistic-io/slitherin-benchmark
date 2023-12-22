//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "./Address.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

import "./IDeBridgeGate.sol";
import "./Flags.sol";

import "./BaseForwarder.sol";

contract CrosschainForwarder is BaseForwarder {
    using Flags for uint256;
    using SafeERC20 for IERC20;

    IDeBridgeGate public deBridgeGate;

    /* ========== ERRORS ========== */

    // swap router didn't put target tokens on this (forwarder's) address
    error SwapEmptyResult(address swapDstToken);

    // wrapper pool not found
    error WrapPoolNotFound(address tokenToWrap);

    // wrapper pool didn't put wrapped tokens on this (forwarder's) address
    error WrapPoolEmptyResult(address tokenToWrap);

    //
    error WrapFailed(address tokenToWrap);

    /* ========== INITIALIZERS ========== */

    function initialize(IDeBridgeGate _deBridgeGate) external initializer {
        __CrosschainForwarder_init(_deBridgeGate);
    }

    function __CrosschainForwarder_init(IDeBridgeGate _deBridgeGate)
        internal
        initializer
    {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __BaseForwarder_init_unchained();
        __CrosschainForwarder_init_unchained(_deBridgeGate);
    }

    function __CrosschainForwarder_init_unchained(IDeBridgeGate _deBridgeGate)
        internal
        initializer
    {
        deBridgeGate = _deBridgeGate;
    }

    /* ========== METHODS ========== */

    function swapAndWrapAndSend(
        address _srcTokenIn,
        uint _srcTokenAmountIn,
        address _srcSwapRouter,
        bytes calldata _srcSwapCalldata,
        address _srcTokenSwapTo,
        uint256 _wrapSlippageBps,
        uint256 _targetChainId,
        address _targetReceiver,
        bytes calldata _targetCalldata,
        address _targetFallbackAddress
    ) external payable {
        // grab the tokens
        IERC20 srcTokenIn = IERC20(_srcTokenIn);
        srcTokenIn.safeTransferFrom(msg.sender, address(this), _srcTokenAmountIn);

        // 1) Invoke swapRouter to do the swap
        IERC20 srcTokenSwapTo = IERC20(_srcTokenSwapTo);
        srcTokenIn.safeApprove(_srcSwapRouter, srcTokenIn.balanceOf(address(this)));
        uint256 srcTokenSwapToBalance = _swapVia(
            _srcSwapRouter,
            _srcSwapCalldata,
            srcTokenSwapTo
        );

        // 2) Wrap dstToken via curve
        (
            address wrappedToken,
            uint256 wrappedAmount,
            bool wrapSuccess
        ) = _swapFrom(
            srcTokenSwapTo,
            srcTokenSwapToBalance,
            srcTokenSwapToBalance - (srcTokenSwapToBalance * _wrapSlippageBps) / BPS_DENOMINATOR
        );
        if (!wrapSuccess) {
            if (wrappedToken == address(0))
                revert WrapPoolNotFound(_srcTokenSwapTo);
            else if (wrappedAmount == 0) revert WrapPoolEmptyResult(_srcTokenSwapTo);
            else revert WrapFailed(_srcTokenSwapTo);
        }

        // 3) send to the gate
        _sendToBridge(
            IERC20(wrappedToken),
            wrappedAmount,
            _targetChainId,
            _targetReceiver,
            _targetCalldata,
            _targetFallbackAddress
        );
    }

    function swapAndSend(
        address _swapRouter,
        bytes calldata _swapCalldata,
        address _swapDstToken,
        uint256 _targetChainId,
        address _targetReceiver,
        bytes calldata _targetCalldata,
        address _targetFallbackAddress
    ) external payable {
        // 1) Invoke swapRouter to do the swap
        IERC20 swapDstToken = IERC20(_swapDstToken);

        uint256 swapDstTokenBalance = _swapVia(
            _swapRouter,
            _swapCalldata,
            swapDstToken
        );

        // 2) send to the gate
        _sendToBridge(
            swapDstToken,
            swapDstTokenBalance,
            _targetChainId,
            _targetReceiver,
            _targetCalldata,
            _targetFallbackAddress
        );
    }

    function wrapAndSend(
        address _token,
        uint _amount,
        uint256 _minWrapAmount,
        uint256 _targetChainId,
        address _targetReceiver,
        bytes calldata _targetCalldata,
        address _targetFallbackAddress
    ) external payable {
        // grab the tokens
        IERC20 token = IERC20(_token);
        token.safeTransferFrom(msg.sender, address(this), _amount);

        // wrap via dstToken via curve
        (
            address wrappedToken,
            uint256 wrappedAmount,
            bool wrapSuccess
        ) = _swapFrom(token, _amount, _minWrapAmount);
        if (!wrapSuccess) {
            if (wrappedToken == address(0))
                revert WrapPoolNotFound(_token);
            else if (wrappedAmount == 0) revert WrapPoolEmptyResult(_token);
            else revert WrapFailed(_token);
        }

        _sendToBridge(
            IERC20(wrappedToken),
            wrappedAmount,
            _targetChainId,
            _targetReceiver,
            _targetCalldata,
            _targetFallbackAddress
        );
    }

    function send(
        address _token,
        uint _amount,
        uint256 _targetChainId,
        address _targetReceiver,
        bytes calldata _targetCalldata,
        address _targetFallbackAddress
    ) external payable {
        IERC20 token = IERC20(_token);
        token.safeTransferFrom(msg.sender, address(this), _amount);

        _sendToBridge(
            token,
            _amount,
            _targetChainId,
            _targetReceiver,
            _targetCalldata,
            _targetFallbackAddress
        );
    }

    function _swapVia(
        address swapRouter,
        bytes calldata swapCalldata,
        IERC20 swapDstToken
    ) internal returns (uint256) {
        uint256 balanceBefore = swapDstToken.balanceOf(address(this));
        Address.functionCall(
            swapRouter,
            swapCalldata,
            "Failed calling _swapRouter"
        );
        uint256 balanceAfter = swapDstToken.balanceOf(address(this));
        if (balanceBefore >= balanceAfter)
            revert SwapEmptyResult(address(swapDstToken));

        uint256 swapDstTokenBalance = balanceAfter - balanceBefore;
        return swapDstTokenBalance;
    }

    function _sendToBridge(
        IERC20 token,
        uint256 amount,
        uint256 targetChainId,
        address targetReceiver,
        bytes calldata targetCalldata,
        address targetFallbackAddress
    ) internal {
        // allow deBridge gate to take all these wrapped tokens
        token.approve(address(deBridgeGate), amount);

        // configure deBridge
        IDeBridgeGate.SubmissionAutoParamsTo memory autoParams;
        autoParams.fallbackAddress = abi.encodePacked(targetFallbackAddress);
        autoParams.data = targetCalldata;

        // remember balance to correctly calc the change
        uint initialBalance = address(this).balance - msg.value;

        // send to deBridge gate
        deBridgeGate.send{value: msg.value}(
            address(token), // _tokenAddress
            amount, // _amount
            targetChainId, // _chainIdTo
            abi.encodePacked(targetReceiver), // _receiver
            "", // _permit
            false, // _useAssetFee
            0, // _referralCode
            abi.encode(autoParams) // _autoParams
        );

        // turn off allowance
        token.approve(address(deBridgeGate), 0);

        // return change, if any
        if (address(this).balance > initialBalance)
            payable(msg.sender).transfer(address(this).balance - initialBalance);
    }

    receive() external payable {
        require(msg.sender == address(deBridgeGate), "for change only");
    }
}

