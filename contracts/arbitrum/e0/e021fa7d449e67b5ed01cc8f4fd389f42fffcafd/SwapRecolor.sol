// SPDX-License-Identifier: LZBL-1.1
// Copyright 2023 LayerZero Labs Ltd.
// You may obtain a copy of the License at
// https://github.com/LayerZero-Labs/license/blob/main/LICENSE-LZBL-1.1

pragma solidity ^0.8.0;

import "./IRecolorHelper.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

// this contract is generic for partner to perform stable coin swap into USDV and use recolorHelper to send out
// example 1: deploy as a generic help built on recolor helper for any protocols to swap into the provided color
// example 2: inherited by a specific protocol and only swap into the preconfigured color by asserting the toColor == myColor
abstract contract SwapRecolor is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct SwapParam {
        address _fromToken;
        uint _fromTokenAmount;
        uint64 _minUSDVOut;
    }

    IRecolorHelper public immutable recolorHelper;
    IERC20 public immutable usdv;

    constructor(address _recolorHelper, address _usdv) {
        recolorHelper = IRecolorHelper(_recolorHelper);
        usdv = IERC20(_usdv);
    }

    /// @dev do swap and then transfer out with color through recolorHelper
    function swapRecolorTransfer(
        SwapParam calldata _swapParam,
        address _receiver,
        uint32 _toColor
    ) public virtual nonReentrant returns (uint usdvOut) {
        // get the token from msg.sender
        IERC20(_swapParam._fromToken).safeTransferFrom(msg.sender, address(this), _swapParam._fromTokenAmount);
        // do the swap and send the token to recolorHelper
        usdvOut = _swap(_swapParam);
        // send out through recolorHelper
        usdv.approve(address(recolorHelper), usdvOut);
        recolorHelper.approvedTransferWithColor(_receiver, usdvOut, _toColor);
    }

    /// @dev do swap and then transfer out with color through recolorHelper
    function swapRecolorSend(
        SwapParam calldata _swapParam,
        uint32 _toColor,
        IOFT.SendParam memory _param, // need to change the amountLD
        bytes calldata _extraOptions,
        MessagingFee calldata _msgFee,
        address payable _refundAddress,
        bytes calldata _composeMsg
    ) public payable virtual nonReentrant returns (uint usdvOut, MessagingReceipt memory msgReceipt) {
        // get the token from msg.sender
        IERC20(_swapParam._fromToken).safeTransferFrom(msg.sender, address(this), _swapParam._fromTokenAmount);
        // do the swap and send the token to recolorHelper
        usdvOut = _swap(_swapParam);
        // override this with the swap output
        _param.amountLD = usdvOut;
        // send out through recolorHelper
        usdv.approve(address(recolorHelper), usdvOut);
        msgReceipt = recolorHelper.approvedSendWithColor{value: msg.value}(
            _param,
            _toColor,
            _extraOptions,
            _msgFee,
            _refundAddress,
            _composeMsg
        );
    }

    // can override this function on different chains to connect to different dex
    function _swap(SwapParam calldata _param) internal virtual returns (uint usdvOut);
}

