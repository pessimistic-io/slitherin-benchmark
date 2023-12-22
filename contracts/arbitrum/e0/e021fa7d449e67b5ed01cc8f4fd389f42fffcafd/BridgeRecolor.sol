// SPDX-License-Identifier: LZBL-1.1
// Copyright 2023 LayerZero Labs Ltd.
// You may obtain a copy of the License at
// https://github.com/LayerZero-Labs/license/blob/main/LICENSE-LZBL-1.1

pragma solidity 0.8.19;

import "./Ownable.sol";
import "./IERC20Metadata.sol";
import "./IToUSDVLp.sol";

import "./SwapRecolor.sol";

// 1/ this contract swaps X stable coin to USDV and send it to recolorHelper
// 2/ then use the recolorHelper to send out the usdv
// 3/ it assert the color to be bridge color
contract BridgeRecolor is SwapRecolor, Ownable {
    using SafeERC20 for IERC20;

    uint8 internal constant USDV_DECIMALS = 6;

    IToUSDVLp public lp;
    uint32 public color; // the target color for recoloring
    uint16 public userRewardBps;
    uint16 public toleranceBps;

    constructor(
        address _lp,
        uint32 _color,
        address _recolorHelper,
        address _usdv,
        uint16 _userRewardBps,
        uint16 _toleranceBps
    ) SwapRecolor(_recolorHelper, _usdv) {
        lp = IToUSDVLp(_lp);
        color = _color;
        userRewardBps = _userRewardBps;
        toleranceBps = _toleranceBps;
    }

    // owner sets lp address
    function setLpAddress(address _lp) external onlyOwner {
        lp = IToUSDVLp(_lp);
    }

    function setUserRewardBps(uint16 _userRewardBps) external onlyOwner {
        userRewardBps = _userRewardBps;
    }

    function setColor(uint32 _color) external onlyOwner {
        color = _color;
    }

    function setToleranceBps(uint16 _toleranceBps) external onlyOwner {
        toleranceBps = _toleranceBps;
    }

    function withdrawUSDV(address _to, uint _amount) external onlyOwner {
        usdv.safeTransfer(_to, _amount);
    }

    /// @dev only can recolor to the color set by the owner
    function swapRecolorTransfer(
        SwapParam calldata _swapParam,
        address _receiver,
        uint32 /*_toColor*/
    ) public override returns (uint usdvOut) {
        usdvOut = super.swapRecolorTransfer(_swapParam, _receiver, color);
    }

    /// @dev only can recolor to the color set by the owner
    function swapRecolorSend(
        SwapParam calldata _swapParam,
        uint32 /*_toColor*/,
        IOFT.SendParam memory _param, // need to change the amountLD
        bytes calldata _extraOptions,
        MessagingFee calldata _msgFee,
        address payable _refundAddress,
        bytes calldata _composeMsg
    ) public payable override returns (uint usdvOut, MessagingReceipt memory msgReceipt) {
        (usdvOut, msgReceipt) = super.swapRecolorSend(
            _swapParam,
            color,
            _param,
            _extraOptions,
            _msgFee,
            _refundAddress,
            _composeMsg
        );
    }

    function _swap(SwapParam calldata _param) internal override returns (uint usdvOut) {
        // approve the lp to spend the token
        IERC20(_param._fromToken).forceApprove(address(lp), _param._fromTokenAmount);
        uint beforeUSDVBalance = usdv.balanceOf(address(this));
        uint usdvSwapped = lp.swapToUSDV(_param._fromToken, _param._fromTokenAmount, _param._minUSDVOut, address(this));

        // cross-check with balance to make sure that lp is behaving as expected
        uint afterUSDVBalance = usdv.balanceOf(address(this));
        require(afterUSDVBalance - beforeUSDVBalance == usdvSwapped, "BridgeRecolor: swap amount too low");

        usdvOut = _getUSDVOut(_param._fromToken, _param._fromTokenAmount);
        require(afterUSDVBalance >= usdvOut, "BridgeRecolor: not enough usdv");
        if (usdvOut > usdvSwapped) {
            require(usdvOut - usdvSwapped <= (usdvOut * toleranceBps) / 10000, "BridgeRecolor: exceeds tolerance");
        }
        // slippage assertion
        require(usdvOut >= _param._minUSDVOut, "BridgeRecolor: swap amount too low");
    }

    // view function for supported tokens of the lp
    function getSupportedTokens() external view returns (address[] memory tokens) {
        return lp.getSupportedTokens();
    }

    // view function for estimating output
    function getUSDVOut(address _fromToken, uint _fromTokenAmount) external view returns (uint usdvOut) {
        usdvOut = _getUSDVOut(_fromToken, _fromTokenAmount);
        uint usdvFromLp = lp.getUSDVOut(_fromToken, _fromTokenAmount);
        require(usdv.balanceOf(address(this)) + usdvFromLp >= usdvOut, "BridgeRecolor: not enough usdv");
        if (usdvOut > usdvFromLp) {
            require(usdvOut - usdvFromLp <= (usdvOut * toleranceBps) / 10000, "BridgeRecolor: exceeds tolerance");
        }
    }

    function getUSDVOutVerbose(
        address _fromToken,
        uint _fromTokenAmount
    ) external view returns (uint usdvOut, uint fee, uint reward) {
        uint8 tokenDecimals = IERC20Metadata(_fromToken).decimals();
        require(tokenDecimals >= USDV_DECIMALS, "BridgeRecolor: token decimals must >= 6");
        uint usdvRequested = _fromTokenAmount / (10 ** (tokenDecimals - USDV_DECIMALS));

        fee = 0;
        reward = (usdvRequested * userRewardBps) / 10000;
        usdvOut = usdvRequested + reward;

        uint usdvFromLp = lp.getUSDVOut(_fromToken, _fromTokenAmount);
        require(usdv.balanceOf(address(this)) + usdvFromLp >= usdvOut, "BridgeRecolor: not enough usdv");
        if (usdvOut > usdvFromLp) {
            require(usdvOut - usdvFromLp <= (usdvOut * toleranceBps) / 10000, "BridgeRecolor: exceeds tolerance");
        }
    }

    function _getUSDVOut(address _fromToken, uint _fromTokenAmount) internal view returns (uint usdvOut) {
        uint8 tokenDecimals = IERC20Metadata(_fromToken).decimals();
        require(tokenDecimals >= USDV_DECIMALS, "BridgeRecolor: token decimals must >= 6");
        uint usdvRequested = _fromTokenAmount / (10 ** (tokenDecimals - USDV_DECIMALS));
        usdvOut = usdvRequested + (usdvRequested * userRewardBps) / 10000;
    }
}

