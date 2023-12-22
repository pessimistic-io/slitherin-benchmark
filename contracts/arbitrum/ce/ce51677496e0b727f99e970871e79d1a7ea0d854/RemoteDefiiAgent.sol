// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IDefii} from "./IDefii.sol";
import {IRemoteDefiiAgent} from "./IRemoteDefiiAgent.sol";
import {IRemoteDefiiPrincipal} from "./IRemoteDefiiPrincipal.sol";
import {OperatorMixin} from "./OperatorMixin.sol";
import {ExecutionSimulation} from "./ExecutionSimulation.sol";
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
    mapping(address vault => mapping(uint256 positionId => uint256))
        public shareBalance;

    event RemoteEnter(address indexed vault, uint256 indexed postionId);
    event RemoteExit(address indexed vault, uint256 indexed postionId);

    constructor(
        address swapRouter_,
        address operatorRegistry,
        uint256 remoteChainId_,
        ExecutionConstructorParams memory executionParams
    )
        RemoteInstructions(swapRouter_, remoteChainId_)
        ExecutionSimulation(executionParams)
        OperatorMixin(operatorRegistry)
    {
        fundsOwner[TREASURY][0] = TREASURY;
    }

    function remoteEnter(
        address vault,
        uint256 positionId,
        IDefii.Instruction[] calldata instructions
    ) external payable operatorCheckApproval(fundsOwner[vault][positionId]) {
        // instructions
        // [SWAP, SWAP, ..., SWAP, MIN_LIQUIDITY_DELTA, REMOTE_CALL]

        address[] memory tokens = supportedTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            _releaseToken(vault, positionId, tokens[i], 0);
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
        shareBalance[TREASURY][0] += fee;
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
            _holdToken(vault, positionId, tokens[i], 0);
        }
        emit RemoteEnter(vault, positionId);
    }

    function remoteExit(
        address vault,
        uint256 positionId,
        uint256 shares,
        IDefii.Instruction[] calldata instructions
    ) external payable {
        address owner = fundsOwner[vault][positionId];
        _operatorCheckApproval(owner);

        _exit(shares);
        shareBalance[vault][positionId] -= shares;
        _totalShares -= shares;

        for (uint256 i = 0; i < instructions.length; i++) {
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
            _holdToken(vault, positionId, tokens[i], 0);
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

        shareBalance[TREASURY][0] += fee;
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
        uint256 shares
    ) external remoteFn {
        shareBalance[vault][positionId] += shares;
    }

    function withdrawLiquidity(address to, uint256 shares) external remoteFn {
        uint256 liquidity = _toLiquidity(shares);
        _totalShares -= shares;

        _withdrawLiquidityLogic(to, liquidity);
    }

    function withdrawFundsAfterEmergencyExit(
        address vault,
        uint256 positionId
    ) external {
        uint256 shares = shareBalance[vault][positionId];
        uint256 totalShares_ = totalShares();
        shareBalance[vault][positionId] -= shares;

        _withdrawAfterEmergencyExit(
            fundsOwner[vault][positionId],
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

