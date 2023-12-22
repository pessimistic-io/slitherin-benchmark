// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { BaseTrader } from "./BaseTrader.sol";

import { ITrader } from "./ITrader.sol";
import { IRouter02 } from "./IRouter02.sol";

import { GenericSwapRequest, GenericRequestExactInOutParams as RequestExactInOutParams } from "./TradingModel.sol";

import { TokenTransferrer } from "./TokenTransferrer.sol";
import { PathHelper } from "./PathHelper.sol";

contract UniswapV2Trader is BaseTrader {
	using PathHelper for address[];

	IRouter02 public router;

	function setUp(address _router) external onlyContract(_router) initializer {
		__BASE_VESTA_INIT();

		router = IRouter02(_router);
	}

	function exchange(address _receiver, bytes memory _request)
		external
		override
		returns (uint256 swapResponse_)
	{
		GenericSwapRequest memory request = _safeDecodeSwapRequest(_request);

		_validExpectingAmount(request.expectedAmountIn, request.expectedAmountOut);

		return
			(request.expectedAmountIn != 0)
				? _swapExactInput(_receiver, request.path, request.expectedAmountIn)
				: _swapExactOutput(_receiver, request.path, request.expectedAmountOut);
	}

	function _safeDecodeSwapRequest(bytes memory _request)
		internal
		view
		returns (GenericSwapRequest memory)
	{
		try this.decodeSwapRequest(_request) returns (
			GenericSwapRequest memory request_
		) {
			return request_;
		} catch {
			revert InvalidRequestEncoding();
		}
	}

	function decodeSwapRequest(bytes memory _request)
		external
		pure
		returns (GenericSwapRequest memory)
	{
		return abi.decode(_request, (GenericSwapRequest));
	}

	function _swapExactInput(
		address _receiver,
		address[] memory _path,
		uint256 _amountIn
	) internal returns (uint256 amountOut_) {
		address tokenIn = _path[0];

		_performTokenTransferFrom(tokenIn, msg.sender, address(this), _amountIn);
		_tryPerformMaxApprove(tokenIn, address(router));

		uint256[] memory values = router.swapExactTokensForTokens(
			_amountIn,
			0,
			_path,
			_receiver,
			block.timestamp
		);

		return values[values.length - 1];
	}

	function _swapExactOutput(
		address _receiver,
		address[] memory _path,
		uint256 _amountOut
	) internal returns (uint256 amountIn_) {
		address tokenIn = _path[0];
		uint256 amountInMax = router.getAmountsIn(_amountOut, _path)[0];

		_performTokenTransferFrom(tokenIn, msg.sender, address(this), amountInMax);
		_tryPerformMaxApprove(tokenIn, address(router));

		amountIn_ = router.swapTokensForExactTokens(
			_amountOut,
			amountInMax,
			_path,
			_receiver,
			block.timestamp
		)[0];

		if (amountIn_ < amountInMax) {
			_performTokenTransfer(tokenIn, msg.sender, amountInMax - amountIn_);
		}

		return amountIn_;
	}

	function getAmountIn(bytes memory _request)
		external
		view
		override
		returns (uint256)
	{
		RequestExactInOutParams memory params = _safeDecodeRequestExactInOutParams(
			_request
		);

		return router.getAmountsIn(params.amount, params.path)[0];
	}

	function getAmountOut(bytes memory _request)
		external
		view
		override
		returns (uint256)
	{
		RequestExactInOutParams memory params = _safeDecodeRequestExactInOutParams(
			_request
		);

		uint256[] memory values = router.getAmountsOut(params.amount, params.path);
		return values[values.length - 1];
	}

	function _safeDecodeRequestExactInOutParams(bytes memory _request)
		internal
		view
		returns (RequestExactInOutParams memory)
	{
		try this.decodeRequestExactInOutParams(_request) returns (
			RequestExactInOutParams memory params
		) {
			return params;
		} catch {
			revert InvalidRequestEncoding();
		}
	}

	function decodeRequestExactInOutParams(bytes memory _request)
		external
		pure
		returns (RequestExactInOutParams memory)
	{
		return abi.decode(_request, (RequestExactInOutParams));
	}

	function generateSwapRequest(
		address[] calldata _path,
		uint256 _expectedAmountIn,
		uint256 _expectedAmountOut
	) external pure returns (bytes memory) {
		return
			abi.encode(GenericSwapRequest(_path, _expectedAmountIn, _expectedAmountOut));
	}

	function generateExpectInOutRequest(address[] calldata _path, uint256 _amount)
		external
		pure
		returns (bytes memory)
	{
		return abi.encode(RequestExactInOutParams(_path, _amount));
	}
}


