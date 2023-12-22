// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {SwapFailed} from "./GenericErrors.sol";
import "./SafeERC20.sol";
import "./Structs.sol";
import "./LibDiamond.sol";
import "./LibData.sol";

library LibPlexusUtil {
    using SafeERC20 for IERC20;
    IERC20 private constant NATIVE_ADDRESS = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    bytes32 internal constant NAMESPACE = keccak256("com.plexus.facets.swap");

    function getSwapStorage() internal pure returns (Dex storage s) {
        bytes32 namespace = NAMESPACE;
        assembly {
            s.slot := namespace
        }
    }

    /// @notice Determines whether the given address is the zero address
    /// @param addr The address to verify
    /// @return Boolean indicating if the address is the zero address
    function isZeroAddress(address addr) internal pure returns (bool) {
        return addr == address(0);
    }

    function getBalance(address token) internal view returns (uint256) {
        return token == address(NATIVE_ADDRESS) ? address(this).balance : IERC20(token).balanceOf(address(this));
    }

    function userBalance(address user, address token) internal view returns (uint256) {
        return token == address(NATIVE_ADDRESS) ? user.balance : IERC20(token).balanceOf(user);
    }

    function _isNative(address _token) internal pure returns (bool) {
        return (IERC20(_token) == NATIVE_ADDRESS);
    }

    function _isTokenDeposit(address _token, uint256 _amount) internal returns (bool isNotNative) {
        isNotNative = !_isNative(_token);

        if (isNotNative) {
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        }
    }

    function _tokenDepositAndSwap(SwapData calldata swap) internal returns (uint256) {
        _isTokenDeposit(swap.srcToken, swap.amount);
        Dex storage s = LibPlexusUtil.getSwapStorage();
        require(s.allowedDex[swap.swapRouter]);
        uint256 dstAmount = _swapStart((swap));
        return dstAmount;
    }

    function _tokenDepositAndUserSwap(SwapData calldata swap) internal returns (uint256) {
        _isTokenDeposit(swap.srcToken, swap.amount);
        Dex storage s = LibPlexusUtil.getSwapStorage();
        require(s.allowedDex[swap.swapRouter]);
        uint256 dstAmount = _userSwapStart((swap));
        return dstAmount;
    }

    function _swapStart(SwapData calldata swap) internal returns (uint256 dstAmount) {
        Dex storage s = LibPlexusUtil.getSwapStorage();
        require(s.allowedDex[swap.swapRouter]);
        bool isNotNative = !_isNative(swap.srcToken);
        if (isNotNative) {
            if (s.proxy[swap.swapRouter] != address(0)) {
                IERC20(swap.srcToken).approve(s.proxy[swap.swapRouter], swap.amount);
            } else {
                IERC20(swap.srcToken).approve(swap.swapRouter, swap.amount);
            }
        }
        uint256 initDstTokenBalance = getBalance(swap.dstToken);
        (bool succ, ) = swap.swapRouter.call{value: isNotNative ? 0 : swap.amount}(swap.callData);
        if (succ) {
            uint256 dstTokenBalance = getBalance(swap.dstToken);
            dstAmount = dstTokenBalance > initDstTokenBalance ? dstTokenBalance - initDstTokenBalance : dstTokenBalance;
            emit LibData.Swap(swap.user, swap.srcToken, swap.dstToken, swap.amount, dstAmount);
        } else {
            revert SwapFailed();
        }
    }

    function _userSwapStart(SwapData calldata swap) internal returns (uint256 dstAmount) {
        Dex storage s = LibPlexusUtil.getSwapStorage();
        require(s.allowedDex[swap.swapRouter]);
        bool isNotNative = !_isNative(swap.srcToken);
        if (isNotNative) {
            IERC20(swap.srcToken).approve(swap.swapRouter, swap.amount);
        }
        uint256 initDstTokenBalance = userBalance(swap.user, swap.dstToken);
        (bool succ, ) = swap.swapRouter.call{value: isNotNative ? 0 : swap.amount}(swap.callData);
        if (succ) {
            uint256 dstTokenBalance = userBalance(swap.user, swap.dstToken);
            dstAmount = dstTokenBalance > initDstTokenBalance ? dstTokenBalance - initDstTokenBalance : dstTokenBalance;
            emit LibData.Swap(swap.user, swap.srcToken, swap.dstToken, swap.amount, dstAmount);
        } else {
            revert SwapFailed();
        }
    }

    function _safeNativeTransfer(address to_, uint256 amount_) internal {
        (bool sent, ) = to_.call{value: amount_}("");
        require(sent, "Safe safeTransfer fail");
    }

    function getFeeReceiver() internal view returns (address) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        if (ds.feeReceiver == address(0)) {
            return LibDiamond.contractOwner();
        } else {
            return ds.feeReceiver;
        }
    }

    function getBridgeFee() internal view returns (uint256) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return ds.fee;
    }

    function _fee(address dstToken, uint256 dstAmount) internal returns (uint256 returnAmount) {
        uint256 getFee = (dstAmount * getBridgeFee()) / 10000;
        returnAmount = dstAmount - getFee;

        address feeReceiver = getFeeReceiver();

        if (getFee > 0) {
            if (!_isNative(dstToken)) {
                IERC20(dstToken).safeTransfer(feeReceiver, getFee);
            } else {
                _safeNativeTransfer(feeReceiver, getFee);
            }
        }
    }
}

