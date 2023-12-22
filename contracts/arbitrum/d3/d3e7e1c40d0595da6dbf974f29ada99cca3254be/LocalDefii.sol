// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {ERC20} from "./ERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IDefii} from "./IDefii.sol";
import {IVault} from "./IVault.sol";
import {Execution} from "./Execution.sol";
import {ExecutionSimulation} from "./ExecutionSimulation.sol";
import {LocalInstructions} from "./LocalInstructions.sol";
import {SharedLiquidity} from "./SharedLiquidity.sol";
import {Notion} from "./Notion.sol";
import {SupportedTokens} from "./SupportedTokens.sol";

abstract contract LocalDefii is
    Notion,
    SupportedTokens,
    IDefii,
    ExecutionSimulation,
    LocalInstructions,
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
        uint256 positionId,
        Instruction[] calldata instructions
    ) external payable {
        // instructions
        // [SWAP, SWAP, ..., SWAP, MIN_LIQUIDITY_DELTA]

        IERC20(_notion).safeTransferFrom(msg.sender, address(this), amount);

        uint256 n = instructions.length;
        for (uint256 i = 0; i < n - 1; i++) {
            SwapInstruction memory instruction = _decodeSwap(instructions[i]);
            _checkNotion(instruction.tokenIn);
            _checkToken(instruction.tokenOut);
            _doSwap(instruction);
        }
        uint256 shares = _enter(_decodeMinLiquidityDelta(instructions[n - 1]));
        _mint(msg.sender, shares);
        IVault(msg.sender).enterCallback(positionId, shares);

        address[] memory tokens = _supportedTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            _returnAllFunds(msg.sender, positionId, tokens[i]);
        }
        _returnAllFunds(msg.sender, positionId, _notion);
    }

    function exit(
        uint256 shares,
        uint256 positionId,
        Instruction[] calldata instructions
    ) external payable {
        _exit(shares);

        uint256 notionAmount = 0;
        for (uint256 i = 0; i < instructions.length; i++) {
            SwapInstruction memory instruction = _decodeSwap(instructions[i]);
            _checkToken(instruction.tokenIn);
            _checkNotion(instruction.tokenOut);
            notionAmount += _doSwap(instruction);
        }
        _returnFunds(msg.sender, positionId, _notion, notionAmount);

        address[] memory tokens = _supportedTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            _returnAllFunds(msg.sender, positionId, tokens[i]);
        }
        IVault(msg.sender).exitCallback(positionId);
    }

    function reinvest(Instruction[] calldata instructions) external {
        // instructions
        // [SWAP, SWAP, ..., SWAP, MIN_LIQUIDITY_DELTA]

        uint256 n = instructions.length;
        for (uint256 i = 0; i < n - 1; i++) {
            SwapInstruction memory instruction = _decodeSwap(instructions[i]);
            IERC20(instruction.tokenIn).safeTransferFrom(
                msg.sender,
                address(this),
                instruction.amountIn
            );
            _checkToken(instruction.tokenOut);
            _doSwap(instruction);
        }
        uint256 shares = _enter(_decodeMinLiquidityDelta(instructions[n - 1]));

        uint256 feeAmount = _calculatePerformanceFeeAmount(shares);
        _mint(treasury, feeAmount);

        address[] memory tokens = _supportedTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenBalance = IERC20(tokens[i]).balanceOf(address(this));
            if (tokenBalance > 0) {
                IERC20(tokens[i]).transfer(msg.sender, tokenBalance);
            }
        }
    }

    function withdrawLiquidity(
        address recipieint,
        uint256 shares,
        Instruction[] calldata
    ) external payable {
        uint256 liuiqidity = _toLiquidity(shares);
        _burn(msg.sender, shares);
        _withdrawLiquidityLogic(recipieint, liuiqidity);
    }

    function totalShares() public view override returns (uint256) {
        return totalSupply();
    }

    function notion() external view returns (address) {
        return _notion;
    }

    function _withdrawShares(uint256 shares) internal override {
        _burn(msg.sender, shares);
    }
}

