// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { IVestaDexTrader } from "./IVestaDexTrader.sol";
import "./TradingModel.sol";
import "./ICurvePool.sol";

import "./ITrader.sol";
import { IERC20, TokenTransferrer } from "./TokenTransferrer.sol";
import "./BaseVesta.sol";

/**
	Selectors (bytes16(keccak256("TRADER_FILE_NAME")))
	UniswapV3Trader: 0x0fa74b3ade106cd68a66c0ef6dfe2154
	CurveTrader: 0x79402703bca5d67f15c4e7e9841e7231
	UniswapV2Trader: 0x7eb272ca6b6d9e128a5589927962ba6d
	GMXTrader: 0xdc7e0e193e9fe90a4a7fbe7a768857c8
 */
contract VestaDexTrader is IVestaDexTrader, TokenTransferrer, BaseVesta {
	mapping(address => bool) internal registeredTrader;
	mapping(bytes16 => address) internal tradersAddress;

	function setUp() external initializer {
		__BASE_VESTA_INIT();
	}

	function registerTrader(bytes16 _selector, address _trader) external onlyOwner {
		registeredTrader[_trader] = true;
		tradersAddress[_selector] = _trader;

		emit TraderRegistered(_trader, _selector);
	}

	function removeTrader(bytes16 _selector, address _trader) external onlyOwner {
		delete registeredTrader[_trader];
		delete tradersAddress[_selector];

		emit TraderRemoved(_trader);
	}

	function exchange(
		address _receiver,
		address _firstTokenIn,
		uint256 _firstAmountIn,
		ManualExchange[] calldata _requests
	)
		external
		override
		onlyValidAddress(_receiver)
		returns (uint256[] memory swapDatas_)
	{
		uint256 length = _requests.length;

		if (length == 0) revert EmptyRequest();

		swapDatas_ = new uint256[](length);

		_performTokenTransferFrom(_firstTokenIn, msg.sender, SELF, _firstAmountIn);

		ManualExchange memory currentManualExchange;
		uint256 nextIn = _firstAmountIn;
		address trader;

		for (uint256 i = 0; i < length; ++i) {
			currentManualExchange = _requests[i];
			trader = tradersAddress[currentManualExchange.traderSelector];

			if (trader == address(0)) {
				revert InvalidTraderSelector();
			}

			_tryPerformMaxApprove(currentManualExchange.tokenInOut[0], trader);

			nextIn = ITrader(trader).exchange(
				i == length - 1 ? _receiver : SELF,
				_getFulfilledSwapRequest(
					currentManualExchange.traderSelector,
					currentManualExchange.data,
					nextIn
				)
			);

			swapDatas_[i] = nextIn;
		}

		emit SwapExecuted(
			msg.sender,
			_receiver,
			[_firstTokenIn, _requests[length - 1].tokenInOut[1]],
			[_firstAmountIn, swapDatas_[length - 1]]
		);

		return swapDatas_;
	}

	function _getFulfilledSwapRequest(
		bytes16 _traderSelector,
		bytes memory _encodedData,
		uint256 _amountIn
	) internal pure returns (bytes memory) {
		//UniswapV3Trader
		if (_traderSelector == 0x0fa74b3ade106cd68a66c0ef6dfe2154) {
			//Setting UniswapV3SwapRequest::expectedAmountIn
			assembly {
				mstore(add(_encodedData, 0x80), _amountIn)
			}

			return _encodedData;
		}
		//Cruve
		else if (_traderSelector == 0x79402703bca5d67f15c4e7e9841e7231) {
			//Setting CurveSwapRequest::expectedAmountIn
			//Setting CurveSwapRequest::slippage (if slippage != 0)
			assembly {
				mstore(add(_encodedData, 0x80), _amountIn)
			}

			return _encodedData;
		} else {
			//Setting GenericSwapRequest::expectedAmountIn
			assembly {
				mstore(add(_encodedData, 0x60), _amountIn)
			}

			return _encodedData;
		}
	}

	function getAmountIn(uint256 _amountOut, ManualExchange[] calldata _requests)
		external
		override
		returns (uint256 amountIn_)
	{
		uint256 length = _requests.length;

		ManualExchange memory path;
		address trader;

		uint256 lastAmountOut = _amountOut;
		while (length > 0) {
			length--;

			path = _requests[length];
			trader = tradersAddress[path.traderSelector];

			lastAmountOut = ITrader(trader).getAmountIn(
				_getFulfilledGetAmountInOut(path.traderSelector, path.data, lastAmountOut)
			);
		}

		return lastAmountOut;
	}

	function getAmountOut(uint256 _amountIn, ManualExchange[] calldata _requests)
		external
		override
		returns (uint256 amountOut_)
	{
		uint256 length = _requests.length;

		ManualExchange memory path;
		address trader;

		uint256 lastAmountIn = _amountIn;
		for (uint256 i = 0; i < length; ++i) {
			path = _requests[i];
			trader = tradersAddress[path.traderSelector];

			lastAmountIn = ITrader(trader).getAmountOut(
				_getFulfilledGetAmountInOut(path.traderSelector, path.data, lastAmountIn)
			);
		}

		return lastAmountIn;
	}

	function _getFulfilledGetAmountInOut(
		bytes16 _traderSelector,
		bytes memory _encodedData,
		uint256 _amount
	) internal pure returns (bytes memory) {
		if (_traderSelector == 0x0fa74b3ade106cd68a66c0ef6dfe2154) {
			UniswapV3SwapRequest memory request = abi.decode(
				_encodedData,
				(UniswapV3SwapRequest)
			);

			return
				abi.encode(
					UniswapV3RequestExactInOutParams(
						request.path,
						request.tokenIn,
						_amount,
						request.usingHop
					)
				);
		} else if (_traderSelector == 0x79402703bca5d67f15c4e7e9841e7231) {
			CurveSwapRequest memory request = abi.decode(_encodedData, (CurveSwapRequest));

			return
				abi.encode(
					CurveRequestExactInOutParams(
						request.pool,
						request.coins,
						_amount,
						request.slippage
					)
				);
		} else {
			GenericSwapRequest memory request = abi.decode(
				_encodedData,
				(GenericSwapRequest)
			);

			return abi.encode(GenericRequestExactInOutParams(request.path, _amount));
		}
	}

	function isRegisteredTrader(address _trader)
		external
		view
		override
		returns (bool)
	{
		return registeredTrader[_trader];
	}

	function getTraderAddressWithSelector(bytes16 _selector)
		external
		view
		override
		returns (address)
	{
		return tradersAddress[_selector];
	}
}


