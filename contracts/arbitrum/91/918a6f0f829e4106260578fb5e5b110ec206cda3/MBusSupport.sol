// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./BaseSupport.sol";
import "./Structs.sol";
import "./IWETH.sol";
import "./IMBusSupport.sol";
import { IMessageBus } from "./ICeler.sol";
import { MessageSenderLib, MsgDataTypes } from "./MessageSenderLib.sol";

import "./Address.sol";
import "./Strings.sol";
import "./SafeERC20.sol";

//celer message bus support
contract MBusSupport is BaseSupport, Structs, IMBusSupport {
    using SafeERC20 for IERC20;

    event SendIM(address _receiver, address _token, uint256 _amount, bytes32 _transferId);
    event TransferRefund(address _receiver, address _token, uint256 _amount);
    event TransferFallback(address _receiver, address _token, uint256 _amount);

    address public immutable override messageBus;
    address public immutable bridge;
    address public immutable weth;

    constructor(address _messageBus, address _weth) {
        messageBus = _messageBus;
        bridge = IMessageBus(_messageBus).liquidityBridge();
        weth = _weth;
    }

    ///@param _swap Whether swap is required after cross chain
    ///@param _swapInfo If the transaction information of the transaction is required
    function _crossChainSwap(
        SwapBaseInfo memory _baseInfo,
        uint256 _crossFee,
        uint64 _dstChainId,
        address _dstContract,
        address _crossToken,
        uint32 _maxSlippage,
        bool _swap,
        SwapInfo memory _swapInfo
    ) external payable override returns (bytes32 _transferId) {
        (bytes memory _sendData, uint256 _fee) = getFee(_baseInfo, _crossFee, _swap, _swapInfo);
        require(msg.value >= _fee, string(Strings.toString(_fee)));

        _transferId = MessageSenderLib.sendMessageWithTransfer(
            _dstContract,
            _crossToken,
            _baseInfo._amount,
            _dstChainId,
            uint64(block.timestamp),
            _maxSlippage,
            _sendData, // message
            MsgDataTypes.BridgeSendType.Liquidity, // the bridge type, we are using liquidity bridge at here
            messageBus,
            _fee
        );
        emit SendIM(msg.sender, _crossToken, _baseInfo._amount, _transferId);
    }

    function getFee(
        SwapBaseInfo memory _baseInfo,
        uint256 _crossFee,
        bool _swap,
        SwapInfo memory _swapInfo
    ) public view override returns (bytes memory _sendData, uint256 _fee) {
        CrossChainData memory _transferData;
        if (_swap) {
            _transferData = CrossChainData({ _receiver: msg.sender, _baseInfo: _baseInfo, _swap: true, _swapInfo: _swapInfo, _crossFee: _crossFee });
        } else {
            _transferData._swap = false;
            _transferData._receiver = msg.sender;
            _transferData._crossFee = _crossFee;
        }

        _sendData = abi.encode(_transferData);
        _fee = IMessageBus(messageBus).calcFee(_sendData);
    }
}

