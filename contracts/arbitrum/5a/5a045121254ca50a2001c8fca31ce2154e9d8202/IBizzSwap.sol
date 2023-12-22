// SPDX-License-Identifier: GNU Affero
pragma solidity ^0.8.0;

/// @title Interface for BizzSwap
interface IBizzSwap {
	/**
	 * @notice Parameters necessary for Uniswap V3 swap
	 *
	 * @param deadline - transaction will revert if it is pending for more than this period of time
	 * @param fee - the fee of the token pool to consider for the pair
	 * @param sqrtPriceLimitX96 - the price limit of the pool that cannot be exceeded by the swap
	 * @param isMultiSwap - flag to check whether to perform single or multi swap, cheaper than to compare path with abi.encodePacked("")
	 * @param isPayingWithEth - true if sender is paying with native coin, false otherwise; msg.value must be greater than zero if true
	 * @param path - sequence of (tokenAddress - fee - tokenAddress), encoded in reverse order, which are the variables needed to compute each pool contract address in sequence of swaps
	 *
	 * @notice msg.sender executes the payment
	 * @notice path is encoded in reverse order
	 */
	struct SwapParameters {
		uint256 deadline;
		uint24 fee;
		uint160 sqrtPriceLimitX96;
		bool isMultiSwap;
		bool isPayingWithEth;
		bytes path;
	}

	/**
	 * @notice Sets the address of the Router Contract
	 *
	 * @notice Only Administrator multisig can call
	 *
	 * @param _uniswapRouterContract - the address of the Router Contract
	 *
	 * No return, reverts on error
	 */
	function setRouterContract(address _uniswapRouterContract) external;

	/**
	 * @notice Creates payment invoice
	 *
	 * @param _desiredTokenAddress - address of the desired token
	 * @param _recipient - address of the recipient
	 * @param _isEthDesired - true if :_recipient: wants to receive native coin, false otherwise; if true, :_desiredTokenAddress: is irrelevant
	 * @param _exactAmountOut - amount of the desired token that should be paid
	 * @param _ipfsCid - ipfs hash of invoice details
	 *
	 * @return invoiceId - id of the newly created invoice
	 */
	function createInvoice(
		address _desiredTokenAddress,
		address _recipient,
		bool _isEthDesired,
		uint256 _exactAmountOut,
		string memory _ipfsCid
	) external returns (uint256 invoiceId);

	/**
	 * @notice Execute payment where sender pays in one token and recipient receives payment in one token
	 *
	 * @param invoiceId - id of the invoice to be paid
	 * @param _inputTokenAddress - address of the input token
	 * @param _maximumAmountIn - maximum amount of input token one is willing to spend for the payment
	 * @param _params - parameters necessary for the swap
	 *
	 * No return, reverts on error
	 */
	function payOneForOne(
		uint256 invoiceId,
		address _inputTokenAddress,
		uint256 _maximumAmountIn,
		SwapParameters memory _params
	) external payable;

	/**
	 * @notice Executes one on one micropayments
	 *
	 * @param _params - parameters necessary for the swap
	 * @param _isEthDesired - true if :_recipient: wants to receive native coin, false otherwise
	 * @param _recipient - the one who receives output tokens
	 * @param _inputTokenAddress - address of the input token
	 * @param _outputTokenAddress - address of the output token
	 * @param _exactAmountOut - amount of the desired token that should be paid
	 * @param _maximumAmountIn - the maximum amount of input token one is willing to spend for the payment
	 *
	 * No return, reverts on error
	 */
	function pay(
		SwapParameters memory _params,
		bool _isEthDesired,
		address _recipient,
		address _inputTokenAddress,
		address _outputTokenAddress,
		uint256 _exactAmountOut,
		uint256 _maximumAmountIn
	) external payable;
}

