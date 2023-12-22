// SPDX-License-Identifier: GNU Affero
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./Counters.sol";
import "./ReentrancyGuard.sol";
import "./ISwapRouter.sol";
import "./TransferHelper.sol";
import "./IPeripheryPayments.sol";
import "./IPeripheryImmutableState.sol";

import "./IBizzSwap.sol";
import "./IWETH9.sol";

/// @title BizzSwap
contract BizzSwap is IBizzSwap, Ownable, ReentrancyGuard {
	using Counters for Counters.Counter;

	/**
	 * @notice Invoice structure
	 *
	 * @param exactAmountOut - amount of the desired token that should be paid
	 * @param desiredTokenAddress - address of the desired token
	 * @param recipient - address of the recipient
	 * @param isEthDesired - true if :recipient: wants to receive native coin, false otherwise; if true, :desiredTokenAddress: is irrelevant
	 * @param isPaid - true if invoice is paid, false otherwise
	 * @param ipfsCid - ipfs hash of invoice details
	 */
	struct Invoice {
		uint256 exactAmountOut;
		address desiredTokenAddress;
		address recipient;
		bool isEthDesired;
		bool isPaid;
		string ipfsCid;
	}

	Counters.Counter private _invoiceId;
	ISwapRouter public uniswapRouterContract;

	mapping(uint256 => Invoice) public invoices;

	event RouterContractUpdated(address indexed uniswapRouterContract);
	event InvoiceCreated(
		uint256 indexed invoiceId,
		string ipfsCid,
		address indexed desiredTokenAddress,
		bool isEthDesired,
		address indexed recipient,
		uint256 exactAmountOut
	);
	event PaymentCompleted(
		uint256 indexed invoiceId,
		address indexed payer,
		address indexed inputTokenAddress,
		bool isPayedWithEth
	);

	modifier validAddress(address _address) {
		require(_address != address(0), 'BizzSwap: Invalid address');
		_;
	}

	modifier validAmount(uint256 _amount) {
		require(_amount > 0, 'BizzSwap: Invalid amount');
		_;
	}

	constructor(address _uniswapRouterContract) {
		setRouterContract(_uniswapRouterContract);
	}

	receive() external payable {}

	/// @inheritdoc IBizzSwap
	function setRouterContract(address _uniswapRouterContract)
		public
		override
		onlyOwner
		validAddress(_uniswapRouterContract)
	{
		uniswapRouterContract = ISwapRouter(_uniswapRouterContract);

		emit RouterContractUpdated(_uniswapRouterContract);
	}

	/// @inheritdoc IBizzSwap
	function createInvoice(
		address _desiredTokenAddress,
		address _recipient,
		bool _isEthDesired,
		uint256 _exactAmountOut,
		string memory _ipfsCid
	)
		external
		override
		validAddress(_desiredTokenAddress)
		validAddress(_recipient)
		validAmount(_exactAmountOut)
		returns (uint256 invoiceId)
	{
		invoiceId = _invoiceId.current();

		address desiredTokenAddress = _isEthDesired
			? IPeripheryImmutableState(address(uniswapRouterContract)).WETH9()
			: _desiredTokenAddress;

		invoices[invoiceId] = Invoice(_exactAmountOut, desiredTokenAddress, _recipient, _isEthDesired, false, _ipfsCid);
		_invoiceId.increment();

		emit InvoiceCreated(invoiceId, _ipfsCid, _desiredTokenAddress, _isEthDesired, _recipient, _exactAmountOut);
	}

	/// @inheritdoc IBizzSwap
	function payOneForOne(
		uint256 invoiceId,
		address _inputTokenAddress,
		uint256 _maximumAmountIn,
		SwapParameters memory _params
	) external payable override {
		Invoice storage invoice = invoices[invoiceId];

		require(invoice.recipient != address(0), 'BizzSwap::payOneForOne: Invoice with specified ID does not exist');
		require(!invoice.isPaid, 'BizzSwap::payOneForOne: Invoice already paid');

		pay(
			_params,
			invoice.isEthDesired,
			invoice.recipient,
			_inputTokenAddress,
			invoice.desiredTokenAddress,
			invoice.exactAmountOut,
			_maximumAmountIn
		);

		invoice.isPaid = true;

		emit PaymentCompleted(invoiceId, msg.sender, _inputTokenAddress, _params.isPayingWithEth);
	}

	/// @inheritdoc IBizzSwap
	function pay(
		SwapParameters memory _params,
		bool _isEthDesired,
		address _recipient,
		address _inputTokenAddress,
		address _outputTokenAddress,
		uint256 _exactAmountOut,
		uint256 _maximumAmountIn
	) public payable override nonReentrant validAddress(_inputTokenAddress) {
		address WETH9 = IPeripheryImmutableState(address(uniswapRouterContract)).WETH9();

		if (_params.isPayingWithEth) {
			require(msg.value > 0, 'BizzSwap::pay: Msg.value must be greather than zero when paying with native coin');

			if (_isEthDesired) {
				_transferEth(_recipient, _exactAmountOut);
			} else if (_outputTokenAddress == WETH9) {
				_wrapEth(WETH9, _exactAmountOut, _recipient);
			} else {
				_swapEthForToken(_params, _recipient, WETH9, _outputTokenAddress, _exactAmountOut, msg.value);
			}
		} else {
			if (_isEthDesired) {
				_swapTokenForEth(_params, _recipient, _inputTokenAddress, WETH9, _exactAmountOut, _maximumAmountIn);
			} else {
				_swapTokens(
					_params,
					_recipient,
					_inputTokenAddress,
					_outputTokenAddress,
					_exactAmountOut,
					_maximumAmountIn
				);
			}
		}
	}

	/**
	 * @notice Swaps as little as possible of one token for :_exactAmountOut: of another token using Uniswap V3
	 * @notice Depends on Uniswap's V3 SwapRouter periphery contract
	 *
	 * @param _params - parameters necessary for the swap
	 * @param _recipient - the one who receives output tokens
	 * @param _inputTokenAddress - address of the input token
	 * @param _outputTokenAddress - address of the output token
	 * @param _exactAmountOut - amount of the desired token that should be swapped
	 * @param _maximumAmountIn - the maximum amount of input token one is willing to spend for the swap
	 *
	 * No return, reverts on error
	 */
	function _swap(
		SwapParameters memory _params,
		address _recipient,
		address _inputTokenAddress,
		address _outputTokenAddress,
		uint256 _exactAmountOut,
		uint256 _maximumAmountIn
	) internal {
		uint256 amountIn = 0;

		TransferHelper.safeTransferFrom(_inputTokenAddress, msg.sender, address(this), _maximumAmountIn);
		TransferHelper.safeApprove(_inputTokenAddress, address(uniswapRouterContract), _maximumAmountIn);

		if (_params.isMultiSwap) {
			amountIn = uniswapRouterContract.exactOutput(
				ISwapRouter.ExactOutputParams({
					path: _params.path, // @dev to swap DAI for WETH9 through a USDC pool: abi.encodePacked(WETH9, poolFee, USDC, poolFee, DAI)
					recipient: _recipient,
					deadline: _params.deadline,
					amountOut: _exactAmountOut,
					amountInMaximum: _maximumAmountIn
				})
			);
		} else {
			amountIn = uniswapRouterContract.exactOutputSingle(
				ISwapRouter.ExactOutputSingleParams({
					tokenIn: _inputTokenAddress,
					tokenOut: _outputTokenAddress,
					fee: _params.fee,
					recipient: _recipient,
					deadline: _params.deadline,
					amountOut: _exactAmountOut,
					amountInMaximum: _maximumAmountIn,
					sqrtPriceLimitX96: _params.sqrtPriceLimitX96
				})
			);
		}

		TransferHelper.safeApprove(_inputTokenAddress, address(uniswapRouterContract), 0);

		// refund leftover
		if (amountIn < _maximumAmountIn) {
			TransferHelper.safeTransfer(_inputTokenAddress, msg.sender, _maximumAmountIn - amountIn);
		}
	}

	/**
	 * @notice Swaps as little as possible of native coin for :_exactAmountOut: of output token using Uniswap V3
	 *
	 * @param _params - parameters necessary for the swap
	 * @param _recipient - the one who receives output tokens
	 * @param _inputTokenAddress - WETH9 token address; always will be since the function is internal, this is cheaper
	 * @param _outputTokenAddress - address of the output token
	 * @param _exactAmountOut - amount of the desired token that should be swapped
	 * @param _maximumAmountIn - maximum amount of native coin one is willing to spend for the swap
	 *
	 * No return, reverts on error
	 */
	function _swapEthForToken(
		SwapParameters memory _params,
		address _recipient,
		address _inputTokenAddress,
		address _outputTokenAddress,
		uint256 _exactAmountOut,
		uint256 _maximumAmountIn
	) internal {
		uint256 amountIn = 0;

		if (_params.isMultiSwap) {
			amountIn = uniswapRouterContract.exactOutput{ value: _maximumAmountIn }(
				ISwapRouter.ExactOutputParams({
					path: _params.path,
					recipient: _recipient,
					deadline: _params.deadline,
					amountOut: _exactAmountOut,
					amountInMaximum: _maximumAmountIn
				})
			);
		} else {
			amountIn = uniswapRouterContract.exactOutputSingle{ value: _maximumAmountIn }(
				ISwapRouter.ExactOutputSingleParams({
					tokenIn: _inputTokenAddress,
					tokenOut: _outputTokenAddress,
					fee: _params.fee,
					recipient: _recipient,
					deadline: _params.deadline,
					amountOut: _exactAmountOut,
					amountInMaximum: _maximumAmountIn,
					sqrtPriceLimitX96: _params.sqrtPriceLimitX96
				})
			);
		}

		// refund leftover
		if (_maximumAmountIn > amountIn) {
			IPeripheryPayments(address(uniswapRouterContract)).refundETH();
			(bool success, ) = msg.sender.call{ value: _maximumAmountIn - amountIn }('');
			require(success, 'BizzSwap::_swapEthForToken: Refund failed');
		}
	}

	/**
	 * @notice Swaps as little as possible of input token for :_exactAmountOut: of native coin
	 *
	 * @param _params - parameters necessary for the swap
	 * @param _recipient - the one who receives native coins
	 * @param _inputTokenAddress - address of the input token
	 * @param _outputTokenAddress - WETH9 token address; always will be since the function is internal, this is cheaper
	 * @param _exactAmountOut - amount of the desired coin that should be swapped
	 * @param _maximumAmountIn - maximum amount of the input token one is willing to spend for the swap
	 *
	 * No return, reverts on error
	 */
	function _swapTokenForEth(
		SwapParameters memory _params,
		address _recipient,
		address _inputTokenAddress,
		address _outputTokenAddress,
		uint256 _exactAmountOut,
		uint256 _maximumAmountIn
	) internal {
		address WETH9 = IPeripheryImmutableState(address(uniswapRouterContract)).WETH9();

		if (_inputTokenAddress == WETH9) {
			// receive WETH9 exactAmountOut of tokens
			TransferHelper.safeTransferFrom(_inputTokenAddress, msg.sender, address(this), _exactAmountOut);
		} else {
			// or swap input token for exactAmountOut of WETH9 tokens
			_swap(_params, address(this), _inputTokenAddress, _outputTokenAddress, _exactAmountOut, _maximumAmountIn);
		}

		// Then, Unwrap WETH9 amount of tokens in contract and send it to the recipient
		IWETH9(WETH9).withdraw(_exactAmountOut);
		TransferHelper.safeTransferETH(_recipient, _exactAmountOut);
	}

	/**
	 * @notice Executes one on one token payment
	 *
	 * @param _params - parameters necessary for the swap
	 * @param _recipient - the one who receives output tokens
	 * @param _inputTokenAddress - address of the input token
	 * @param _outputTokenAddress - address of the output token
	 * @param _exactAmountOut - amount of the desired token that should be swapped
	 * @param _maximumAmountIn - maximum amount of input token one is willing to spend for the swap
	 *
	 * No return, reverts on error
	 */
	function _swapTokens(
		SwapParameters memory _params,
		address _recipient,
		address _inputTokenAddress,
		address _outputTokenAddress,
		uint256 _exactAmountOut,
		uint256 _maximumAmountIn
	) internal {
		if (_inputTokenAddress == _outputTokenAddress) {
			TransferHelper.safeTransferFrom(_inputTokenAddress, msg.sender, _recipient, _exactAmountOut);
		} else {
			_swap(_params, _recipient, _inputTokenAddress, _outputTokenAddress, _exactAmountOut, _maximumAmountIn);
		}
	}

	/**
	 * @notice Deposits native coin to get wrapped token representation of the native coin
	 *
	 * @param _weth9 - WETH9 token address
	 * @param _exactAmountOut - the amount of native coin to be wrapped
	 * @param _recipient - the one who receives output tokens
	 *
	 * No return, reverts on error
	 */
	function _wrapEth(
		address _weth9,
		uint256 _exactAmountOut,
		address _recipient
	) internal {
		IWETH9(_weth9).deposit{ value: _exactAmountOut }();
		TransferHelper.safeTransfer(_weth9, _recipient, _exactAmountOut);

		// refund leftover
		if (msg.value > _exactAmountOut) {
			TransferHelper.safeTransferETH(msg.sender, msg.value - _exactAmountOut);
		}
	}

	/**
	 * @notice Transfer :_exactAmountOut: of native coins to the :_recipient:
	 *
	 * @param _exactAmountOut - the amount of native coin to transfer
	 * @param _recipient - the one who receives output coins
	 *
	 * No return, reverts on error
	 */
	function _transferEth(address _recipient, uint256 _exactAmountOut) internal {
		TransferHelper.safeTransferETH(_recipient, _exactAmountOut);

		// refund leftover
		if (msg.value > _exactAmountOut) {
			TransferHelper.safeTransferETH(msg.sender, msg.value - _exactAmountOut);
		}
	}
}

