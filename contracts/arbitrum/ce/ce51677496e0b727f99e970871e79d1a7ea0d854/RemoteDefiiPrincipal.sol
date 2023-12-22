// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";
import {ERC20} from "./ERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IDefii} from "./IDefii.sol";
import {IVault} from "./IVault.sol";
import {IRemoteDefiiAgent} from "./IRemoteDefiiAgent.sol";
import {IRemoteDefiiPrincipal} from "./IRemoteDefiiPrincipal.sol";
import {OperatorMixin} from "./OperatorMixin.sol";
import {RemoteInstructions} from "./RemoteInstructions.sol";
import {RemoteCalls} from "./RemoteCalls.sol";
import {SupportedTokens} from "./SupportedTokens.sol";
import {Notion} from "./Notion.sol";

abstract contract RemoteDefiiPrincipal is
    IDefii,
    IRemoteDefiiPrincipal,
    RemoteInstructions,
    RemoteCalls,
    SupportedTokens,
    ERC20,
    Notion,
    OperatorMixin
{
    using SafeERC20 for IERC20;

    constructor(
        address swapRouter_,
        address operatorRegistry,
        uint256 remoteChainId_,
        address notion_,
        string memory name
    )
        Notion(notion_)
        OperatorMixin(operatorRegistry)
        RemoteInstructions(swapRouter_, remoteChainId_)
        ERC20(name, "DLP")
    {}

    function enter(
        uint256 amount,
        uint256 positionId,
        Instruction[] calldata instructions
    ) external payable {
        IERC20(NOTION).safeTransferFrom(msg.sender, address(this), amount);

        address owner = IVault(msg.sender).ownerOf(positionId);
        for (uint256 i = 0; i < instructions.length; i++) {
            if (instructions[i].type_ == InstructionType.BRIDGE) {
                BridgeInstruction memory instruction = _decodeBridge(
                    instructions[i]
                );
                _checkNotion(instruction.token);
                _doBridge(msg.sender, positionId, owner, instruction);
            } else if (instructions[i].type_ == InstructionType.SWAP_BRIDGE) {
                SwapBridgeInstruction memory instruction = _decodeSwapBridge(
                    instructions[i]
                );
                _checkToken(instruction.tokenOut);
                _doSwapBridge(msg.sender, positionId, owner, instruction);
            }
        }

        _returnAllFunds(msg.sender, positionId, NOTION);
    }

    function exit(
        uint256 shares,
        uint256 positionId,
        Instruction[] calldata instructions
    ) external payable {
        _burn(msg.sender, shares);

        _startRemoteCall(
            abi.encodeWithSelector(
                IRemoteDefiiAgent.increaseShareBalance.selector,
                msg.sender,
                positionId,
                shares
            ),
            _decodeRemoteCall(instructions[0])
        );
    }

    function mintShares(
        address vault,
        uint256 positionId,
        uint256 shares
    ) external remoteFn {
        _mint(vault, shares);
        IVault(vault).enterCallback(positionId, shares);
    }

    function remoteExit(
        address vault,
        uint256 positionId,
        IDefii.Instruction[] calldata instructions
    ) external payable operatorCheckApproval(fundsOwner[vault][positionId]) {
        // instructions
        // [SWAP, SWAP, ..., SWAP]
        uint256 nInstructions = instructions.length;
        for (uint256 i = 0; i < nInstructions; i++) {
            IDefii.SwapInstruction memory instruction = _decodeSwap(
                instructions[i]
            );
            _checkToken(instruction.tokenIn);
            _checkNotion(instruction.tokenOut);
            _releaseToken(
                vault,
                positionId,
                instruction.tokenIn,
                instruction.amountIn
            );
            _doSwap(instruction);
        }
        _returnAllFunds(vault, positionId, NOTION);
        IVault(vault).exitCallback(positionId);
    }

    function withdrawLiquidity(
        address recipient,
        uint256 shares,
        Instruction[] calldata instructions
    ) external payable {
        _burn(msg.sender, shares);

        _startRemoteCall(
            abi.encodeWithSelector(
                IRemoteDefiiAgent.withdrawLiquidity.selector,
                recipient,
                shares
            ),
            _decodeRemoteCall(instructions[0])
        );
    }

    // solhint-disable-next-line named-return-values
    function notion() external view returns (address) {
        return NOTION;
    }

    /// @inheritdoc IDefii
    // solhint-disable-next-line named-return-values
    function defiiType() external pure returns (Type) {
        return Type.REMOTE;
    }
}

