// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IVault} from "./IVault.sol";
import {Commands} from "./libraries_Commands.sol";
import {Errors} from "./Errors.sol";
import {IStvAccount} from "./IStvAccount.sol";
import {SpotTrade} from "./SpotTrade.sol";
import {IOperator} from "./IOperator.sol";
import {IERC20} from "./interfaces_IERC20.sol";
import {IAccount} from "./IAccount.sol";
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
        (address stvId, uint96 amount) = _getAmountAndStvId(data);

        _getStvBalanceCheck(stvId, amount, isOpen);
        (address tokenIn, address tokenOut) = _getTokens(stvId, isOpen);
        _transferTokens(stvId, amount, isOpen, operator);

        if (command == Commands.UNI) {
            (,, bytes memory commands, bytes[] memory inputs, uint256 deadline) =
                abi.decode(data, (address, uint96, bytes, bytes[], uint256));
            bytes memory addresses = abi.encode(stvId, operator);

            totalReceived = SpotTrade.uni(tokenIn, tokenOut, amount, commands, inputs, deadline, addresses);
        } else if (command == Commands.SUSHI) {
            (,, uint256 amountOutMin) = abi.decode(data, (address, uint96, uint256));
            if (amountOutMin < 1) revert Errors.ZeroAmount();

            totalReceived = SpotTrade.sushi(tokenIn, tokenOut, amount, amountOutMin, stvId, operator);
        } else {
            revert Errors.CommandMisMatch();
        }
    }

    /// @notice distribute the fees and the remaining tokens after the stv is closed
    /// @param stvId address of the stv
    /// @param command the command of the ddex protocol from `Commands` library
    /// @param data encoded fees and exchange data
    /// @param operator address of the operator
    /// @return totalRemainingAfterDistribute amount of defaultStableCoin remaining after fees
    /// @return mFee manager fees
    /// @return pFee protocol fees
    function distribute(address stvId, uint8 command, bytes calldata data, address operator)
        external
        returns (uint96 totalRemainingAfterDistribute, uint96 mFee, uint96 pFee)
    {
        (bytes memory feesData, bytes[] memory exchangeData) = abi.decode(data, (bytes, bytes[]));
        IVault.StvInfo memory stv = IStvAccount(stvId).stvInfo();
        address defaultStableCoin = IOperator(operator).getAddress("DEFAULTSTABLECOIN");
        uint96 depositTokenBalance = uint96(IERC20(defaultStableCoin).balanceOf(stvId));
        address stvId = stvId; // stack deep

        if (command == Commands.GMX) {
            address tradeToken = stv.tradeToken;
            uint96 tradeTokenBalance = uint96(IERC20(tradeToken).balanceOf(stvId));

            // after the position is closed from gmx, then the tokens recieved are transferred back to usdc
            if (stvId.balance > 0) _swap(stvId, uint96(stvId.balance), address(0), defaultStableCoin, exchangeData[0]);
            if (tradeTokenBalance > 0) _swap(stvId, tradeTokenBalance, tradeToken, defaultStableCoin, exchangeData[1]);
        } else if (command == Commands.KWENTA) {
            // swap from sUSD to USDC is done in PerpTrade call (withdraw all margin + swap to USDC)
            // exchangeData[0] should be "data" in PerpTrade._kwenta(bytes calldata data, bool isOpen) call
            address perpTrade = IOperator(operator).getAddress("PERPTRADE");
            IPerpTrade(perpTrade).execute(Commands.KWENTA, exchangeData[0], false);
        }
        uint96 depositTokenBalanceAfter = uint96(IERC20(defaultStableCoin).balanceOf(stvId));
        if (depositTokenBalanceAfter > depositTokenBalance) depositTokenBalance = depositTokenBalanceAfter;
        if (depositTokenBalance < 1) revert Errors.ZeroAmount();

        IVault.StvBalance memory stvBalance = IStvAccount(stvId).stvBalance();
        // TODO  to use depositTokenBalance or stvBalance.totalReceivedAfterClose ( effect on Spot/Perp ??)
        (totalRemainingAfterDistribute, mFee, pFee) = _distribute(stvBalance.totalRaised, depositTokenBalance, feesData);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice get the first two params of the encoded data which is the address and the amount
    function _getAmountAndStvId(bytes calldata data) internal pure returns (address stvId, uint96 amount) {
        assembly {
            stvId := calldataload(data.offset)
            amount := calldataload(add(data.offset, 0x20))
        }
    }

    /// @notice get the tokenIn and tokenOut for swapping
    function _getTokens(address stvId, bool isOpen) internal view returns (address tokenIn, address tokenOut) {
        IVault.StvInfo memory stv = IStvAccount(stvId).stvInfo();
        tokenIn = isOpen ? stv.depositToken : stv.tradeToken;
        tokenOut = isOpen ? stv.tradeToken : stv.depositToken;
    }

    /// @notice check the `stvBalance` before executing the trade
    function _getStvBalanceCheck(address stvId, uint96 amount, bool isOpen) internal view {
        if (!isOpen) {
            IVault.StvBalance memory stvBalance = IStvAccount(stvId).stvBalance();
            if (amount + stvBalance.totalTradeTokenUsedForClose > stvBalance.totalReceivedAfterOpen) {
                revert Errors.MoreThanTotalReceived();
            }
        }
    }

    /// @notice transfer the tokens to the `Vault` contract before executing the trade
    function _transferTokens(address stvId, uint96 amount, bool isOpen, address operator) internal {
        address vault = IOperator(operator).getAddress("VAULT");
        (address tokenIn,) = _getTokens(stvId, isOpen);
        bytes memory tradeData = abi.encodeWithSignature("transfer(address,uint256)", vault, amount);
        IStvAccount(stvId).execute(tokenIn, tradeData);
    }

    /// @notice pure function to calculate the manager and the protocol fees
    function _distribute(uint96 totalRaised, uint96 totalReceivedAfterClose, bytes memory feesData)
        internal
        pure
        returns (uint96 totalRemainingAfterDistribute, uint96 mFee, uint96 pFee)
    {
        (uint96 managerFees, uint96 protocolFees) = abi.decode(feesData, (uint96, uint96));
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
    function _swap(address account, uint96 amount, address tokenIn, address tokenOut, bytes memory exchangeData)
        internal
    {
        (address exchangeRouter, bytes memory routerData) = abi.decode(exchangeData, (address, bytes));
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(account);

        if (tokenIn != address(0)) {
            bytes memory tokenApprovalData = abi.encodeWithSignature("approve(address,uint256)", exchangeRouter, amount);
            IAccount(account).execute(tokenIn, tokenApprovalData);
        }

        IAccount(account).execute(exchangeRouter, routerData);
        // (uint256 returnAmount,) = abi.decode(returnData, (uint256, uint256));
        uint256 balanceAfter = IERC20(tokenOut).balanceOf(account);
        if (balanceAfter <= balanceBefore) revert Errors.BalanceLessThanAmount();
    }
}

