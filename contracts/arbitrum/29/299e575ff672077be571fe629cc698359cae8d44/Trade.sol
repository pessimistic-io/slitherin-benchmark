// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IVault} from "./IVault.sol";
import {Commands} from "./libraries_Commands.sol";
import {Errors} from "./Errors.sol";
import {IStvAccount} from "./IStvAccount.sol";
import {SpotTrade} from "./SpotTrade.sol";
import {IOperator} from "./IOperator.sol";
import {IERC20} from "./interfaces_IERC20.sol";
import {IPerpTrade} from "./IPerpTrade.sol";

library Trade {
    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice execute the type of trade
    /// @param command the command of the ddex protocol from `Commands` library
    /// @param data encoded data of parameters depending on the ddex
    /// @param isOpen bool to check if the trade is an increase or a decrease trade
    /// @param operator address of the operator
    /// @return totalReceived after executing the trade
    function execute(uint256 command, bytes calldata data, bool isOpen, address operator)
        external
        returns (uint96 totalReceived)
    {
        (address stvId, uint96 amount, address tradeToken) = _getParams(data);
        address defaultStableCoin = IOperator(operator).getAddress("DEFAULTSTABLECOIN");
        if (tradeToken == defaultStableCoin) revert Errors.InputMismatch();

        address tokenIn = isOpen ? defaultStableCoin : tradeToken;
        address tokenOut = isOpen ? tradeToken : defaultStableCoin;

        if (command == Commands.UNI) {
            (,,, bytes memory commands, bytes[] memory inputs, uint256 deadline) =
                abi.decode(data, (address, uint96, address, bytes, bytes[], uint256));
            bytes memory addresses = abi.encode(stvId, operator);

            _transferTokens(stvId, amount, tokenIn, operator);
            totalReceived = SpotTrade.uni(tokenIn, tokenOut, amount, commands, inputs, deadline, addresses);
        } else if (command == Commands.SUSHI) {
            (,,, uint256 amountOutMin) = abi.decode(data, (address, uint96, address, uint256));
            if (amountOutMin < 1) revert Errors.ZeroAmount();

            _transferTokens(stvId, amount, tokenIn, operator);
            totalReceived = SpotTrade.sushi(tokenIn, tokenOut, amount, amountOutMin, stvId, operator);
        } else if (command == Commands.ONE_INCH) {
            (,,, bytes memory exchangeData) = abi.decode(data, (address, uint96, address, bytes));

            _transferTokens(stvId, amount, tokenIn, operator);
            totalReceived = SpotTrade.oneInch(tokenIn, tokenOut, stvId, exchangeData, operator);
        } else {
            revert Errors.CommandMisMatch();
        }
    }

    /// @notice distribute the fees and the remaining tokens after the stv is closed
    /// @param stvId address of the stv
    /// @param command the command of the ddex protocol from `Commands` library
    /// @param managerFees manager fees in 1e18 decimals
    /// @param protocolFees protocol fees in 1e18 decimals
    /// @param tradeToken address of the trade token to swap
    /// @param exchangeData exchange data to swap, 0 - eth swap, 1 - tradeToken swap
    /// @param operator address of the operator
    /// @return totalRemainingAfterDistribute amount of defaultStableCoin remaining after fees
    /// @return mFee manager fees
    /// @return pFee protocol fees
    function distribute(
        address stvId,
        uint256 command,
        uint96 totalDepositTokenUsed,
        uint96 managerFees,
        uint96 protocolFees,
        address tradeToken,
        bytes[] memory exchangeData,
        address operator
    ) external returns (uint96 totalRemainingAfterDistribute, uint96 mFee, uint96 pFee) {
        address id = stvId; // to avoid stack too deep
        uint96 depositTokenUsed = totalDepositTokenUsed; // to avoid stack too deep
        address defaultStableCoin = IOperator(operator).getAddress("DEFAULTSTABLECOIN");
        uint256 depositTokenBalance = IERC20(defaultStableCoin).balanceOf(id);

        if (command == Commands.GMX) {
            address tt = tradeToken; // to avoid stack too deep
            uint256 ethBalance = id.balance;
            address exchangeRouter = IOperator(operator).getAddress("ONEINCHROUTER");
            bytes memory ethSwapExchangeData = exchangeData[0];
            bytes memory tokenSwapExchangeData = exchangeData[1];
            if (ethBalance > 0) IStvAccount(id).execute(exchangeRouter, ethSwapExchangeData, ethBalance);
            // after the position is closed from gmx, then the tokens recieved are transferred back to usdc
            if (tt != address(0)) _swap(id, tt, operator, exchangeRouter, tokenSwapExchangeData);
        } else if (command == Commands.KWENTA) {
            // swap from sUSD to USDC is done in PerpTrade call (withdraw all margin + swap to USDC)
            // exchangeData[0] should be "data" in PerpTrade._kwenta(bytes calldata data, bool isOpen) call
            address perpTrade = IOperator(operator).getAddress("PERPTRADE");
            IPerpTrade(perpTrade).execute(Commands.KWENTA, exchangeData[0], false);
        }
        uint256 depositTokenBalanceAfter = IERC20(defaultStableCoin).balanceOf(id);
        if (depositTokenBalanceAfter > depositTokenBalance) depositTokenBalance = depositTokenBalanceAfter;
        if (depositTokenBalance < 1) revert Errors.ZeroAmount();

        // to avoid stack too deep
        {
            (totalRemainingAfterDistribute, mFee, pFee) =
                _distribute(depositTokenUsed, uint96(depositTokenBalance), managerFees, protocolFees);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice get the first two params of the encoded data which is the address and the amount
    function _getParams(bytes calldata data) internal pure returns (address stvId, uint96 amount, address tradeToken) {
        assembly {
            stvId := calldataload(data.offset)
            amount := calldataload(add(data.offset, 0x20))
            tradeToken := calldataload(add(data.offset, 0x40))
        }
    }

    /// @notice transfer the tokens to the `Vault` contract before executing the trade
    function _transferTokens(address stvId, uint96 amount, address tokenIn, address operator) internal {
        address vault = IOperator(operator).getAddress("VAULT");
        bytes memory tradeData = abi.encodeWithSignature("transfer(address,uint256)", vault, amount);
        IStvAccount(stvId).execute(tokenIn, tradeData, 0);
    }

    /// @notice pure function to calculate the manager and the protocol fees
    function _distribute(uint96 totalRaised, uint96 totalReceivedAfterClose, uint96 managerFees, uint96 protocolFees)
        internal
        pure
        returns (uint96 totalRemainingAfterDistribute, uint96 mFee, uint96 pFee)
    {
        if (totalReceivedAfterClose > totalRaised) {
            uint96 profits = totalReceivedAfterClose - totalRaised;
            mFee = (profits * (managerFees / 1e18)) / 100;
            pFee = (profits * (protocolFees / 1e18)) / 100;
            totalRemainingAfterDistribute = totalReceivedAfterClose - mFee - pFee;
        } else {
            totalRemainingAfterDistribute = totalReceivedAfterClose;
        }
    }

    /// @notice internal function to swap the tokens when `distribute` is called
    function _swap(
        address account,
        address tokenIn,
        address operator,
        address exchangeRouter,
        bytes memory exchangeData
    ) internal {
        address defaultStableCoin = IOperator(operator).getAddress("DEFAULTSTABLECOIN");
        uint256 balanceBefore = IERC20(defaultStableCoin).balanceOf(account);

        uint256 tokenInBalance = IERC20(tokenIn).balanceOf(account);
        bytes memory tokenApprovalData =
            abi.encodeWithSignature("approve(address,uint256)", exchangeRouter, tokenInBalance);
        IStvAccount(account).execute(tokenIn, tokenApprovalData, 0);
        IStvAccount(account).execute(exchangeRouter, exchangeData, 0);

        // (uint256 returnAmount,) = abi.decode(returnData, (uint256, uint256));
        uint256 balanceAfter = IERC20(defaultStableCoin).balanceOf(account);
        if (balanceAfter <= balanceBefore) revert Errors.BalanceLessThanAmount();
    }
}

