// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./Pino.sol";
import "./IWETH9.sol";
import "./IAave.sol";
import "./IWethGateway.sol";
import "./ILendingPoolV2.sol";
import "./ILendingPoolV3.sol";

import "./SafeERC20.sol";

/// @title Aave proxy contract
/// @author Matin Kaboli
/// @notice Deposits and Withdraws tokens to the lending pool
/// @dev This contract uses Permit2
contract Aave is IAave, Pino {
    using SafeERC20 for IERC20;

    IWethGateway public wethGateway;
    ILendingPoolV2 public lendingPoolV2;
    ILendingPoolV3 public lendingPoolV3;

    /// @notice Sets LendingPool addresses for different Aave versions
    /// @param _permit2 Address of Permit2 contract
    /// @param _weth Address of WETH9 contract
    /// @param _lendingPoolV2 Aave lending pool V2 address
    /// @param _lendingPoolV3 Aave lending pool V3 address
    /// @param _wethGateway Aave WethGateway contract address
    constructor(
        Permit2 _permit2,
        IWETH9 _weth,
        ILendingPoolV2 _lendingPoolV2,
        ILendingPoolV3 _lendingPoolV3,
        IWethGateway _wethGateway
    ) Pino(_permit2, _weth) {
        wethGateway = _wethGateway;
        lendingPoolV2 = _lendingPoolV2;
        lendingPoolV3 = _lendingPoolV3;
    }

    /// @notice Changes LendingPool and WethGateway address if necessary
    /// @param _lendingPoolV2 Aave lending pool V2 address
    /// @param _lendingPoolV3 Aave lending pool V3 address
    /// @param _wethGateway Address of the new weth gateway
    function setNewAddresses(ILendingPoolV2 _lendingPoolV2, ILendingPoolV3 _lendingPoolV3, IWethGateway _wethGateway)
        external
        onlyOwner
    {
        wethGateway = _wethGateway;
        lendingPoolV2 = _lendingPoolV2;
        lendingPoolV3 = _lendingPoolV3;
    }

    /// @notice Deposits a token to the lending pool V2 and transfers aTokens to recipient
    /// @param _params Supply parameters
    /// token Token to deposit
    /// amount Amount to deposit
    /// recipient Recipient of the deposit that will receive aTokens
    function depositV2(IAave.DepositParams calldata _params) external payable {
        lendingPoolV2.deposit(_params.token, _params.amount, _params.recipient, 0);
    }

    /// @notice Deposits a token to the lending pool V3 and transfers aTokens to recipient
    /// @param _params Supply parameters
    /// token Token to deposit
    /// amount Amount to deposit
    /// recipient Recipient of the deposit that will receive aTokens
    function depositV3(IAave.DepositParams calldata _params) external payable {
        lendingPoolV3.supply(_params.token, _params.amount, _params.recipient, 0);
    }

    /// @notice Receives aToken and transfers ERC20 token to recipient using lending pool V2
    /// @param _params Withdraw params
    /// token Token to withdraw
    /// amount Amount to withdraw
    /// recipient Recipient to receive ERC20 tokens
    function withdrawV2(IAave.WithdrawParams calldata _params) external payable {
        lendingPoolV2.withdraw(_params.token, _params.amount, _params.recipient);
    }

    /// @notice Receives aToken and transfers ERC20 token to recipient using lending pool V3
    /// @param _params Withdraw params
    /// token Token to withdraw
    /// amount Amount to withdraw
    /// recipient Recipient to receive ERC20 tokens
    function withdrawV3(IAave.WithdrawParams calldata _params) external payable {
        lendingPoolV3.withdraw(_params.token, _params.amount, _params.recipient);
    }

    /// @notice Receives A_WETH and transfers ETH token to recipient using lending pool V2
    /// @param _params Withdraw params
    /// amount Amount to withdraw
    /// recipient Recipient to receive ETH
    function withdrawETHV2(IAave.WithdrawETHParams calldata _params) external payable {
        wethGateway.withdrawETH(address(lendingPoolV2), _params.amount, _params.recipient);
    }

    /// @notice Receives A_WETH and transfers ETH token to recipient using lending pool V3
    /// @param _params Withdraw params
    /// amount Amount to withdraw
    /// recipient Recipient to receive ETH
    function withdrawETHV3(IAave.WithdrawETHParams calldata _params) external payable {
        wethGateway.withdrawETH(address(lendingPoolV3), _params.amount, _params.recipient);
    }

    /// @notice Repays a borrowed token using lending pool V2
    /// @param _params Rate mode, 1 for stable and 2 for variable
    /// token Token to repay
    /// amount Amount to repay
    /// rateMode Rate mode, 1 for stable and 2 for variable
    /// recipient Recipient to repay for
    function repayV2(IAave.RepayParams calldata _params) external payable {
        lendingPoolV2.repay(_params.token, _params.amount, _params.rateMode, _params.recipient);
    }

    /// @notice Repays a borrowed token using lending pool V3
    /// @param _params Rate mode, 1 for stable and 2 for variable
    /// token Token to repay
    /// amount Amount to repay
    /// rateMode Rate mode, 1 for stable and 2 for variable
    /// recipient Recipient to repay for
    function repayV3(IAave.RepayParams calldata _params) external payable {
        lendingPoolV3.repay(_params.token, _params.amount, _params.rateMode, _params.recipient);
    }
}

