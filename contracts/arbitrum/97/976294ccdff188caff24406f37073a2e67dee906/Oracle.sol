// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;
import "./OracleLibrary.sol";

contract Oracle {
	address public immutable pool;

	address private immutable WETH;
	address private immutable USDC;

	constructor(
		address _wethAddress,
		address _usdcAddress,
		address _poolAddress
	) {
		require(
			_wethAddress != address(0),
			"Crowdsale: _wethAddress is the zero address"
		);
		require(
			_usdcAddress != address(0),
			"Crowdsale: _usdcAddress is the zero address"
		);
		require(
			_poolAddress != address(0),
			"Crowdsale: _poolAddress is the zero address"
		);

		WETH = _wethAddress;
		USDC = _usdcAddress;
		pool = _poolAddress;
	}

	function usdAmount(uint128 _weiAmount) external view returns (uint256) {
		require(_weiAmount > 0, "invalid weiAmount");
		(int24 tick, ) = OracleLibrary.consult(pool, 60);

		uint256 amountOut = OracleLibrary.getQuoteAtTick(
			tick,
			_weiAmount,
			WETH,
			USDC
		);

		require(amountOut != 0, "oracle failed");
		return amountOut;
	}
}

