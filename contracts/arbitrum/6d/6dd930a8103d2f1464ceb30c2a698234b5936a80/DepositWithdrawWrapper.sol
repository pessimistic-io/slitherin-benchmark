// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./SafeERC20.sol";

import "./ICommonFacet.sol";
import "./IProportionalDepositFacet.sol";
import "./IProportionalWithdrawFacet.sol";

import "./UniV3Token.sol";

contract DepositWithdrawWrapper {
    using SafeERC20 for IERC20;

    function deposit(
        address vault,
        uint256[] memory tokenAmounts,
        uint256 minLpAmount
    ) external returns (uint256 lpAmount, uint256[] memory actualTokenAmounts) {
        (address[] memory tokens, , ) = ICommonFacet(vault).tokens();
        require(tokens.length == 1);
        UniV3Token token = UniV3Token(tokens[0]);

        address token0 = token.token0();
        address token1 = token.token1();

        IERC20(token0).safeTransferFrom(msg.sender, address(this), tokenAmounts[0]);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), tokenAmounts[1]);

        IERC20(token0).safeIncreaseAllowance(address(token), tokenAmounts[0]);
        IERC20(token1).safeIncreaseAllowance(address(token), tokenAmounts[1]);

        token.mint(tokenAmounts[0], tokenAmounts[1], 0);

        uint256 balance = token.balanceOf(address(this));

        IERC20(tokens[0]).safeIncreaseAllowance(vault, balance);

        uint256[] memory depositTokenAmounts = new uint256[](1);
        depositTokenAmounts[0] = balance;
        (lpAmount, actualTokenAmounts) = IProportionalDepositFacet(vault).proportionalDeposit(
            depositTokenAmounts,
            minLpAmount
        );

        if (actualTokenAmounts[0] < balance) {
            token.burn(balance - actualTokenAmounts[0]);
        }

        actualTokenAmounts = new uint256[](2);

        {
            balance = IERC20(token0).balanceOf(address(this));
            actualTokenAmounts[0] = tokenAmounts[0] - balance;
            if (balance > 0) {
                IERC20(token0).safeTransfer(msg.sender, balance);
            }
        }
        {
            balance = IERC20(token1).balanceOf(address(this));
            actualTokenAmounts[1] = tokenAmounts[1] - balance;
            if (balance > 0) {
                IERC20(token1).safeTransfer(msg.sender, balance);
            }
        }

        LpToken lpToken = ICommonFacet(vault).lpToken();
        if (lpToken.totalSupply() == lpAmount) {
            // initial deposit
            require(minLpAmount == 0, "Invalid state");
            lpAmount = 0;
        } else {
            IERC20(address(lpToken)).safeTransfer(msg.sender, lpAmount);
        }
        IERC20(tokens[0]).safeApprove(vault, 0);

        IERC20(token0).safeApprove(address(token), 0);
        IERC20(token1).safeApprove(address(token), 0);
    }

    function withdraw(
        address vault,
        uint256 lpAmount,
        uint256[] memory minTokenAmounts
    ) external returns (uint256[] memory actualTokenAmounts) {
        (address[] memory tokens, , ) = ICommonFacet(vault).tokens();
        require(tokens.length == 1, "Invalid length");

        LpToken lpToken = ICommonFacet(vault).lpToken();
        IERC20(address(lpToken)).safeTransferFrom(msg.sender, address(this), lpAmount);

        uint256[] memory withdrawedTokenAmounts = IProportionalWithdrawFacet(vault).proportionalWithdrawal(
            lpAmount,
            new uint256[](1)
        );

        UniV3Token token = UniV3Token(tokens[0]);
        token.burn(uint128(token.convertSupplyToLiquidity(withdrawedTokenAmounts[0])));

        actualTokenAmounts = new uint256[](2);
        actualTokenAmounts[0] = IERC20(token.token0()).balanceOf(address(this));
        actualTokenAmounts[1] = IERC20(token.token1()).balanceOf(address(this));

        for (uint256 i = 0; i < 2; i++) {
            require(actualTokenAmounts[i] >= minTokenAmounts[i], "Limit underflow");
        }

        IERC20(token.token0()).safeTransfer(msg.sender, actualTokenAmounts[0]);
        IERC20(token.token1()).safeTransfer(msg.sender, actualTokenAmounts[1]);
    }
}

