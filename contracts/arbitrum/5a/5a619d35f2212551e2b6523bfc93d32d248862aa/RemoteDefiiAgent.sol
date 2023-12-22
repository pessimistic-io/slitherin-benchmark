// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IDefii} from "./IDefii.sol";
import {OperatorMixin} from "./OperatorMixin.sol";
import {ExitSimulation} from "./ExitSimulation.sol";
import {Instructions} from "./Instructions.sol";
import {SharedLiquidity} from "./SharedLiquidity.sol";
import {RemoteMessaging} from "./RemoteMessaging.sol";
import {SupportedTokens} from "./SupportedTokens.sol";
import {Notion} from "./Notion.sol";
import {FundsHolder} from "./FundsHolder.sol";

abstract contract RemoteDefiiAgent is
    Instructions,
    FundsHolder,
    RemoteMessaging,
    ExitSimulation,
    SupportedTokens,
    OperatorMixin,
    Notion
{
    using SafeERC20 for IERC20;

    uint256 internal _totalShares;
    mapping(address => mapping(address => uint256)) public userShares;

    constructor(
        address swapRouter_,
        uint256 remoteChainId_,
        address notion_
    ) Instructions(swapRouter_, remoteChainId_) Notion(notion_) {}

    function remoteEnter(
        address vault,
        address user,
        IDefii.Instruction[] calldata instructions
    ) external payable operatorCheckApproval(user) {
        _useFunds(vault, user, _notion);
        uint256 nInstructions = instructions.length;
        for (uint256 i = 0; i < nInstructions - 1; i++) {
            IDefii.SwapInstruction memory instruction = abi.decode(
                instructions[i].data,
                (IDefii.SwapInstruction)
            );
            _checkToken(instruction.tokenOut);
            _doSwap(instruction);
        }

        // enter
        uint256 shares = _enter();
        _sendMessage(
            instructions[nInstructions - 1].data,
            abi.encode(vault, user, shares)
        );
        _storeFunds(vault, user, _notion);
    }

    function remoteExit(
        address withdrawalAddress,
        address owner,
        uint256 shares,
        IDefii.Instruction[] calldata instructions
    ) external payable operatorCheckApproval(owner) {
        userShares[withdrawalAddress][owner] -= shares;
        _exit(shares);

        // instructions
        for (uint256 i = 0; i < instructions.length; i++) {
            if (instructions[i].type_ == IDefii.InstructionType.BRIDGE) {
                IDefii.BridgeInstruction memory bridgeInstruction = abi.decode(
                    instructions[i].data,
                    (IDefii.BridgeInstruction)
                );
                _doBridge(withdrawalAddress, owner, bridgeInstruction);
            } else if (
                instructions[i].type_ == IDefii.InstructionType.SWAP_BRIDGE
            ) {
                IDefii.SwapBridgeInstruction memory swapBridgeInstruction = abi
                    .decode(
                        instructions[i].data,
                        (IDefii.SwapBridgeInstruction)
                    );
                _doSwapBridge(withdrawalAddress, owner, swapBridgeInstruction);
            }
        }
    }

    function totalShares() public view override returns (uint256) {
        return _totalShares;
    }

    function _processPayload(bytes calldata payload) internal override {
        (address withdrawalAddress, address owner, uint256 shares) = abi.decode(
            payload,
            (address, address, uint256)
        );
        userShares[withdrawalAddress][owner] += shares;
    }

    function _issueShares(uint256 shares) internal override {
        _totalShares += shares;
    }

    function _withdrawShares(uint256 shares) internal override {
        _totalShares -= shares;
    }
}

