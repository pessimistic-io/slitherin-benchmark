// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

/**
 * @notice Contains all errors used throughout the Definitive contracts
 * @dev This file should only be used as an internal library.
 * @dev When adding a new error, add alphabetically
 */

error AccountMissingRole(address _account, bytes32 _role);
error AccountNotAdmin(address);
error AccountNotWhitelisted(address);
error AddLiquidityFailed();
error EnterAllFailed();
error ExceededMaxLTV();
error ExitAllFailed();
error ExitOneCoinFailed();
error InputGreaterThanStaked();
error InsufficientBalance();
error InsufficientSwapTokenBalance();
error InvalidAmount();
error InvalidAmounts();
error InvalidCalldata();
error InvalidERC20Address();
error InvalidExecutedOutputAmount();
error InvalidFeePercent();
error InvalidFlashLoanToken(address);
error InvalidHandler();
error InvalidInputs();
error InvalidMsgValue();
error InvalidSingleHopSwap();
error InvalidMultiHopSwap();
error InvalidOutputToken();
error InvalidRedemptionRecipient(); // Used in cross-chain redeptions
error InvalidReportedOutputAmount();
error InvalidSwapHandler();
error InvalidSwapInputAmount();
error InvalidSwapOutputToken();
error InvalidSwapPath();
error InvalidSwapPayload();
error InvalidSwapToken();
error NativeAssetWrapFailed(bool wrappingToNative);
error RemoveLiquidityFailed();
error SlippageExceeded(uint256 _outputAmount, uint256 _outputAmountMin);
error StakeFailed();
error StopGuardianEnabled();
error SwapDeadlineExceeded();
error SwapLimitExceeded();
error SwapTokenIsOutputToken();
error UnstakeFailed();
error UnauthenticatedFlashloan();
error UntrustedFlashLoanSender(address);

