// SPDX-License-Identifier: SHIFT-1.0
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IDefii} from "./IDefii.sol";
import {IRemoteDefiiAgent} from "./IRemoteDefiiAgent.sol";
import {IRemoteDefiiPrincipal} from "./IRemoteDefiiPrincipal.sol";
import {OperatorMixin} from "./OperatorMixin.sol";
import {ExecutionSimulation} from "./ExecutionSimulation.sol";
import {Execution} from "./Execution.sol";
import {RemoteInstructions} from "./RemoteInstructions.sol";
import {RemoteCalls} from "./RemoteCalls.sol";
import {SupportedTokens} from "./SupportedTokens.sol";

abstract contract RemoteDefiiAgent is
    IRemoteDefiiAgent,
    RemoteInstructions,
    RemoteCalls,
    ExecutionSimulation,
    SupportedTokens,
    OperatorMixin
{
    using SafeERC20 for IERC20;

    uint256 internal _totalShares;

    event RemoteEnter(address indexed vault, uint256 indexed postionId);
    event RemoteExit(address indexed vault, uint256 indexed postionId);

    constructor(
        address swapRouter_,
        address operatorRegistry,
        uint256 remoteChainId_,
        ExecutionConstructorParams memory executionParams
    )
        RemoteInstructions(swapRouter_, remoteChainId_)
        Execution(executionParams)
        OperatorMixin(operatorRegistry)
    {}

    function remoteEnter(
        address vault,
        uint256 positionId,
        address owner,
        IDefii.Instruction[] calldata instructions
    ) external payable operatorCheckApproval(owner) {
        // instructions
        // [SWAP, SWAP, ..., SWAP, MIN_LIQUIDITY_DELTA, REMOTE_CALL]

        address[] memory tokens = supportedTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            _releaseToken(vault, positionId, owner, tokens[i], 0);
        }

        uint256 nInstructions = instructions.length;
        for (uint256 i = 0; i < nInstructions - 2; i++) {
            IDefii.SwapInstruction memory instruction = _decodeSwap(
                instructions[i]
            );
            _checkToken(instruction.tokenOut);
            _doSwap(instruction);
        }

        uint256 shares = _enter(
            _decodeMinLiquidityDelta(instructions[nInstructions - 2])
        );

        uint256 fee = _calculateFixedFeeAmount(shares);
        uint256 userShares = shares - fee;

        _totalShares += shares;
        positionBalance[address(0)][0][owner][address(this)] += fee;
        _startRemoteCall(
            abi.encodeWithSelector(
                IRemoteDefiiPrincipal.mintShares.selector,
                vault,
                positionId,
                userShares
            ),
            _decodeRemoteCall(instructions[nInstructions - 1])
        );

        for (uint256 i = 0; i < tokens.length; i++) {
            _holdToken(vault, positionId, owner, tokens[i], 0);
        }
        emit RemoteEnter(vault, positionId);
    }

    function startRemoteExit(
        address vault,
        uint256 positionId,
        address owner,
        IDefii.Instruction[] calldata instructions
    ) external payable operatorCheckApproval(owner) {
        // instructions
        // [MIN_TOKENS_DELTA, BRIDGE/SWAP_BRIDGE, BRIDGE/SWAP_BRIDGE, ...]

        IDefii.MinTokensDeltaInstruction
            memory minTokensDelta = _decodeMinTokensDelta(instructions[0]);

        uint256 shares = positionBalance[vault][positionId][owner][
            address(this)
        ];

        _exit(shares, minTokensDelta.tokens, minTokensDelta.deltas);
        positionBalance[vault][positionId][owner][address(this)] = 0;
        _totalShares -= shares;

        for (uint256 i = 1; i < instructions.length; i++) {
            if (instructions[i].type_ == IDefii.InstructionType.BRIDGE) {
                IDefii.BridgeInstruction
                    memory bridgeInstruction = _decodeBridge(instructions[i]);
                _checkToken(bridgeInstruction.token);
                _doBridge(vault, positionId, owner, bridgeInstruction);
            } else if (
                instructions[i].type_ == IDefii.InstructionType.SWAP_BRIDGE
            ) {
                IDefii.SwapBridgeInstruction
                    memory swapBridgeInstruction = _decodeSwapBridge(
                        instructions[i]
                    );
                _checkToken(swapBridgeInstruction.tokenOut);
                _doSwapBridge(vault, positionId, owner, swapBridgeInstruction);
            }
        }

        address[] memory tokens = supportedTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            _holdToken(vault, positionId, owner, tokens[i], 0);
        }
        emit RemoteExit(vault, positionId);
    }

    function reinvest(IDefii.Instruction[] calldata instructions) external {
        // instructions
        // [SWAP, SWAP, ..., SWAP, MIN_LIQUIDITY_DELTA]

        uint256 nInstructions = instructions.length;
        for (uint256 i = 0; i < nInstructions - 1; i++) {
            IDefii.SwapInstruction memory instruction = _decodeSwap(
                instructions[i]
            );
            IERC20(instruction.tokenIn).safeTransferFrom(
                msg.sender,
                address(this),
                instruction.amountIn
            );
            _checkToken(instruction.tokenIn);
            _checkToken(instruction.tokenOut);
            _doSwap(instruction);
        }

        uint256 shares = _enter(
            _decodeMinLiquidityDelta(instructions[nInstructions - 1])
        );
        uint256 fee = _calculatePerformanceFeeAmount(shares);

        positionBalance[address(0)][0][TREASURY][address(this)] += shares;
        _totalShares += fee;

        address[] memory tokens = supportedTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenBalance = IERC20(tokens[i]).balanceOf(address(this));
            if (tokenBalance > 0) {
                IERC20(tokens[i]).transfer(msg.sender, tokenBalance);
            }
        }
    }

    function increaseShareBalance(
        address vault,
        uint256 positionId,
        address owner,
        uint256 shares
    ) external remoteFn {
        positionBalance[vault][positionId][owner][address(this)] += shares;
    }

    function remoteWithdrawLiquidity() external {
        uint256 shares = positionBalance[address(0)][0][msg.sender][
            address(this)
        ];
        uint256 liquidity = _toLiquidity(shares);
        positionBalance[address(0)][0][msg.sender][address(this)] = 0;
        _totalShares -= shares;

        _withdrawLiquidity(msg.sender, liquidity);
    }

    function withdrawFundsAfterEmergencyExit(
        address vault,
        uint256 positionId,
        address owner
    ) external {
        uint256 shares = positionBalance[vault][positionId][owner][
            address(this)
        ];
        uint256 totalShares_ = totalShares();
        positionBalance[vault][positionId][owner][address(this)] = 0;

        _withdrawAfterEmergencyExit(
            owner,
            shares,
            totalShares_,
            supportedTokens()
        );
    }

    // solhint-disable-next-line named-return-values
    function totalShares() public view override returns (uint256) {
        return _totalShares;
    }
}

