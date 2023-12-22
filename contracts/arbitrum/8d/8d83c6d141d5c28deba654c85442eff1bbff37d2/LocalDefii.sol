// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {ERC20} from "./ERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IFundsCollector} from "./IFundsCollector.sol";
import {IDefii} from "./IDefii.sol";
import {BaseDefii} from "./BaseDefii.sol";

abstract contract LocalDefii is IDefii, BaseDefii, ERC20 {
    using SafeERC20 for IERC20;

    constructor(
        address swapHelper_
    ) BaseDefii(swapHelper_) ERC20("Defii LP", "DLP") {}

    function enter(
        address token,
        uint256 amount,
        uint256 id,
        Instruction[] calldata instructions
    ) external payable {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        uint256 totalSupply = totalSupply();

        uint256 lpAmountBefore = ownedLpAmount();
        _doInstructions(instructions);
        _enter();
        uint256 lpAmountAfter = ownedLpAmount();
        if (lpAmountBefore >= lpAmountAfter) {
            revert EnterFailed();
        }

        uint256 defiiLpAmount;
        if (totalSupply == 0) {
            defiiLpAmount = lpAmountAfter - lpAmountBefore;
        } else {
            defiiLpAmount =
                ((lpAmountAfter - lpAmountBefore) * totalSupply) /
                lpAmountBefore;
        }

        _mint(address(this), defiiLpAmount);

        // this.approve instead approve for correct msg.sender
        this.approve(msg.sender, defiiLpAmount);

        IFundsCollector(msg.sender).collectFunds(
            address(this),
            id,
            address(this),
            defiiLpAmount
        );
    }

    function exit(
        uint256 defiiLpAmount,
        address toToken,
        uint256 id,
        Instruction[] calldata instructions
    ) external payable {
        uint256 lpAmount = defiiLpAmountToLpAmount(defiiLpAmount);
        _burn(msg.sender, defiiLpAmount);

        uint256 toTokenAmountBefore = IERC20(toToken).balanceOf(address(this));
        _exit(lpAmount);
        _doInstructions(instructions);
        uint256 toTokenAmountAfter = IERC20(toToken).balanceOf(address(this));

        if (toTokenAmountAfter <= toTokenAmountBefore) {
            revert ExitFailed();
        }

        IERC20(toToken).safeIncreaseAllowance(
            msg.sender,
            toTokenAmountAfter - toTokenAmountBefore
        );
        IFundsCollector(msg.sender).collectFunds(
            address(this),
            id,
            toToken,
            toTokenAmountAfter - toTokenAmountBefore
        );
    }

    function defiiLpAmountToLpAmount(
        uint256 defiiLpAmount
    ) public override returns (uint256) {
        return (defiiLpAmount * ownedLpAmount()) / totalSupply();
    }
}

