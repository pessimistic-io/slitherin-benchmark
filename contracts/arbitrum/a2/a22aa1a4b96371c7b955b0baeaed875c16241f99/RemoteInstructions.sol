// SPDX-License-Identifier: SHIFT-1.0
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IBridgeAdapter} from "./IBridgeAdapter.sol";
import {ITokenWithMessageReceiver} from "./ITokenWithMessageReceiver.sol";

import {IDefii} from "./IDefii.sol";
import {LocalInstructions} from "./LocalInstructions.sol";
import {FundsHolder} from "./FundsHolder.sol";

contract RemoteInstructions is LocalInstructions, ITokenWithMessageReceiver {
    using SafeERC20 for IERC20;

    uint256 public immutable REMOTE_CHAIN_ID;
    FundsHolder public immutable FUNDS_HOLDER;

    mapping(address vault => mapping(uint256 positionId => mapping(address owner => mapping(address token => uint256 balance))))
        public positionBalance;

    event Bridge(
        address token,
        address bridgeAdapter,
        uint256 amount,
        uint256 chainId,
        bytes32 traceId
    );

    constructor(
        address swapRouter_,
        uint256 remoteChainId
    ) LocalInstructions(swapRouter_) {
        REMOTE_CHAIN_ID = remoteChainId;
        FUNDS_HOLDER = new FundsHolder();
    }

    function receiveTokenWithMessage(
        address token,
        uint256 amount,
        bytes calldata message
    ) external {
        (address vault, uint256 positionId, address owner) = abi.decode(
            message,
            (address, uint256, address)
        );

        IERC20(token).safeTransferFrom(
            msg.sender,
            address(FUNDS_HOLDER),
            amount
        );
        positionBalance[vault][positionId][owner][token] += amount;
    }

    function withdrawFunds(
        address vault,
        uint256 positionId,
        address token,
        uint256 amount
    ) external {
        positionBalance[vault][positionId][msg.sender][token] -= amount;
        FUNDS_HOLDER.transferTokenTo(token, amount, msg.sender);
    }

    function _releaseToken(
        address vault,
        uint256 positionId,
        address owner,
        address token,
        uint256 amount
    ) internal {
        if (amount == 0) {
            amount = positionBalance[vault][positionId][owner][token];
        }

        if (amount > 0) {
            positionBalance[vault][positionId][owner][token] -= amount;
            FUNDS_HOLDER.transferTokenTo(token, amount, address(this));
        }
    }

    function _holdToken(
        address vault,
        uint256 positionId,
        address owner,
        address token,
        uint256 amount
    ) internal {
        if (amount == 0) {
            amount = IERC20(token).balanceOf(address(this));
        }
        if (amount > 0) {
            IERC20(token).safeTransfer(address(FUNDS_HOLDER), amount);
            positionBalance[vault][positionId][owner][token] += amount;
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

        bytes32 traceId = IBridgeAdapter(bridgeInstruction.bridgeAdapter)
            .sendTokenWithMessage{value: bridgeInstruction.value}(
            IBridgeAdapter.Token({
                address_: bridgeInstruction.token,
                amount: bridgeInstruction.amount,
                slippage: bridgeInstruction.slippage
            }),
            IBridgeAdapter.Message({
                dstChainId: REMOTE_CHAIN_ID,
                content: abi.encode(vault, positionId, owner),
                bridgeParams: bridgeInstruction.bridgeParams
            })
        );

        emit Bridge(
            bridgeInstruction.token,
            bridgeInstruction.bridgeAdapter,
            bridgeInstruction.amount,
            REMOTE_CHAIN_ID,
            traceId
        );
    }

    function _doSwapBridge(
        address vault,
        uint256 positionId,
        address owner,
        IDefii.SwapBridgeInstruction memory swapBridgeInstruction
    ) internal {
        _doSwap(
            IDefii.SwapInstruction({
                tokenIn: swapBridgeInstruction.tokenIn,
                tokenOut: swapBridgeInstruction.tokenOut,
                amountIn: swapBridgeInstruction.amountIn,
                minAmountOut: swapBridgeInstruction.minAmountOut,
                routerCalldata: swapBridgeInstruction.routerCalldata
            })
        );
        _doBridge(
            vault,
            positionId,
            owner,
            IDefii.BridgeInstruction({
                token: swapBridgeInstruction.tokenOut,
                amount: IERC20(swapBridgeInstruction.tokenOut).balanceOf(
                    address(this)
                ),
                slippage: swapBridgeInstruction.slippage,
                bridgeAdapter: swapBridgeInstruction.bridgeAdapter,
                value: swapBridgeInstruction.value,
                bridgeParams: swapBridgeInstruction.bridgeParams
            })
        );
    }

    /* solhint-disable named-return-values */
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

