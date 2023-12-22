// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {ERC20} from "./ERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IDefii} from "./IDefii.sol";
import {Instructions} from "./Instructions.sol";
import {RemoteMessaging} from "./RemoteMessaging.sol";
import {SupportedTokens} from "./SupportedTokens.sol";
import {FundsHolder} from "./FundsHolder.sol";
import {Notion} from "./Notion.sol";

abstract contract RemoteDefiiPrincipal is
    IDefii,
    Instructions,
    FundsHolder,
    RemoteMessaging,
    SupportedTokens,
    ERC20,
    Notion
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
        // do instructions
        IERC20(_notion).safeTransferFrom(msg.sender, address(this), amount);
        for (uint256 i = 0; i < instructions.length; i++) {
            if (instructions[i].type_ == InstructionType.BRIDGE) {
                _doBridge(
                    msg.sender,
                    account,
                    abi.decode(instructions[i].data, (BridgeInstruction))
                );
            } else if (instructions[i].type_ == InstructionType.SWAP_BRIDGE) {
                SwapBridgeInstruction memory instruction = abi.decode(
                    instructions[i].data,
                    (SwapBridgeInstruction)
                );
                _checkToken(instruction.tokenOut);
                _doSwapBridge(msg.sender, account, instruction);
            }
        }

        // return funds
        _returnFunds(msg.sender, account, _notion, 0);
    }

    function exit(
        uint256 shares,
        address recipient,
        Instruction[] calldata instructions
    ) external payable {
        _burn(msg.sender, shares);

        require(instructions.length == 1);
        require(instructions[0].type_ == InstructionType.REMOTE_MESSAGE);

        _sendMessage(
            instructions[0].data,
            _encodePayload(msg.sender, recipient, shares)
        );
    }

    function notion() external view returns (address) {
        return _notion;
    }

    function _processPayload(bytes calldata payload) internal override {
        (address sender, address recipient, uint256 shares) = _decodePayload(
            payload
        );
        _mint(address(this), shares);
        _returnFunds(sender, recipient, address(this), shares);
    }
}

