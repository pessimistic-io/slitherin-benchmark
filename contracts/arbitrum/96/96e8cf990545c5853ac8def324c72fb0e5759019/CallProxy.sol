// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.17;

import "./Utils.sol";
import "./Ownable2Step.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

contract CallProxy is Ownable2Step {
    using SafeERC20 for IERC20;

    address public bridge;

    event SetBridge(address bridge);

    modifier onlyBridge() {
        require(msg.sender == bridge, "CallProxy: no privilege");
        _;
    }

    function proxyCall(
        address token,
        uint256 amount,
        address receiver,
        bytes memory callData
    ) external onlyBridge returns (bool) {
        try this.decodeCallDataForExternalCall(callData) returns (address callee, bytes memory data) {
            IERC20(token).safeApprove(callee, 0);
            IERC20(token).safeApprove(callee, amount);

            callee.call(data);
        } catch {}

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(receiver, balance);
        }

        return true;
    }

    function setBridge(address newBridge) external onlyOwner {
        require(newBridge != address(0), "bridge address cannot be zero");
        bridge = newBridge;
        emit SetBridge(newBridge);
    }

    function rescueFund(address tokenAddress) external onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        token.safeTransfer(_msgSender(), token.balanceOf(address(this)));
    }

    function decodeCallDataForExternalCall(bytes memory callData) external pure returns (
        address callee,
        bytes memory data
    ) {
        uint256 offset = 0;

        bytes memory calleeAddressBytes;
        (calleeAddressBytes, offset) = Utils.NextVarBytes(callData, offset);
        callee = Utils.bytesToAddress(calleeAddressBytes);

        (data, offset) = Utils.NextVarBytes(callData, offset);
    }

    function encodeCallDataForExternalCall(
        address callee,
        bytes calldata callData
    ) external pure returns (bytes memory) {
        bytes memory buff;

        buff = abi.encodePacked(
            Utils.WriteVarBytes(abi.encodePacked(callee)),
            Utils.WriteVarBytes(callData)
        );

        return buff;
    }
}

