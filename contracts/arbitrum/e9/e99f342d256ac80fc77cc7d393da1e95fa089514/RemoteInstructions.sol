// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IBridgeAdapter} from "./IBridgeAdapter.sol";
import {ITokenWithMessageReceiver} from "./ITokenWithMessageReceiver.sol";

import {IDefii} from "./IDefii.sol";
import {LocalInstructions} from "./LocalInstructions.sol";
import {FundsHolder} from "./FundsHolder.sol";

contract RemoteInstructions is LocalInstructions, ITokenWithMessageReceiver {
    using SafeERC20 for IERC20;

    uint256 public immutable remoteChainId;
    FundsHolder public immutable fundsHolder;

    mapping(address vault => mapping(uint256 positionId => address fundsOwner))
        public fundsOwner;
    mapping(address vault => mapping(uint256 positionId => mapping(address token => uint256 balance)))
        private _funds;

    event Bridge(
        address token,
        address bridgeAdapter,
        uint256 amount,
        uint256 chainId
    );

    constructor(
        address swapRouter_,
        uint256 remoteChainId_
    ) LocalInstructions(swapRouter_) {
        remoteChainId = remoteChainId_;
        fundsHolder = new FundsHolder();
    }

    function receiveTokenWithMessage(
        address token,
        uint256 amount,
        bytes calldata message
    ) external {
        //TODO: everyone can rewrite owner rigth now
        (address vault, uint256 positionId, address owner) = abi.decode(
            message,
            (address, uint256, address)
        );

        fundsOwner[vault][positionId] = owner;
        IERC20(token).safeTransfer(address(fundsHolder), amount);
        _funds[vault][positionId][token] += amount;
    }

    function withdrawFunds(
        address vault,
        uint256 positionId,
        address token,
        uint256 amount
    ) external {
        address owner = fundsOwner[vault][positionId];
        require(msg.sender == owner);

        _funds[vault][positionId][token] -= amount;
        fundsHolder.transferTokenTo(token, amount, owner);
    }

    function _releaseToken(
        address vault,
        uint256 positionId,
        address token,
        uint256 amount
    ) internal {
        fundsHolder.transferTokenTo(token, amount, address(this));
        _funds[vault][positionId][token] -= amount;
    }

    function _holdToken(
        address vault,
        uint256 positionId,
        address token,
        uint256 amount
    ) internal {
        if (amount == 0) {
            amount = IERC20(token).balanceOf(address(this));
        }
        if (amount > 0) {
            IERC20(token).safeTransfer(address(fundsHolder), amount);
            _funds[vault][positionId][token] += amount;
        }
    }

    function _doBridge(
        address vault,
        uint256 positionId,
        address owner,
        IDefii.BridgeInstruction memory bridgeInstruction
    ) internal {
        IERC20(bridgeInstruction.token).safeTransfer(
            bridgeInstruction.bridgeAdapter,
            bridgeInstruction.amount
        );

        IBridgeAdapter(bridgeInstruction.bridgeAdapter).sendTokenWithMessage{
            value: bridgeInstruction.value
        }(
            IBridgeAdapter.Token({
                address_: bridgeInstruction.token,
                amount: bridgeInstruction.amount,
                slippage: bridgeInstruction.slippage
            }),
            IBridgeAdapter.Message({
                dstChainId: remoteChainId,
                content: abi.encode(vault, positionId, owner),
                bridgeParams: bridgeInstruction.bridgeParams
            })
        );

        emit Bridge(
            bridgeInstruction.token,
            bridgeInstruction.bridgeAdapter,
            bridgeInstruction.amount,
            remoteChainId
        );
    }

    function _doSwapBridge(
        address vault,
        uint256 positionId,
        address owner,
        IDefii.SwapBridgeInstruction memory swapBridgeInstruction
    ) internal {
        _doBridge(
            vault,
            positionId,
            owner,
            IDefii.BridgeInstruction({
                token: swapBridgeInstruction.tokenOut,
                amount: _doSwap(
                    IDefii.SwapInstruction({
                        tokenIn: swapBridgeInstruction.tokenIn,
                        tokenOut: swapBridgeInstruction.tokenOut,
                        amountIn: swapBridgeInstruction.amountIn,
                        minAmountOut: swapBridgeInstruction.minAmountOut,
                        routerCalldata: swapBridgeInstruction.routerCalldata
                    })
                ),
                slippage: swapBridgeInstruction.slippage,
                bridgeAdapter: swapBridgeInstruction.bridgeAdapter,
                value: swapBridgeInstruction.value,
                bridgeParams: swapBridgeInstruction.bridgeParams
            })
        );
    }

    function _decodeBridge(
        IDefii.Instruction memory instruction
    ) internal pure returns (IDefii.BridgeInstruction memory) {
        _checkInstructionType(instruction, IDefii.InstructionType.BRIDGE);
        return abi.decode(instruction.data, (IDefii.BridgeInstruction));
    }

    function _decodeSwapBridge(
        IDefii.Instruction memory instruction
    ) internal pure returns (IDefii.SwapBridgeInstruction memory) {
        _checkInstructionType(instruction, IDefii.InstructionType.SWAP_BRIDGE);
        return abi.decode(instruction.data, (IDefii.SwapBridgeInstruction));
    }

    function _decodeRemoteCall(
        IDefii.Instruction calldata instruction
    ) internal pure returns (bytes calldata) {
        _checkInstructionType(instruction, IDefii.InstructionType.REMOTE_CALL);
        return instruction.data;
    }
}

