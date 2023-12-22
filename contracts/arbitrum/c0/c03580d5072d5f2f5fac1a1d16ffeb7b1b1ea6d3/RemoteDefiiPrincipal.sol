// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {ERC20} from "./ERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IDefii} from "./IDefii.sol";
import {OperatorMixin} from "./OperatorMixin.sol";
import {IFundsCollector} from "./IFundsCollector.sol";
import {Instructions} from "./Instructions.sol";
import {RemoteCalls} from "./RemoteCalls.sol";
import {SupportedTokens} from "./SupportedTokens.sol";
import {Notion} from "./Notion.sol";
import {Funds} from "./Funds.sol";

import {RemoteDefiiAgent} from "./RemoteDefiiAgent.sol";

abstract contract RemoteDefiiPrincipal is
    IDefii,
    Instructions,
    RemoteCalls,
    SupportedTokens,
    ERC20,
    Notion,
    Funds,
    OperatorMixin
{
    using SafeERC20 for IERC20;

    constructor(
        address swapRouter_,
        uint256 remoteChainId_,
        address notion_,
        string memory name
    )
        Notion(notion_)
        Instructions(swapRouter_, remoteChainId_)
        ERC20(name, "DLP")
    {}

    function enter(
        uint256 amount,
        address account,
        Instruction[] calldata instructions
    ) external payable {
        IERC20(_notion).safeTransferFrom(msg.sender, address(this), amount);
        for (uint256 i = 0; i < instructions.length; i++) {
            if (instructions[i].type_ == InstructionType.BRIDGE) {
                _doBridge(msg.sender, account, _decodeBridge(instructions[i]));
            } else if (instructions[i].type_ == InstructionType.SWAP_BRIDGE) {
                SwapBridgeInstruction memory instruction = _decodeSwapBridge(
                    instructions[i]
                );
                _checkToken(instruction.tokenOut);
                _doSwapBridge(msg.sender, account, instruction);
            }
        }
        _returnFunds(msg.sender, account, _notion, 0);
    }

    function exit(
        uint256 shares,
        address recipient,
        Instruction[] calldata instructions
    ) external payable {
        _burn(msg.sender, shares);

        require(instructions[0].type_ == InstructionType.REMOTE_CALL);
        _startRemoteCall(
            abi.encodeWithSelector(
                RemoteDefiiAgent.increaseUserShares.selector,
                msg.sender,
                recipient,
                shares
            ),
            instructions[0].data
        );
    }

    function notion() external view returns (address) {
        return _notion;
    }

    function mintShares(
        address withdrawalAddress,
        address owner,
        uint256 shares
    ) external remoteFn {
        _mint(address(this), shares);
        _returnFunds(withdrawalAddress, owner, address(this), shares);
    }

    function remoteExit(
        address withdrawalAddress,
        address owner,
        IDefii.Instruction[] calldata instructions
    ) external payable operatorCheckApproval(owner) {
        // instructions
        // [SWAP, SWAP, ..., SWAP]

        address[] memory tokens = _supportedTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            _useToken(withdrawalAddress, owner, tokens[i]);
        }

        // instructions
        uint256 nInstructions = instructions.length;
        uint256 notionAmount = 0;
        for (uint256 i = 0; i < nInstructions - 2; i++) {
            IDefii.SwapInstruction memory instruction = _decodeSwap(
                instructions[i]
            );
            _checkToken(instruction.tokenIn);
            _checkNotion(instruction.tokenOut);
            notionAmount += _doSwap(instruction);
        }
        _returnFunds(withdrawalAddress, owner, _notion, notionAmount);

        for (uint256 i = 0; i < tokens.length; i++) {
            _storeToken(withdrawalAddress, owner, tokens[i]);
        }
    }

    function withdrawLiquidity(
        address recipieint,
        uint256 shares,
        Instruction[] calldata instructions
    ) external payable {
        _burn(msg.sender, shares);

        require(instructions[0].type_ == InstructionType.REMOTE_CALL);
        _startRemoteCall(
            abi.encodeWithSelector(
                RemoteDefiiAgent.withdrawLiquidity.selector,
                recipieint,
                shares
            ),
            instructions[0].data
        );
    }
}

