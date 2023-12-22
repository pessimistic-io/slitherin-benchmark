// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import "./Switch.sol";
import "./DataTypes.sol";
import { ICallDataExecutor } from "./ICallDataExecutor.sol";
import { ISwitchEvent } from "./ISwitchEvent.sol";
import "./IMessageReceiverApp.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";

contract SwitchCelerDepositReceiver is Ownable, ReentrancyGuard {
    address public celerMessageBus;
    address public callDataExecutor;
    address public paraswapProxy;
    address public augustusSwapper;
    ISwitchEvent public switchEvent;
    using SafeERC20 for IERC20;
    using UniversalERC20 for IERC20;

    event CallDataExecutorSet(address callDataExecutor);
    event CelerMessageBusSet(address celerMessageBus);
    event ParaswapProxySet(address paraswapProxy);
    event AugustusSwapperSet(address augustusSwapper);

    struct CelerDepositRequest {
        bytes32 id;
        bytes32 bridge;
        address srcToken;
        address bridgeToken;
        address depositToken;
        address recipient;
        address depositContract;
        address toApprovalAddress; // the approval address for deposit
        address contractOutputsToken;  // optional, some contract will output a token (e.g. staking) to forward the token to the user.
        uint256 srcAmount;
        uint256 bridgeDstAmount;
        uint256 estimatedDepositAmount;
        uint32 toContractGasLimit;
        DataTypes.ParaswapUsageStatus paraswapUsageStatus;
        uint256[] dstDistribution;
        bytes depositCallData;
        bytes dstParaswapData;
    }

    constructor(
        address _switchEventAddress,
        address _callDataExecutor,
        address _celerMessageBus,
        address _paraswapProxy,
        address _augustusSwapper
    ) public {
        switchEvent = ISwitchEvent(_switchEventAddress);
        celerMessageBus = _celerMessageBus;
        callDataExecutor = _callDataExecutor;
        paraswapProxy = _paraswapProxy;
        augustusSwapper = _augustusSwapper;
    }

    modifier onlyMessageBus() {
        require(msg.sender == celerMessageBus, "caller is not message bus");
        _;
    }

    function setCelerMessageBus(address _newCelerMessageBus) external onlyOwner {
        celerMessageBus = _newCelerMessageBus;
        emit CelerMessageBusSet(_newCelerMessageBus);
    }

    function setCallDataExecutor(address _newCallDataExecutor) external onlyOwner {
        callDataExecutor = _newCallDataExecutor;
        emit CallDataExecutorSet(_newCallDataExecutor);
    }

    function setParaswapProxy(address _paraswapProxy) external onlyOwner {
        paraswapProxy = _paraswapProxy;
        emit ParaswapProxySet(_paraswapProxy);
    }

    function setAugustusSwapper(address _augustusSwapper) external onlyOwner {
        augustusSwapper = _augustusSwapper;
        emit AugustusSwapperSet(_augustusSwapper);
    }

    // handler function required by MsgReceiverApp
    function executeMessageWithTransfer(
        address, //sender
        address _token,
        uint256 _amount,
        uint64 _srcChainId,
        bytes memory _message,
        address // executor
    )
        external
        payable
        onlyMessageBus
        returns (IMessageReceiverApp.ExecutionStatus)
    {
        CelerDepositRequest memory m = abi.decode((_message), (CelerDepositRequest));
        require(_token == m.bridgeToken, "bridged token must be the same as the first token in destination swap path");
        uint256 depositAmount = m.estimatedDepositAmount;
        if (m.bridgeToken != m.depositToken) {
            require(m.bridgeDstAmount <= _amount, "estimated bridge token balance is insufficient");
            // swap token through paraswap
            ICallDataExecutor(callDataExecutor).execute(IERC20(_token), augustusSwapper, paraswapProxy, _amount, 0, m.dstParaswapData);
            // deposit token to lending protocal
            ICallDataExecutor(callDataExecutor).execute(IERC20(m.depositToken), m.depositContract, m.toApprovalAddress, depositAmount, m.toContractGasLimit, m.depositCallData);
            _emitCrosschainDepositDone(m, _amount, depositAmount, DataTypes.DepositStatus.Succeeded);
        } else {
            depositAmount = m.bridgeDstAmount;
            require(depositAmount <= _amount, "deposit balance is insufficient");

            if (IERC20(_token).isETH()) {
                ICallDataExecutor(callDataExecutor).sendNativeAndExecute{ value: _amount }(
                    IERC20(m.depositToken),
                    m.depositContract,
                    m.toApprovalAddress,
                    depositAmount,
                    m.toContractGasLimit,
                    m.depositCallData
                );
            } else {
                // Give approval
                IERC20(_token).universalApprove(callDataExecutor, _amount);
                ICallDataExecutor(callDataExecutor).sendAndExecute(
                    IERC20(m.depositToken),
                    m.depositContract,
                    m.toApprovalAddress,
                    depositAmount,
                    m.toContractGasLimit,
                    m.depositCallData
                );
            }

            _sendToRecipient(_token, m.recipient, _amount - depositAmount);
            _emitCrosschainDepositDone(m, _amount, _amount, DataTypes.DepositStatus.Succeeded);
        }
        // always return true since swap failure is already handled in-place
        return IMessageReceiverApp.ExecutionStatus.Success;
    }

    // called on source chain for handling of bridge failures (bad liquidity, bad slippage, etc...)
    function executeMessageWithTransferRefund(
        address _token,
        uint256 _amount,
        bytes calldata _message,
        address // executor
    )
        external
        payable
        onlyMessageBus
        returns (IMessageReceiverApp.ExecutionStatus)
    {
        CelerDepositRequest memory m = abi.decode((_message), (CelerDepositRequest));
        _sendToRecipient(_token, m.recipient, _amount);

        switchEvent.emitCrosschainDepositRequest(
            m.id,
            bytes32(0),
            m.bridge,
            m.recipient,
            m.depositContract, // contract address for deposit
            m.toApprovalAddress, // the approval address for deposit
            m.srcToken,
            m.depositToken,
            m.srcAmount,
            m.estimatedDepositAmount,
            DataTypes.DepositStatus.Fallback
        );

        return IMessageReceiverApp.ExecutionStatus.Success;
    }

    // handler function required by MsgReceiverApp
    // called only if handleMessageWithTransfer above was reverted
    function executeMessageWithTransferFallback(
        address, // sender
        address _token, // token,
        uint256 _amount, // amount
        uint64 _srcChainId,
        bytes memory _message,
        address // executor
    )
        external
        payable
        onlyMessageBus
        returns (IMessageReceiverApp.ExecutionStatus)
    {
        CelerDepositRequest memory m = abi.decode((_message), (CelerDepositRequest));
        _sendToRecipient(_token, m.recipient, _amount);

        _emitCrosschainSwapDone(m, _amount, 0, DataTypes.SwapStatus.Fallback);
        // we can do in this app as the swap failures are already handled in executeMessageWithTransfer
        return IMessageReceiverApp.ExecutionStatus.Success;
    }

    function _sendToRecipient(
        address token,
        address recipient,
        uint256 amount
    )
        internal
    {
        if (IERC20(token).isETH()) {
            payable(recipient).transfer(amount);
        } else {
            IERC20(token).universalTransfer(recipient, amount);
        }
    }

    function transferToken(address token, uint256 amount, address recipient) external onlyOwner {
        IERC20(token).universalTransfer(recipient, amount);
    }

    function _emitCrosschainDepositDone(
        CelerDepositRequest memory m,
        uint256 srcAmount,
        uint256 dstAmount,
        DataTypes.DepositStatus status
    )
        internal
    {
        switchEvent.emitCrosschainDepositDone(m.id, m.bridge, m.recipient, m.depositContract, m.toApprovalAddress, m.bridgeToken, m.depositToken, srcAmount, dstAmount, status);
    }

    function _emitCrosschainSwapDone(
        CelerDepositRequest memory m,
        uint256 srcAmount,
        uint256 dstAmount,
        DataTypes.SwapStatus status
    )
        internal
    {
        switchEvent.emitCrosschainSwapDone(m.id, m.bridge, m.recipient, m.bridgeToken, m.depositToken, srcAmount, dstAmount, status);
    }
}

