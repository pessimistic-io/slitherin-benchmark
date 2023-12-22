// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {ERC20} from "./ERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IDefii} from "./IDefii.sol";
import {Execution} from "./Execution.sol";
import {ExecutionSimulation} from "./ExecutionSimulation.sol";
import {LocalInstructions} from "./Instructions.sol";
import {SharedLiquidity} from "./SharedLiquidity.sol";
import {Notion} from "./Notion.sol";
import {SupportedTokens} from "./SupportedTokens.sol";

abstract contract LocalDefii is
    Notion,
    IDefii,
    ExecutionSimulation,
    LocalInstructions,
    SupportedTokens,
    ERC20
{
    using SafeERC20 for IERC20;

    constructor(
        address swapRouter_,
        address notion_,
        string memory name,
        ExecutionConstructorParams memory executionParams
    )
        LocalInstructions(swapRouter_)
        Notion(notion_)
        ERC20(name, "DLP")
        ExecutionSimulation(executionParams)
    {}

    function enter(
        uint256 amount,
        address recipient,
        Instruction[] calldata instructions
    ) external payable {
        // do instructions
        IERC20(_notion).safeTransferFrom(msg.sender, address(this), amount);
        for (uint256 i = 0; i < instructions.length; i++) {
            IDefii.SwapInstruction memory instruction = abi.decode(
                instructions[i].data,
                (IDefii.SwapInstruction)
            );
            _checkNotion(instruction.tokenIn);
            _checkToken(instruction.tokenOut);
            _doSwap(instruction);
        }

        uint256 shares = _enter(true);
        _returnFunds(msg.sender, recipient, address(this), shares);

        // return funds
        _returnFunds(msg.sender, recipient, _notion, 0);

        address[] memory tokens = _supportedTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            _returnFunds(msg.sender, recipient, tokens[i], 0);
        }
    }

    function exit(
        uint256 shares,
        address recipient,
        Instruction[] calldata instructions
    ) external payable {
        _exit(shares);

        // return funds
        for (uint256 i = 0; i < instructions.length; i++) {
            IDefii.SwapInstruction memory instruction = abi.decode(
                instructions[i].data,
                (IDefii.SwapInstruction)
            );
            _checkToken(instruction.tokenIn);
            _checkNotion(instruction.tokenOut);
            _returnFunds(
                msg.sender,
                recipient,
                instruction.tokenOut,
                _doSwap(instruction)
            );
        }

        address[] memory tokens = _supportedTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            _returnFunds(msg.sender, recipient, tokens[i], 0);
        }
    }

    function reinvest() external {
        _reinvest();
    }

    function _accrueFee(
        uint256 feeAmount,
        address recipient
    ) internal override {
        _mint(recipient, feeAmount);
    }

    function totalShares() public view override returns (uint256) {
        return totalSupply();
    }

    function notion() external view returns (address) {
        return _notion;
    }

    function _issueShares(uint256 shares) internal override {
        _mint(address(this), shares);
    }

    function _withdrawShares(uint256 shares) internal override {
        _burn(msg.sender, shares);
    }
}

