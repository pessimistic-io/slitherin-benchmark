// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IDefii} from "./IDefii.sol";
import {OperatorMixin} from "./OperatorMixin.sol";
import {ExecutionSimulation} from "./ExecutionSimulation.sol";
import {Instructions} from "./Instructions.sol";
import {SharedLiquidity} from "./SharedLiquidity.sol";
import {RemoteCalls} from "./RemoteCalls.sol";
import {SupportedTokens} from "./SupportedTokens.sol";
import {Funds} from "./Funds.sol";
import {Notion} from "./Notion.sol";

import {RemoteDefiiPrincipal} from "./RemoteDefiiPrincipal.sol";

abstract contract RemoteDefiiAgent is
    Instructions,
    Funds,
    RemoteCalls,
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
        // instructions
        // [SWAP, SWAP, ..., SWAP, MIN_LIQUIDITY_DELTA, REMOTE_CALL]

        address[] memory tokens = _supportedTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            _useToken(vault, user, tokens[i]);
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
                user,
                shares
            ),
            instructions[nInstructions - 1].data
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
                _doBridge(
                    withdrawalAddress,
                    owner,
                    _decodeBridge(instructions[i])
                );
            } else if (
                instructions[i].type_ == IDefii.InstructionType.SWAP_BRIDGE
            ) {
                IDefii.SwapBridgeInstruction
                    memory swapBridgeInstruction = _decodeSwapBridge(
                        instructions[i]
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

        _totalShares += shares;
        userShares[address(0)][treasury] += feeAmount;
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
        address withdrawalAddress,
        address owner,
        uint256 shares
    ) external remoteFn {
        userShares[withdrawalAddress][owner] += shares;
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

