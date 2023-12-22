// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.20;

import {Owned} from "./Owned.sol";
import {SafeTransferLib, ERC20} from "./SafeTransferLib.sol";

/// @notice Buffer contract for quick token <> token exchagne.
contract TokenExchange is Owned {
    using SafeTransferLib for ERC20;

    /// @notice The exchange token we issue or redeem.
    ERC20 public immutable exchangeToken;

    /// @notice Whether issuing is enabled.
    bool public canIssue = true;
    /// @notice Whether redeeming is enabled.
    bool public canRedeem = true;

    /// @notice Initial 0.01% fee on issue and redeem.
    uint256 public issueFeeBps = 1;
    uint256 public redeemFeeBps = 1;

    /// @notice 1 unit of token x gives y units of exchange token, multiplied by 10^18.
    /// @dev Example: if exchangeToken is a stablecion with 6 decimals: exchangeRate[USDC] = 1e18, exchangeRate[DAI] = 1e6.
    mapping(address token => uint256 rate) public exchangeRate;

    event SetExchangeRate(address indexed token, uint256 rate);
    event Issue(address indexed account, address tokenIn, uint256 amountIn, uint256 amountIssued);
    event Redeem(address indexed account, address tokenOut, uint256 amountOut, uint256 amountRedeemed);
    event CanIssue(bool status);
    event CanRedeem(bool status);
    event SetIssueFeeBps(uint256 feeBps);
    event SetRedeemFeeBps(uint256 feeBps);

    error CannotIssue();
    error CannotRedeem();
    error NoExchangeRate();

    constructor(address _exchangeToken)
        Owned(msg.sender)
    {
        exchangeToken = ERC20(_exchangeToken);
    }

    /// @notice Calculates the amount of exchangeToken to issue in exchange for a quote token.
    function getIssueAmount(address tokenIn, uint256 amountIn) public view returns (uint256) {
        uint256 rate = exchangeRate[tokenIn];
        if (rate == 0) revert NoExchangeRate();
        return (amountIn * rate / 1e18) * (1e6 - issueFeeBps) / 1e6;
    }

    /// @notice Calculates the amount of tokenOut to redeem in exchange for exchangeToken.
    function getRedeemAmount(address tokenOut, uint256 amountIn) public view returns (uint256) {
        uint256 rate = exchangeRate[tokenOut];
        if (rate == 0) revert NoExchangeRate();
        return (amountIn * 1e18 / rate) * (1e6 - redeemFeeBps) / 1e6;
    }

    function issue(address tokenIn, uint256 amountIn) external returns (uint256 amountOut) {
        if (!canIssue) revert CannotIssue();
        amountOut = getIssueAmount(tokenIn, amountIn);
        ERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        exchangeToken.safeTransfer(msg.sender, amountOut);
        emit Issue(msg.sender, tokenIn, amountIn, amountOut);
    }

    function redeem(address tokenOut, uint256 amountIn) external returns (uint256 amountOut) {
        if (!canRedeem) revert CannotRedeem();
        amountOut = getRedeemAmount(tokenOut, amountIn);
        exchangeToken.safeTransferFrom(msg.sender, address(this), amountIn);
        ERC20(tokenOut).transfer(msg.sender, amountOut);
        emit Redeem(msg.sender, tokenOut, amountIn, amountOut);
    }

    /// @notice Set the exchange rate for a token.
    function setExchangeRate(address token, uint256 rate) external onlyOwner {
        exchangeRate[token] = rate;
        emit SetExchangeRate(token, rate);
    }

    /// @notice Set the issue fee.
    function setIssueFee(uint256 feeBps) external onlyOwner {
        issueFeeBps = feeBps;
        emit SetIssueFeeBps(feeBps);
    }

    /// @notice Set the redeem fee.
    function setRedeemFee(uint256 feeBps) external onlyOwner {
        redeemFeeBps = feeBps;
        emit SetRedeemFeeBps(feeBps);
    }

    /// @notice Pauses or unpauses issuing.
    function enableIssuing(bool status) external onlyOwner {
        canIssue = status;
        emit CanIssue(status);
    }

    /// @notice Pauses or unpauses redeeming.
    function enableRedeeming(bool status) external onlyOwner {
        canRedeem = status;
        emit CanRedeem(status);
    }

    /// @notice Owner has full access over contract funds.
    function withdraw(address token, address to, uint256 amount) external onlyOwner {
        ERC20(token).safeTransfer(to, amount);
    }
}

