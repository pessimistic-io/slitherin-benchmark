// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { BaseTrader } from "./BaseTrader.sol";
import { ICurvePool } from "./ICurvePool.sol";

import { CurveSwapRequest, CurveRequestExactInOutParams as RequestExactInOutParams } from "./TradingModel.sol";
import { PoolConfig } from "./CurveModel.sol";

import { FullMath } from "./FullMath.sol";
import { IERC20 } from "./IERC20.sol";

contract CurveTrader is BaseTrader {
	error ExchangeReturnedRevert();
	error GetDyReturnedRevert();
	error PoolNotRegistered();
	error InvalidCoinsSize();

	event PoolRegistered(address indexed pool);
	event PoolUnRegistered(address indexed pool);

	uint256 public constant PRECISION = 1e27;
	uint128 public constant BPS_DEMOMINATOR = 10_000;
	uint8 public constant TARGET_DECIMALS = 18;

	mapping(address => PoolConfig) internal curvePools;

	modifier onlyRegistered(address _pool) {
		if (curvePools[_pool].tokens.length == 0) {
			revert PoolNotRegistered();
		}
		_;
	}

	function setUp() external initializer {
		__BASE_VESTA_INIT();
	}

	function registerPool(
		address _pool,
		uint8 _totalCoins,
		string calldata _get_dy_signature,
		string calldata _exchange_signature
	) external onlyOwner onlyContract(_pool) {
		if (_totalCoins < 2) revert InvalidCoinsSize();

		address[] memory tokens = new address[](_totalCoins);
		address token;

		for (uint256 i = 0; i < _totalCoins; ++i) {
			token = ICurvePool(_pool).coins(i);
			tokens[i] = token;

			_performApprove(token, _pool, MAX_UINT256);
		}

		curvePools[_pool] = PoolConfig({
			tokens: tokens,
			get_dy_signature: _get_dy_signature,
			exchange_signature: _exchange_signature
		});

		emit PoolRegistered(_pool);
	}

	function unregisterPool(address _pool) external onlyOwner onlyRegistered(_pool) {
		delete curvePools[_pool];
		emit PoolUnRegistered(_pool);
	}

	function exchange(address _receiver, bytes memory _request)
		external
		override
		returns (uint256 swapResponse_)
	{
		CurveSwapRequest memory request = _safeDecodeSwapRequest(_request);

		_validExpectingAmount(request.expectedAmountIn, request.expectedAmountOut);

		if (!isPoolRegistered(request.pool)) {
			revert PoolNotRegistered();
		}

		PoolConfig memory curve = curvePools[request.pool];
		address pool = request.pool;
		int128 i = int128(int8(request.coins[0]));
		int128 j = int128(int8(request.coins[1]));
		address tokenOut = curve.tokens[uint128(j)];

		if (request.expectedAmountIn == 0) {
			uint256 amountIn = _getExpectAmountIn(
				pool,
				curve.get_dy_signature,
				i,
				j,
				request.expectedAmountOut
			);

			request.expectedAmountIn =
				amountIn +
				FullMath.mulDiv(amountIn, request.slippage, BPS_DEMOMINATOR);
		} else {
			request.expectedAmountOut = _get_dy(
				pool,
				curve.get_dy_signature,
				i,
				j,
				request.expectedAmountIn
			);
		}

		_performTokenTransferFrom(
			curve.tokens[uint128(i)],
			msg.sender,
			address(this),
			request.expectedAmountIn
		);

		uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));

		(bool success, ) = pool.call{ value: 0 }(
			abi.encodeWithSignature(
				curve.exchange_signature,
				i,
				j,
				request.expectedAmountIn,
				request.expectedAmountOut,
				false
			)
		);

		if (!success) revert ExchangeReturnedRevert();

		uint256 balanceAfter = IERC20(tokenOut).balanceOf(address(this));
		uint256 result = balanceAfter - balanceBefore;

		_performTokenTransfer(curve.tokens[uint128(j)], _receiver, result);

		return result;
	}

	function _safeDecodeSwapRequest(bytes memory _request)
		internal
		view
		returns (CurveSwapRequest memory)
	{
		try this.decodeSwapRequest(_request) returns (CurveSwapRequest memory params) {
			return params;
		} catch {
			revert InvalidRequestEncoding();
		}
	}

	function decodeSwapRequest(bytes memory _request)
		external
		pure
		returns (CurveSwapRequest memory)
	{
		return abi.decode(_request, (CurveSwapRequest));
	}

	function getAmountIn(bytes memory _request)
		external
		view
		override
		returns (uint256 amountIn_)
	{
		RequestExactInOutParams memory params = _safeDecodeRequestExactInOutParams(
			_request
		);

		PoolConfig memory curve = curvePools[params.pool];

		amountIn_ = _getExpectAmountIn(
			params.pool,
			curve.get_dy_signature,
			int128(int8(params.coins[0])),
			int128(int8(params.coins[1])),
			params.amount
		);

		amountIn_ += FullMath.mulDiv(amountIn_, params.slippage, BPS_DEMOMINATOR);

		return amountIn_;
	}

	function _getExpectAmountIn(
		address _pool,
		string memory _get_dy_signature,
		int128 _coinA,
		int128 _coinB,
		uint256 _expectOut
	) internal view returns (uint256 amountIn_) {
		uint256 estimationIn = _get_dy(
			_pool,
			_get_dy_signature,
			_coinB,
			_coinA,
			_expectOut
		);
		uint256 estimationOut = _get_dy(
			_pool,
			_get_dy_signature,
			_coinA,
			_coinB,
			estimationIn
		);

		uint256 rate = FullMath.mulDiv(estimationIn, PRECISION, estimationOut);
		amountIn_ = FullMath.mulDiv(rate, _expectOut, PRECISION);
		amountIn_ += FullMath.mulDiv(
			amountIn_,
			EXACT_AMOUNT_IN_CORRECTION,
			CORRECTION_DENOMINATOR
		);

		return amountIn_;
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

		address pool = params.pool;

		return
			_get_dy(
				pool,
				curvePools[pool].get_dy_signature,
				int128(int8(params.coins[0])),
				int128(int8(params.coins[1])),
				params.amount
			);
	}

	function _get_dy(
		address _pool,
		string memory _signature,
		int128 i,
		int128 j,
		uint256 dx
	) internal view returns (uint256) {
		bool success;
		bytes memory data;

		(success, data) = _pool.staticcall(
			abi.encodeWithSignature(_signature, i, j, dx)
		);

		if (!success) {
			revert GetDyReturnedRevert();
		}

		return abi.decode(data, (uint256));
	}

	function _safeDecodeRequestExactInOutParams(bytes memory _request)
		internal
		view
		returns (RequestExactInOutParams memory)
	{
		try this.decodeDecodeRequestExactInOutParams(_request) returns (
			RequestExactInOutParams memory params
		) {
			return params;
		} catch {
			revert InvalidRequestEncoding();
		}
	}

	function decodeDecodeRequestExactInOutParams(bytes memory _request)
		external
		pure
		returns (RequestExactInOutParams memory)
	{
		return abi.decode(_request, (RequestExactInOutParams));
	}

	function getPoolConfigOf(address _pool) external view returns (PoolConfig memory) {
		return curvePools[_pool];
	}

	function isPoolRegistered(address _pool) public view returns (bool) {
		return curvePools[_pool].tokens.length != 0;
	}

	function generateSwapRequest(
		address _pool,
		uint8[2] calldata _coins,
		uint256 _expectedAmountIn,
		uint256 _expectedAmountOut,
		uint16 _slippage
	) external pure returns (bytes memory) {
		return
			abi.encode(
				CurveSwapRequest(
					_pool,
					_coins,
					_expectedAmountIn,
					_expectedAmountOut,
					_slippage
				)
			);
	}

	function generateExpectInOutRequest(
		address _pool,
		uint8[2] calldata _coins,
		uint256 _amount,
		uint16 _slippage
	) external pure returns (bytes memory) {
		return abi.encode(RequestExactInOutParams(_pool, _coins, _amount, _slippage));
	}
}


