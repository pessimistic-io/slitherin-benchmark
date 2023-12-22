// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.9;

import {     SwapOperation,     SwapProtocol,     InToken,     InInformation,     OutInformation,     InteractionOperation,     Operation,     InteractionOperation,     WrapperSelector,     WrapperSelectorAMM,     OneTokenSwapAMM } from "./structs.sol";
import {SwapHelper} from "./swapHelper.sol";
import {GenerateCallData} from "./generateCalldata.sol";
import {IERC20} from "./IERC20.sol";

/// @title  Executor
/// @author Valha Team - octave@1608labs.xyz
/// @notice Executor contract enabling the Router to execute the steps to perform the operations
contract Executor is SwapHelper, GenerateCallData {
    uint24 private constant UNISWAP_V3_FEE = 3000;

    /// ============ Constructor ============

    /// @notice Creates a new Router contract
    constructor() SwapHelper() {
        /* For faster testing */
        SwapProtocol[] memory _swapRouterTypes = new SwapProtocol[](3);
        address[] memory _swapRouterAddress = new address[](3);
        _swapRouterTypes[0] = SwapProtocol.UniswapV3;
        _swapRouterTypes[1] = SwapProtocol.OneInch;
        _swapRouterTypes[2] = SwapProtocol.ZeroX;
        _swapRouterAddress[0] = address(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        _swapRouterAddress[1] = address(0x1111111254EEB25477B68fb85Ed929f73A960582);
        _swapRouterAddress[2] = address(0xDef1C0ded9bec7F1a1670819833240f027b25EfF);
        _registerSwaps(_swapRouterTypes, _swapRouterAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// ============ Errors ============
    error InteractionError();

    /// ============ Main Functions ============

    /// @notice Allows users to chain calls on-chain.
    /// @notice This function can chain swap and DeFi protocol interactions (deposit, redeem...)
    /// @dev    Requires user to approve contract.
    /// @param  routingCall contains all the swap and interaction information. This object is at the center of the contract's logic
    /// @param  outInformation contains all the tokens that will be sent back to the msg.sender after all interactions.
    function execute(
        Operation[] memory routingCall, // Can't turn to calldata because of wrapper functions
        OutInformation memory outInformation // Can't turn to calldata because of wrapper functions
    ) public payable {
        // We call all the interactions sequentially
        uint256 routingCallLength = routingCall.length;
        for (uint256 i; i < routingCallLength; ++i) {
            // We check which operation should be executed
            if (_isSwapOperation(routingCall[i])) {
                uint256 thisCallLength = routingCall[i].swap.length;
                for (uint256 j; j < thisCallLength; ++j) {
                    executeSwap(routingCall[i].swap[j]);
                }
            } else {
                uint256 thisCallLength = routingCall[i].interaction.length;
                for (uint256 j; j < thisCallLength; ++j) {
                    executeInteraction(routingCall[i].interaction[j]);
                }
            }
        }
        uint256 outTokenLength = outInformation.tokens.length;
        // We transfer the remaining tokens to the customer
        for (uint256 i; i < outTokenLength; ++i) {
            uint256 balance = _balanceOf(outInformation.tokens[i], address(this));
            _transferFromContract(outInformation.tokens[i], outInformation.to, balance);
        }
    }

    /// @notice Execute a swap operation
    /// @param  _swap contains all the information needed to execute the operation
    function executeSwap(SwapOperation memory _swap) internal {
        // Here we swap one asset for one other asset
        uint256 balance = thisBalanceOf(_swap.inToken);
        swap(_swap, min(balance, _swap.maxInAmount));
    }

    /// @notice Execute a DeFi operation
    /// @param  _interaction contains all the information needed to execute the operation
    function executeInteraction(InteractionOperation memory _interaction) internal {
        // We get all the inToken balances and change the inAmount of the call
        uint256 value;

        uint256 inTokenLength = _interaction.inTokens.length;
        for (uint256 i; i < inTokenLength; ++i) {
            uint256 balance = thisBalanceOf(_interaction.inTokens[i]);

            if (_interaction.amountPositions[i] != type(uint8).max) {
                _interaction.callArgs[_interaction.amountPositions[i]] = bytes32(balance);
            }

            if (_interaction.inTokens[i] == nativeToken) {
                value += balance;
            }
            _approveIfNecessary(_interaction.interactionAddress, _interaction.inTokens[i], balance);
        }

        bytes memory callData = _generateCalldataFromBytes(_interaction.methodSelector, _interaction.callArgs);

        (bool success,) = address(_interaction.interactionAddress).call{value: value}(callData);
        if (!success) revert InteractionError();
    }

    /// ============ Helpers Functions ============

    /// @notice Get the balance of a specific user of a specified token
    /// @param  _token address of the token to check the balance of
    /// @param  _user address of the user to check the balance of
    /// @return balance of the _user for the specific _contract
    function _balanceOf(address _token, address _user) internal view returns (uint256 balance) {
        if (_token == nativeToken) {
            balance = _user.balance;
        } else {
            balance = IERC20(_token).balanceOf(_user);
        }
    }

    /// @notice Get the balance of this contract of a specified token
    /// @param  _token address of the token to check the balance of
    /// @return balance of the router for the specific _token
    function thisBalanceOf(address _token) internal view returns (uint256 balance) {
        return _balanceOf(_token, address(this));
    }

    /// @notice     Get the minimum of two provided uint256 values
    /// @param      a uint256 value
    /// @param      b uint256 value
    /// @return     The minimum value between a and b
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a <= b ? a : b;
    }

    /// @dev Callback for receiving Ether when the calldata is empty
    /// Because the owner can remove funds from the contract, we allow depositing funds here
    receive() external payable {}
}

