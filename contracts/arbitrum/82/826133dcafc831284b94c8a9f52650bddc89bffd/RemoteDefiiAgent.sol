// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IDefii} from "./IDefii.sol";
import {OperatorMixin} from "./OperatorMixin.sol";
import {ExecutionSimulation} from "./ExecutionSimulation.sol";
import {Instructions} from "./Instructions.sol";
import {SharedLiquidity} from "./SharedLiquidity.sol";
import {RemoteMessaging} from "./RemoteMessaging.sol";
import {SupportedTokens} from "./SupportedTokens.sol";
import {Funds} from "./Funds.sol";

abstract contract RemoteDefiiAgent is
    Instructions,
    Funds,
    RemoteMessaging,
    ExecutionSimulation,
    SupportedTokens,
    OperatorMixin
{
    using SafeERC20 for IERC20;

    uint256 internal _totalShares;
    mapping(address => mapping(address => uint256)) public userShares;

    constructor(
        address swapRouter_,
        uint256 remoteChainId_,
        ExecutionConstructorParams memory executionParams
    )
        Instructions(swapRouter_, remoteChainId_)
        ExecutionSimulation(executionParams)
    {}

    function remoteEnter(
        address vault,
        address user,
        IDefii.Instruction[] calldata instructions
    ) external payable operatorCheckApproval(user) {
        address[] memory tokens = _supportedTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            _useToken(vault, user, tokens[i]);
        }

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
        uint256 shares = _enter(true);
        _sendMessage(
            instructions[nInstructions - 1].data,
            abi.encode(vault, user, shares)
        );

        for (uint256 i = 0; i < tokens.length; i++) {
            _storeToken(vault, user, tokens[i]);
        }
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
                _checkToken(swapBridgeInstruction.tokenOut);
                _doSwapBridge(withdrawalAddress, owner, swapBridgeInstruction);
            }
        }

        address[] memory tokens = _supportedTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            _storeToken(withdrawalAddress, owner, tokens[i]);
        }
    }

    function remoteReinvest() public {
        uint256 shares = _reinvest();
        _totalShares += shares;
    }

    function _accrueFee(
        uint256 feeAmount,
        address recipient
    ) internal override {
        userShares[address(0)][recipient] += feeAmount;
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

