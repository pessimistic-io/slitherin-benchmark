// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IDefii} from "./IDefii.sol";
import {OperatorMixin} from "./OperatorMixin.sol";
import {ExecutionSimulation} from "./ExecutionSimulation.sol";
import {RemoteInstructions} from "./RemoteInstructions.sol";
import {SharedLiquidity} from "./SharedLiquidity.sol";
import {RemoteCalls} from "./RemoteCalls.sol";
import {SupportedTokens} from "./SupportedTokens.sol";
import {Notion} from "./Notion.sol";

import {RemoteDefiiPrincipal} from "./RemoteDefiiPrincipal.sol";

abstract contract RemoteDefiiAgent is
    RemoteInstructions,
    RemoteCalls,
    ExecutionSimulation,
    SupportedTokens,
    OperatorMixin
{
    using SafeERC20 for IERC20;

    event RemoteEnter(address indexed vault, uint256 indexed postionId);
    event RemoteExit(address indexed vault, uint256 indexed postionId);

    uint256 internal _totalShares;
    mapping(address vault => mapping(uint256 positionId => uint256))
        public userShares;

    constructor(
        address swapRouter_,
        uint256 remoteChainId_,
        ExecutionConstructorParams memory executionParams
    )
        RemoteInstructions(swapRouter_, remoteChainId_)
        ExecutionSimulation(executionParams)
    {
        fundsOwner[address(0)][0] = msg.sender;
    }

    function remoteEnter(
        address vault,
        uint256 positionId,
        IDefii.Instruction[] calldata instructions
    ) external payable operatorCheckApproval(fundsOwner[vault][positionId]) {
        // instructions
        // [SWAP, SWAP, ..., SWAP, MIN_LIQUIDITY_DELTA, REMOTE_CALL]

        address[] memory tokens = _supportedTokens();
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
        _totalShares += shares;

        _startRemoteCall(
            abi.encodeWithSelector(
                RemoteDefiiPrincipal.mintShares.selector,
                vault,
                positionId,
                shares
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

        userShares[vault][positionId] -= shares;
        _exit(shares);

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

        address[] memory tokens = _supportedTokens();
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
            _checkToken(instruction.tokenOut);
            _doSwap(instruction);
        }

        uint256 shares = _enter(
            _decodeMinLiquidityDelta(instructions[nInstructions - 1])
        );
        uint256 feeAmount = _calculatePerformanceFeeAmount(shares);

        userShares[address(0)][0] += feeAmount;
        _totalShares += feeAmount;

        address[] memory tokens = _supportedTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenBalance = IERC20(tokens[i]).balanceOf(address(this));
            if (tokenBalance > 0) {
                IERC20(tokens[i]).transfer(msg.sender, tokenBalance);
            }
        }
    }

    function totalShares() public view override returns (uint256) {
        return _totalShares;
    }

    function increaseUserShares(
        address vault,
        uint256 positionId,
        uint256 shares
    ) external remoteFn {
        userShares[vault][positionId] += shares;
    }

    function withdrawLiquidity(address to, uint256 shares) external remoteFn {
        uint256 liquidity = _toLiquidity(shares);
        _totalShares -= shares;

        _withdrawLiquidityLogic(to, liquidity);
    }

    function _withdrawShares(uint256 shares) internal override {
        _totalShares -= shares;
    }
}

