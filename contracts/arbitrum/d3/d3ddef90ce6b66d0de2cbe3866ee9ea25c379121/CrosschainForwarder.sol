//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";

import "./IERC20.sol";
import "./draft-IERC20Permit.sol";
import "./SafeERC20.sol";

import "./IDeBridgeGate.sol";
import "./ICrossChainForwarder.sol";
import "./Flags.sol";
import "./SignatureUtil.sol";

contract CrosschainForwarder is Initializable, AccessControlUpgradeable, ICrossChainForwarder {
    using SafeERC20 for IERC20;
    using Flags for uint256;
    using SignatureUtil for bytes;

    /// @dev Basis points or bps, set to 10 000 (equal to 1/10000). Used to express relative values (fees)
    uint256 public constant BPS_DENOMINATOR = 10000;

    address public constant NATIVE_TOKEN = address(0);

    IDeBridgeGate public deBridgeGate;

    /* ========== ERRORS ========== */

    // swap router didn't put target tokens on this (forwarder's) address
    error SwapEmptyResult(address srcTokenOut);

    error SwapFailed(address srcRouter);

    error NotEnoughSrcFundsIn(uint amount);

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
        __CrosschainForwarder_init_unchained(_deBridgeGate);
    }

    function __CrosschainForwarder_init_unchained(IDeBridgeGate _deBridgeGate)
        internal
        initializer
    {
        deBridgeGate = _deBridgeGate;
    }

    /* ========== METHODS ========== */

    function swapAndSend(
        address _srcTokenIn,
        uint _srcAmountIn,
        bytes memory _srcTokenInPermit,
        address _srcSwapRouter,
        bytes calldata _srcSwapCalldata,
        address _srcTokenOut,
        bytes calldata _dstDetails
    ) external payable {
        uint ethBalanceBefore = address(this).balance - msg.value;
        uint srcAmountOut;

        if (_srcTokenIn == NATIVE_TOKEN) {
            _validateSrcETHIn(_srcAmountIn);
            srcAmountOut = _swapToERC20Via(
                _srcSwapRouter,
                _srcSwapCalldata,
                _srcAmountIn,
                IERC20(_srcTokenOut)
            );
        }
        else {
            // grab the tokens
            IERC20 srcTokenIn = IERC20(_srcTokenIn);
            srcAmountOut = _collectSrcERC20In(srcTokenIn, _srcAmountIn, _srcTokenInPermit);

            srcTokenIn.safeApprove(_srcSwapRouter, srcAmountOut);
            if (_srcTokenOut == NATIVE_TOKEN) {
                _swapToETHVia(_srcSwapRouter, _srcSwapCalldata);
                srcAmountOut = 0; // ETH amount will be calculated separately
            }
            else {
                srcAmountOut = _swapToERC20Via(_srcSwapRouter, _srcSwapCalldata, 0, IERC20(_srcTokenOut));
            }
            srcTokenIn.safeApprove(_srcSwapRouter, 0);
        }

        _sendToBridge(
            _srcTokenOut,
            srcAmountOut,
            address(this).balance - ethBalanceBefore, // value
            _dstDetails
        );
    }

    function send(
        address _srcTokenIn,
        uint _srcInAmount,
        bytes memory _srcTokenInPermit,
        bytes calldata _dstDetails
    ) external payable {
        uint srcAmountOut;

        if (_srcTokenIn == NATIVE_TOKEN) {
            _validateSrcETHIn(_srcInAmount);
        }
        else {
            srcAmountOut = _collectSrcERC20In(IERC20(_srcTokenIn), _srcInAmount, _srcTokenInPermit);
        }

        _sendToBridge(
            _srcTokenIn,
            srcAmountOut,
            msg.value,
            _dstDetails
        );
    }


    function _validateSrcETHIn(uint _srcAmountIn) internal view {
        // mind that msg.value = srcAmountIn + globalFixedNativeFee,
        // that's why we need to validate _srcAmountIn separately
        if (!(address(this).balance >= _srcAmountIn))
            revert NotEnoughSrcFundsIn(_srcAmountIn);

        // actually, we may implement this check too:
        // require(msg.value == (deBridgeGate.globalFixedNativeFee + _srcAmountIn))
        // but it is yet not clear how deBridgeGate.globalFixedNativeFee is generated
    }

    function _collectSrcERC20In(
        IERC20 _token,
        uint _amount,
        bytes memory _permit) internal returns (uint) {

        // call permit before transferring token
        if (_permit.length > 0) {
            uint256 deadline = _permit.toUint256(0);
            (bytes32 r, bytes32 s, uint8 v) = _permit.parseSignature(32);
            IERC20Permit(address(_token)).permit(
                msg.sender,
                address(this),
                _amount,
                deadline,
                v,
                r,
                s);
        }

        uint256 balanceBefore = _token.balanceOf(address(this));
        _token.safeTransferFrom(msg.sender, address(this), _amount);
        uint balanceAfter = _token.balanceOf(address(this));

        if (!(balanceAfter > balanceBefore))
            revert NotEnoughSrcFundsIn(_amount);

        return (balanceAfter - balanceBefore);
    }

    function _swapToETHVia(
        address _router,
        bytes calldata _calldata
    ) internal returns (uint) {
        uint256 balanceBefore = address(this).balance;

        bool success = externalCall(_router, _calldata, 0);
        if (!success) {
            revert SwapFailed(_router);
        }

        uint256 balanceAfter = address(this).balance;

        if (balanceBefore >= balanceAfter)
            revert SwapEmptyResult(address(0));

        uint256 swapDstTokenBalance = balanceAfter - balanceBefore;
        return swapDstTokenBalance;
    }

    function _swapToERC20Via(
        address _router,
        bytes calldata _calldata,
        uint _value,
        IERC20 _targetToken
    ) internal returns (uint256) {
        uint256 balanceBefore = _targetToken.balanceOf(address(this));

        bool success = externalCall(_router, _calldata, _value);
        if (!success) {
            revert SwapFailed(_router);
        }

        uint256 balanceAfter = _targetToken.balanceOf(address(this));
        if (balanceBefore >= balanceAfter)
            revert SwapEmptyResult(address(_targetToken));

        uint256 swapDstTokenBalance = balanceAfter - balanceBefore;
        return swapDstTokenBalance;
    }

    function _sendToBridge(
        address token,
        uint256 amount,
        uint _value,
        bytes calldata _dstDetails
    ) internal {
        require(_dstDetails.length > 0);
        DstDetails memory dstDetails;
        dstDetails = abi.decode(_dstDetails, (DstDetails));

        // remember balance to correctly calc the change
        uint ethBalanceBefore = address(this).balance - _value;

        if (token != NATIVE_TOKEN) {
            // allow deBridge gate to take all these wrapped tokens
            IERC20(token).approve(address(deBridgeGate), amount);
        }

        // configure deBridge
        IDeBridgeGate.SubmissionAutoParamsTo memory autoParams;
        autoParams.fallbackAddress = abi.encodePacked(dstDetails.fallbackAddress);
        autoParams.data = dstDetails.receiverCalldata;

        // send to deBridge gate
        // TODO: re-calc value
        deBridgeGate.send{value: _value}(
            address(token), // _tokenAddress
            amount, // _amount
            dstDetails.chainId, // _chainIdTo
            abi.encodePacked(dstDetails.receiver), // _receiver
            "", // _permit
            dstDetails.useAssetFee, // _useAssetFee
            dstDetails.referralCode, // _referralCode
            abi.encode(autoParams) // _autoParams
        );

        if (token != NATIVE_TOKEN) {
            // turn off allowance
            IERC20(token).approve(address(deBridgeGate), 0);
        }

        // return change, if any
        if (address(this).balance > ethBalanceBefore)
            payable(msg.sender).transfer(address(this).balance - ethBalanceBefore);
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

    receive() external payable {
    }
}

