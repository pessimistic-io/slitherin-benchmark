// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { BaseTrader } from "./BaseTrader.sol";

import { ISwapRouter } from "./ISwapRouter.sol";
import { TokenTransferrer } from "./TokenTransferrer.sol";

import { UniswapV3SwapRequest, UniswapV3RequestExactInOutParams as RequestExactInOutParams } from "./TradingModel.sol";
import "./UniswapV3Model.sol";

import { IQuoter } from "./IQuoter.sol";

contract UniswapV3Trader is TokenTransferrer, BaseTrader {
	error InvalidPathEncoding();

	ISwapRouter public router;
	IQuoter public quoter;

	function setUp(address _router, address _quoter)
		external
		initializer
		onlyContract(_router)
		onlyContract(_quoter)
	{
		__BASE_VESTA_INIT();
		router = ISwapRouter(_router);
		quoter = IQuoter(_quoter);
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
			bytes memory correctedPath = _safeCorrectMultiHopPath(
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

	function getAmountIn(bytes memory _request) external override returns (uint256) {
		RequestExactInOutParams memory params = _safeDecodeRequestInOutParams(_request);
		uint256 amount = params.amount;

		if (params.usingHop) {
			bytes memory path = _safeCorrectMultiHopPath(params.path, false);
			return quoter.quoteExactOutput(path, amount);
		} else {
			(address tokenOut, uint24 fee) = _safeDecodeSingleHopPath(params.path);
			return quoter.quoteExactOutputSingle(params.tokenIn, tokenOut, fee, amount, 0);
		}
	}

	function getAmountOut(bytes memory _request) external override returns (uint256) {
		RequestExactInOutParams memory params = _safeDecodeRequestInOutParams(_request);
		uint256 amount = params.amount;

		if (params.usingHop) {
			bytes memory path = _safeCorrectMultiHopPath(params.path, true);
			return quoter.quoteExactInput(path, amount);
		} else {
			(address tokenOut, uint24 fee) = _safeDecodeSingleHopPath(params.path);
			return quoter.quoteExactInputSingle(params.tokenIn, tokenOut, fee, amount, 0);
		}
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

	function _safeCorrectMultiHopPath(bytes memory _path, bool _withAmountIn)
		internal
		view
		returns (bytes memory correctedPath_)
	{
		try this.correctMultiHopPath(_path, _withAmountIn) returns (
			bytes memory correctedPath
		) {
			return correctedPath;
		} catch {
			revert InvalidPathEncoding();
		}
	}

	function correctMultiHopPath(bytes memory _path, bool _withAmountIn)
		external
		pure
		returns (bytes memory correctedPath_)
	{
		(
			address tokenIn,
			uint24 feeA,
			address tokenOutIn,
			uint24 feeB,
			address tokenOut
		) = abi.decode(_path, (address, uint24, address, uint24, address));

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


