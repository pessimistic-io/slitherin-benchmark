// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;
import "./SafeERC20.sol";
import "./IERC20.sol";
import "./MessageApp.sol";

// A HelloWorld example for basic cross-chain message passing
contract OriginalToken is MessageApp {
    using SafeERC20 for IERC20;

    address token;

    event MessageReceived(address srcContract, uint64 srcChainId, address sender, bytes message);

    constructor(address _messageBus, address _token) MessageApp(_messageBus) {
        token = _token;
    }

    // called by user on source chain to send cross-chain messages
    function deposit(
        address _dstContract,
        uint256 _amount,
        uint64 _dstChainId,
        bytes calldata _message
    ) external payable {
        IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);
        bytes memory message = abi.encode(msg.sender, _amount, _message);
        sendMessage(_dstContract, _dstChainId, message, msg.value);
    }

    // called by MessageBus on destination chain to receive cross-chain messages
    function executeMessage(
        address _srcContract,
        uint64 _srcChainId,
        bytes calldata _message,
        address // executor
    ) external payable override onlyMessageBus returns (ExecutionStatus) {
        (address sender, uint256 amount, bytes memory message) = abi.decode((_message), (address, uint256, bytes));
        IERC20(token).safeTransfer(sender, amount);
        emit MessageReceived(_srcContract, _srcChainId, sender, message);
        return ExecutionStatus.Success;
    }
}

