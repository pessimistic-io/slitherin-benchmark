// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { BaseTrader } from "./BaseTrader.sol";

import { ISwapRouter } from "./ISwapRouter.sol";
import { TokenTransferrer } from "./TokenTransferrer.sol";

import { UniswapV3SwapRequest, UniswapV3RequestExactInOutParams as RequestExactInOutParams } from "./TradingModel.sol";
import "./UniswapV3Model.sol";

import { IQuoter } from "./IQuoter.sol";
import { IUniswapV3Factory } from "./IUniswapV3Factory.sol";
import { UniswapV3QuoterLibrary } from "./UniswapV3QuoterLibrary.sol";

contract UniswapV3Trader is TokenTransferrer, BaseTrader {
	using UniswapV3QuoterLibrary for IUniswapV3Factory;
	error InvalidPathEncoding();

	ISwapRouter public router;
	IQuoter public quoter;
	IUniswapV3Factory public v3Factory;

	function setUp(
		address _router,
		address _quoter,
		address _v3Factory
	) external initializer onlyContracts(_router, _quoter) onlyContract(_v3Factory) {
		__BASE_VESTA_INIT();
		router = ISwapRouter(_router);
		quoter = IQuoter(_quoter);
		v3Factory = IUniswapV3Factory(_v3Factory);
	}

	function setRouter(address _router) external onlyOwner {
		router = ISwapRouter(_router);
	}

	function setQuoter(address _quoter) external onlyOwner {
		quoter = IQuoter(_quoter);
	}

	function setV3Factory(address _v3Factory) external onlyOwner {
		v3Factory = IUniswapV3Factory(_v3Factory);
	}

	function exchange(address _receiver, bytes memory _request)
		external
		override
		onlyValidAddress(_receiver)
		returns (uint256 swapResponse_)
	{
		UniswapV3SwapRequest memory request = _safeDecodeSwapRequest(_request);
		bytes memory path = request.path;

		_validExpectingAmount(request.expectedAmountIn, request.expectedAmountOut);

		if (!request.usingHop) {
			(address tokenOut, uint24 poolFee) = _safeDecodeSingleHopPath(path);

			return
				(request.expectedAmountIn != 0)
					? _swapExactInputSingleHop(
						_receiver,
						request.tokenIn,
						tokenOut,
						poolFee,
						request.expectedAmountIn
					)
					: _swapExactOutputSingleHop(
						_receiver,
						request.tokenIn,
						tokenOut,
						poolFee,
						request.expectedAmountOut,
						request.amountInMaximum
					);
		} else {
			bytes memory correctedPath = sanitizeMultiHopForUniswap(
				path,
				request.expectedAmountIn != 0
			);

			return
				(request.expectedAmountIn != 0)
					? _swapExactInputMultiHop(
						correctedPath,
						_receiver,
						request.tokenIn,
						request.expectedAmountIn
					)
					: _swapExactOutputMultiHop(
						correctedPath,
						_receiver,
						request.tokenIn,
						request.expectedAmountOut,
						request.amountInMaximum
					);
		}
	}

	function _swapExactInputSingleHop(
		address _receiver,
		address _tokenIn,
		address _tokenOut,
		uint24 _poolFee,
		uint256 _amountIn
	) internal returns (uint256 amountOut_) {
		_performTokenTransferFrom(_tokenIn, msg.sender, address(this), _amountIn);
		_tryPerformMaxApprove(_tokenIn, address(router));

		ExactInputSingleParams memory params = ExactInputSingleParams({
			tokenIn: _tokenIn,
			tokenOut: _tokenOut,
			fee: _poolFee,
			recipient: _receiver,
			deadline: block.timestamp,
			amountIn: _amountIn,
			amountOutMinimum: 0,
			sqrtPriceLimitX96: 0
		});

		amountOut_ = router.exactInputSingle(params);

		return amountOut_;
	}

	function _swapExactOutputSingleHop(
		address _receiver,
		address _tokenIn,
		address _tokenOut,
		uint24 _poolFee,
		uint256 _amountOut,
		uint256 _amountInMaximum
	) internal returns (uint256 amountIn_) {
		if (_amountInMaximum == 0) {
			_amountInMaximum = quoter.quoteExactOutputSingle(
				_tokenIn,
				_tokenOut,
				_poolFee,
				_amountOut,
				0
			);
		}

		_performTokenTransferFrom(_tokenIn, msg.sender, address(this), _amountInMaximum);
		_tryPerformMaxApprove(_tokenIn, address(router));

		ExactOutputSingleParams memory params = ExactOutputSingleParams({
			tokenIn: _tokenIn,
			tokenOut: _tokenOut,
			fee: _poolFee,
			recipient: _receiver,
			deadline: block.timestamp,
			amountOut: _amountOut,
			amountInMaximum: _amountInMaximum,
			sqrtPriceLimitX96: 0
		});

		amountIn_ = router.exactOutputSingle(params);

		if (amountIn_ < _amountInMaximum) {
			_performTokenTransfer(_tokenIn, msg.sender, _amountInMaximum - amountIn_);
		}

		return amountIn_;
	}

	function _swapExactInputMultiHop(
		bytes memory _path,
		address _receiver,
		address _tokenIn,
		uint256 _amountIn
	) internal returns (uint256 amountOut_) {
		_performTokenTransferFrom(_tokenIn, msg.sender, address(this), _amountIn);
		_tryPerformMaxApprove(_tokenIn, address(router));

		ExactInputParams memory params = ExactInputParams({
			path: _path,
			recipient: _receiver,
			deadline: block.timestamp,
			amountIn: _amountIn,
			amountOutMinimum: 0
		});

		return router.exactInput(params);
	}

	function _swapExactOutputMultiHop(
		bytes memory _path,
		address _receiver,
		address _tokenIn,
		uint256 _amountOut,
		uint256 _amountInMaximum
	) internal returns (uint256 amountIn_) {
		if (_amountInMaximum == 0) {
			_amountInMaximum = quoter.quoteExactOutput(_path, _amountOut);
		}

		_performTokenTransferFrom(_tokenIn, msg.sender, address(this), _amountInMaximum);
		_tryPerformMaxApprove(_tokenIn, address(router));

		ExactOutputParams memory params = ExactOutputParams({
			path: _path,
			recipient: _receiver,
			deadline: block.timestamp,
			amountOut: _amountOut,
			amountInMaximum: _amountInMaximum
		});

		amountIn_ = router.exactOutput(params);

		if (amountIn_ < _amountInMaximum) {
			_performTokenTransfer(_tokenIn, msg.sender, _amountInMaximum - amountIn_);
		}

		return amountIn_;
	}

	function getAmountIn(bytes memory _request)
		external
		view
		override
		returns (uint256)
	{
		RequestExactInOutParams memory params = _safeDecodeRequestInOutParams(_request);

		return (
			_getAmountIn(params.tokenIn, params.amount, params.path, params.usingHop)
		);
	}

	function _getAmountIn(
		address _tokenIn,
		uint256 _amountOut,
		bytes memory _path,
		bool _usingHop
	) internal view returns (uint256) {
		uint256 cachedOut = _amountOut;
		if (_usingHop) {
			(
				address tokenIn,
				uint24 feeA,
				address tokenOutIn,
				uint24 feeB,
				address tokenOut
			) = _safeDecodeMultiHopPath(_path);

			return
				_getEstimateSwap(
					tokenOutIn,
					tokenIn,
					feeB,
					_getEstimateSwap(tokenOut, tokenOutIn, feeA, cachedOut, false),
					false
				);
		} else {
			(address tokenOut, uint24 fee) = _safeDecodeSingleHopPath(_path);
			return _getEstimateSwap(tokenOut, _tokenIn, fee, cachedOut, false);
		}
	}

	function getAmountOut(bytes memory _request)
		external
		view
		override
		returns (uint256)
	{
		RequestExactInOutParams memory params = _safeDecodeRequestInOutParams(_request);

		return (
			_getAmountOut(params.tokenIn, params.amount, params.path, params.usingHop)
		);
	}

	function _getAmountOut(
		address _tokenIn,
		uint256 _amountIn,
		bytes memory _path,
		bool _usingHop
	) internal view returns (uint256) {
		uint256 cachedIn = _amountIn;
		if (_usingHop) {
			(
				address tokenIn,
				uint24 feeA,
				address tokenOutIn,
				uint24 feeB,
				address tokenOut
			) = _safeDecodeMultiHopPath(_path);

			return
				_getEstimateSwap(
					tokenOutIn,
					tokenOut,
					feeB,
					_getEstimateSwap(tokenIn, tokenOutIn, feeA, cachedIn, true),
					true
				);
		} else {
			(address tokenOut, uint24 fee) = _safeDecodeSingleHopPath(_path);
			return _getEstimateSwap(_tokenIn, tokenOut, fee, cachedIn, true);
		}
	}

	function _getEstimateSwap(
		address _tokenIn,
		address _tokenOut,
		uint24 _fee,
		uint256 _amount,
		bool _maximum
	) internal view virtual returns (uint256) {
		if (v3Factory.getPool(_tokenIn, _tokenOut, _fee) == address(0)) return 0;

		return
			_maximum
				? v3Factory.estimateMaxSwapUniswapV3(_tokenIn, _tokenOut, _amount, _fee)
				: v3Factory.estimateMinSwapUniswapV3(_tokenIn, _tokenOut, _amount, _fee);
	}

	function _safeDecodeSwapRequest(bytes memory _request)
		internal
		view
		returns (UniswapV3SwapRequest memory)
	{
		try this.decodeSwapRequest(_request) returns (
			UniswapV3SwapRequest memory request_
		) {
			return request_;
		} catch {
			revert InvalidRequestEncoding();
		}
	}

	function decodeSwapRequest(bytes memory _request)
		external
		pure
		returns (UniswapV3SwapRequest memory)
	{
		return abi.decode(_request, (UniswapV3SwapRequest));
	}

	function _safeDecodeSingleHopPath(bytes memory _path)
		internal
		view
		returns (address tokenOut_, uint24 fee_)
	{
		try this.decodeSingleHopPath(_path) returns (address tokenOut, uint24 fee) {
			return (tokenOut, fee);
		} catch {
			revert InvalidPathEncoding();
		}
	}

	function decodeSingleHopPath(bytes memory _path)
		external
		pure
		returns (address tokenOut_, uint24 fee_)
	{
		return abi.decode(_path, (address, uint24));
	}

	function _safeDecodeMultiHopPath(bytes memory _path)
		internal
		view
		returns (
			address tokenIn_,
			uint24 feeA_,
			address tokenOutIn_,
			uint24 feeB_,
			address tokenOut_
		)
	{
		try this.decodeMultiHopPath(_path) returns (
			address tokenIn,
			uint24 feeA,
			address tokenOutIn,
			uint24 feeB,
			address tokenOut
		) {
			return (tokenIn, feeA, tokenOutIn, feeB, tokenOut);
		} catch {
			revert InvalidPathEncoding();
		}
	}

	function decodeMultiHopPath(bytes memory _path)
		external
		pure
		returns (
			address tokenIn_,
			uint24 feeA_,
			address tokenOutIn_,
			uint24 feeB_,
			address tokenOut_
		)
	{
		return abi.decode(_path, (address, uint24, address, uint24, address));
	}

	function sanitizeMultiHopForUniswap(bytes memory _path, bool _withAmountIn)
		public
		view
		returns (bytes memory correctedPath_)
	{
		(
			address tokenIn,
			uint24 feeA,
			address tokenOutIn,
			uint24 feeB,
			address tokenOut
		) = _safeDecodeMultiHopPath(_path);

		return
			(_withAmountIn)
				? abi.encodePacked(tokenIn, feeA, tokenOutIn, feeB, tokenOut)
				: abi.encodePacked(tokenOut, feeB, tokenOutIn, feeA, tokenIn);
	}

	function _safeDecodeRequestInOutParams(bytes memory _request)
		internal
		view
		returns (RequestExactInOutParams memory)
	{
		try this.decodeRequestInOutParams(_request) returns (
			RequestExactInOutParams memory params
		) {
			return params;
		} catch {
			revert InvalidRequestEncoding();
		}
	}

	function decodeRequestInOutParams(bytes memory _request)
		external
		pure
		returns (RequestExactInOutParams memory)
	{
		return abi.decode(_request, (RequestExactInOutParams));
	}

	function generateSwapRequest(
		address _tokenMiddle,
		address _tokenOut,
		uint24 _poolFeeA,
		uint24 _poolFeeB,
		address _tokenIn,
		uint256 _expectedAmountIn,
		uint256 _expectedAmountOut,
		uint256 _amountInMaximum,
		bool _usingHop
	) external pure returns (bytes memory) {
		bytes memory path = _usingHop
			? abi.encode(_tokenIn, _poolFeeA, _tokenMiddle, _poolFeeB, _tokenOut)
			: abi.encode(_tokenOut, _poolFeeA);

		return
			abi.encode(
				UniswapV3SwapRequest(
					path,
					_tokenIn,
					_expectedAmountIn,
					_expectedAmountOut,
					_amountInMaximum,
					_usingHop
				)
			);
	}

	function generateExpectInOutRequest(
		address _tokenMiddle,
		address _tokenOut,
		uint24 _poolFeeA,
		uint24 _poolFeeB,
		address _tokenIn,
		uint256 _amount,
		bool _usingHop
	) external pure returns (bytes memory) {
		bytes memory path = _usingHop
			? abi.encode(_tokenIn, _poolFeeA, _tokenMiddle, _poolFeeB, _tokenOut)
			: abi.encode(_tokenOut, _poolFeeA);

		return abi.encode(RequestExactInOutParams(path, _tokenIn, _amount, _usingHop));
	}
}

