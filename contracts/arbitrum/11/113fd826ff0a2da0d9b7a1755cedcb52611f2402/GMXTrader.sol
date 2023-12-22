// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { BaseTrader } from "./BaseTrader.sol";

import { ITrader } from "./ITrader.sol";
import { IVault } from "./IVault.sol";
import { IVaultUtils } from "./IVaultUtils.sol";
import { IGlpRewardRouter } from "./IGlpRewardRouter.sol";
import { IGLPManager } from "./IGLPManager.sol";
import { IERC20 } from "./IERC20.sol";

import { GenericSwapRequest, GenericRequestExactInOutParams as RequestExactInOutParams } from "./TradingModel.sol";

import { TokenTransferrer } from "./TokenTransferrer.sol";
import { PathHelper } from "./PathHelper.sol";

import { PathHelper } from "./PathHelper.sol";
import { FullMath } from "./FullMath.sol";

contract GMXTrader is BaseTrader {
	using PathHelper for address[];

	error InvalidRoutPathLenght();

	uint256 public constant BASIS_POINTS_DIVISOR = 10_000;
	uint256 public constant PRICE_PRECISION = 10**30;

	IVault public vault;
	IVaultUtils public vaultUtils;
	address public usdg;

	address public sGLP;
	IGlpRewardRouter public glpRewardRouter;
	IGLPManager public glpManager;

	function setUp(
		address _vault,
		address _vaultUtils,
		address _usdg,
		address _sGLP,
		address _glpRewardRouter,
		address _glpManager
	)
		external
		initializer
		onlyContracts(_vault, _vaultUtils)
		onlyContracts(_usdg, _sGLP)
		onlyContracts(_glpRewardRouter, _glpManager)
	{
		__BASE_VESTA_INIT();

		vault = IVault(_vault);
		vaultUtils = IVaultUtils(_vaultUtils);
		usdg = _usdg;
		sGLP = _sGLP;
		glpRewardRouter = IGlpRewardRouter(_glpRewardRouter);
		glpManager = IGLPManager(_glpManager);
	}

	function setGLP(address _sGLP) external onlyOwner {
		sGLP = _sGLP;
	}

	function setGLPRewardRouter(address _glpRewardRouter) external onlyOwner {
		glpRewardRouter = IGlpRewardRouter(_glpRewardRouter);
	}

	function setGLPManager(address _glpManager) external onlyOwner {
		glpManager = IGLPManager(_glpManager);
	}

	function exchange(address _receiver, bytes memory _request)
		external
		override
		returns (uint256)
	{
		GenericSwapRequest memory request = _safeDecodeSwapRequest(_request);
		_validExpectingAmount(request.expectedAmountIn, request.expectedAmountOut);

		address[] memory path = request.path;
		uint256 amountIn = request.expectedAmountIn;

		if (amountIn == 0) {
			amountIn = this.getAmountIn(
				abi.encode(RequestExactInOutParams(path, request.expectedAmountOut))
			);
		}

		return _swap(request.path, amountIn, _receiver);
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

	function _swap(
		address[] memory _path,
		uint256 _amountIn,
		address _receiver
	) internal returns (uint256) {
		if (_path[0] == sGLP) {
			_performTokenTransferFrom(_path[0], msg.sender, address(this), _amountIn);
			return glpRewardRouter.unstakeAndRedeemGlp(_path[1], _amountIn, 0, _receiver);
		}

		_performTokenTransferFrom(_path[0], msg.sender, address(vault), _amountIn);

		if (_path.length == 2) {
			return _vaultSwap(_path[0], _path[1], _receiver);
		} else if (_path.length == 3) {
			uint256 midOut = _vaultSwap(_path[0], _path[1], address(this));
			_performTokenTransfer(_path[1], address(vault), midOut);
			return _vaultSwap(_path[1], _path[2], _receiver);
		}

		revert InvalidRoutPathLenght();
	}

	function _vaultSwap(
		address _tokenIn,
		address _tokenOut,
		address _receiver
	) internal returns (uint256 amountOut_) {
		if (_tokenOut == usdg) {
			amountOut_ = IVault(vault).buyUSDG(_tokenIn, _receiver);
		} else if (_tokenIn == usdg) {
			amountOut_ = IVault(vault).sellUSDG(_tokenOut, _receiver);
		} else {
			amountOut_ = IVault(vault).swap(_tokenIn, _tokenOut, _receiver);
		}

		return amountOut_;
	}

	function getAmountIn(bytes memory _request)
		external
		view
		override
		returns (uint256 amountIn_)
	{
		RequestExactInOutParams memory request = _safeDecodeRequestExactInOutParams(
			_request
		);

		address[] memory path = request.path;

		if (path.isSinglePath()) {
			amountIn_ = _getAmountIn(path[1], path[0], request.amount);
		} else {
			amountIn_ = _getAmountIn(path[2], path[1], request.amount);
			amountIn_ = _getAmountIn(path[1], path[0], amountIn_);
		}

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
		returns (uint256 _amountOut)
	{
		RequestExactInOutParams memory request = _safeDecodeRequestExactInOutParams(
			_request
		);

		address[] memory path = request.path;

		if (path.isSinglePath()) {
			_amountOut = _getAmountOut(path[0], path[1], request.amount);
		} else {
			_amountOut = _getAmountOut(path[0], path[1], request.amount);
			_amountOut = _getAmountOut(path[1], path[2], _amountOut);
		}

		return _amountOut;
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

	function _getAmountIn(
		address _tokenIn,
		address _tokenOut,
		uint256 _amount
	) internal view returns (uint256 amountIn_) {
		uint256 priceIn = _getTokenPrice(_tokenIn, false);
		uint256 priceOut = _getTokenPrice(_tokenOut, true);

		amountIn_ = vault.adjustForDecimals(
			FullMath.mulDiv(_amount, priceIn, priceOut),
			_tokenIn,
			_tokenOut
		);

		uint256 usdgAmount = vault.adjustForDecimals(
			FullMath.mulDiv(_amount, priceIn, PRICE_PRECISION),
			_tokenIn,
			usdg
		);

		uint256 feeBasisPoints = vaultUtils.getSwapFeeBasisPoints(
			_tokenOut,
			_tokenIn,
			usdgAmount
		);

		return
			FullMath.mulDiv(
				amountIn_,
				(BASIS_POINTS_DIVISOR + feeBasisPoints),
				BASIS_POINTS_DIVISOR
			);
	}

	function _getAmountOut(
		address _tokenIn,
		address _tokenOut,
		uint256 _amount
	) internal view returns (uint256 amountOut_) {
		uint256 priceIn = _getTokenPrice(_tokenIn, false);
		uint256 priceOut = _getTokenPrice(_tokenOut, true);

		amountOut_ = vault.adjustForDecimals(
			FullMath.mulDiv(_amount, priceIn, priceOut),
			_tokenIn,
			_tokenOut
		);

		uint256 usdgAmount = vault.adjustForDecimals(
			FullMath.mulDiv(_amount, priceIn, PRICE_PRECISION),
			_tokenIn,
			usdg
		);

		uint256 feeBasisPoints = vaultUtils.getSwapFeeBasisPoints(
			_tokenIn,
			_tokenOut,
			usdgAmount
		);

		return
			FullMath.mulDiv(
				amountOut_,
				(BASIS_POINTS_DIVISOR - feeBasisPoints),
				BASIS_POINTS_DIVISOR
			);
	}

	function _getTokenPrice(address _token, bool _maximum)
		internal
		view
		returns (uint256 price_)
	{
		if (_token == sGLP) {
			price_ = (glpManager.getAum(_maximum) /
				IERC20(glpManager.glp()).totalSupply());
		} else if (_maximum) {
			price_ = vault.getMaxPrice(_token);
		} else {
			price_ = vault.getMinPrice(_token);
		}

		return price_;
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

