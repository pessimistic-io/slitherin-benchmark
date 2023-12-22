// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.7.5;

import "./UQ112x112.sol";
import "./FixedPoint.sol";
import "./UniswapV2Library.sol";

import "./IPriceOracle.sol";

contract SimpleUniswapOracle is IPriceOracle {
	using UQ112x112 for uint224;
	using FixedPoint for *;
	
	uint32 public constant MIN_T = 1800;
	
	struct Pair {
		uint256 price0CumulativeA;
		uint256 price0CumulativeB;
		uint256 price1CumulativeA;
		uint256 price1CumulativeB;
		uint32 updateA;
		uint32 updateB;
		bool lastIsA;
		bool initialized;
	}

	address public immutable factory;

	mapping(address => Pair) public getPair;

	event PriceUpdate(address indexed pair, uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp, bool lastIsA);
	
	constructor(address factory_) {
 		factory = factory_;
	}

	function toUint224(uint256 input) internal pure returns (uint224) {
		require(input <= uint224(-1), "UniswapOracle: UINT224_OVERFLOW");
		return uint224(input);
	}
	
	function getPriceCumulativeCurrent(address uniswapV2Pair) internal view returns (uint256 price0Cumulative, uint256 price1Cumulative) {
		price0Cumulative = IUniswapV2Pair(uniswapV2Pair).price0CumulativeLast();
		price1Cumulative = IUniswapV2Pair(uniswapV2Pair).price1CumulativeLast();
		(uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(uniswapV2Pair).getReserves();
		uint32 timeElapsed = getBlockTimestamp() - blockTimestampLast; // overflow is desired
		
		// * never overflows, and + overflow is desired
		price0Cumulative += uint256(UQ112x112.encode(reserve1).uqdiv(reserve0)) * timeElapsed;
		price1Cumulative += uint256(UQ112x112.encode(reserve0).uqdiv(reserve1)) * timeElapsed;
	}
	
	function initialize(address uniswapV2Pair) external {
		Pair storage pairStorage = getPair[uniswapV2Pair];
		require(!pairStorage.initialized, "UniswapOracle: ALREADY_INITIALIZED");
		
		(uint256 price0CumulativeCurrent, uint256 price1CumulativeCurrent) = getPriceCumulativeCurrent(uniswapV2Pair);
		uint32 blockTimestamp = getBlockTimestamp();
		pairStorage.price0CumulativeA = price0CumulativeCurrent;
		pairStorage.price0CumulativeB = price0CumulativeCurrent;
		pairStorage.price1CumulativeA = price1CumulativeCurrent;
		pairStorage.price1CumulativeB = price1CumulativeCurrent;
		pairStorage.updateA = blockTimestamp;
		pairStorage.updateB = blockTimestamp;
		pairStorage.lastIsA = true;
		pairStorage.initialized = true;
		emit PriceUpdate(uniswapV2Pair, price0CumulativeCurrent, price1CumulativeCurrent, blockTimestamp, true);
	}
	
	function getResult(address uniswapV2Pair) public returns (uint224 price0, uint224 price1, uint32 T, uint32 lastUpdated) {
		Pair memory pair = getPair[uniswapV2Pair];
		require(pair.initialized, "UniswapOracle: NOT_INITIALIZED");
		Pair storage pairStorage = getPair[uniswapV2Pair];
				
		uint32 timestamp = getBlockTimestamp();
		uint32 updateLast = pair.lastIsA ? pair.updateA : pair.updateB;
		(uint256 price0CumulativeCurrent, uint256 price1CumulativeCurrent) = getPriceCumulativeCurrent(uniswapV2Pair);
		uint256 price0CumulativeLast;
		uint256 price1CumulativeLast;
		
		if (timestamp - updateLast >= MIN_T) {
			// update
			price0CumulativeLast = pair.lastIsA ? pair.price0CumulativeA : pair.price0CumulativeB;
			price1CumulativeLast = pair.lastIsA ? pair.price1CumulativeA : pair.price1CumulativeB;
			lastUpdated = timestamp;
			if (pair.lastIsA) {
				pairStorage.price0CumulativeB = price0CumulativeCurrent;
				pairStorage.price1CumulativeB = price1CumulativeCurrent;
				pairStorage.updateB = timestamp;
			} else {
				pairStorage.price0CumulativeA = price0CumulativeCurrent;
				pairStorage.price1CumulativeA = price1CumulativeCurrent;
				pairStorage.updateA = timestamp;
			}
			pairStorage.lastIsA = !pair.lastIsA;
			emit PriceUpdate(uniswapV2Pair, price0CumulativeCurrent, price1CumulativeCurrent, timestamp, !pair.lastIsA);
		}
		else {
			// don't update and return price using previous priceCumulative
			updateLast = lastUpdated = pair.lastIsA ? pair.updateB : pair.updateA;
			price0CumulativeLast = pair.lastIsA ? pair.price0CumulativeB : pair.price0CumulativeA;
			price1CumulativeLast = pair.lastIsA ? pair.price1CumulativeB : pair.price1CumulativeA;
		}
		
		T = timestamp - updateLast; // overflow is desired
		require(T >= MIN_T, "UniswapOracle: NOT_READY"); //reverts only if the pair has just been initialized
		// / is safe, and - overflow is desired
		price0 = toUint224((price0CumulativeCurrent - price0CumulativeLast) / T);
		price1 = toUint224((price1CumulativeCurrent - price1CumulativeLast) / T);
	}

	function getLastResult(address uniswapV2Pair) public view returns (uint224 price0, uint224 price1, uint32 T, uint32 lastUpdated) {
		Pair memory pair = getPair[uniswapV2Pair];
		require(pair.initialized, "UniswapOracle: NOT_INITIALIZED");

		(uint256 price0CumulativeCurrent, uint256 price1CumulativeCurrent) = getPriceCumulativeCurrent(uniswapV2Pair);

		// don't update and return price using previous priceCumulative
		uint32 updateLast = lastUpdated = pair.lastIsA ? pair.updateB : pair.updateA;
		uint256 price0CumulativeLast = pair.lastIsA ? pair.price0CumulativeB : pair.price0CumulativeA;
		uint256 price1CumulativeLast = pair.lastIsA ? pair.price1CumulativeB : pair.price1CumulativeA;

		T = getBlockTimestamp() - updateLast; // overflow is desired
		require(T >= MIN_T, "UniswapOracle: NOT_READY"); //reverts only if the pair has just been initialized
		// / is safe, and - overflow is desired
		price0 = toUint224((price0CumulativeCurrent - price0CumulativeLast) / T);
		price1 = toUint224((price1CumulativeCurrent - price1CumulativeLast) / T);
	}
	
	function consult(address tokenIn, uint amountIn, address tokenOut) external override returns (uint amountOut) {
		address pair = UniswapV2Library.pairFor(factory, tokenIn, tokenOut);
		(uint224 price0, uint224 price1, , ) = getResult(pair);

		(address token0,) = UniswapV2Library.sortTokens(tokenIn, tokenOut);
		uint224 price = price0;
		if (token0 == tokenOut) {
			price = price1;
		}

		amountOut = FixedPoint.uq112x112(price).mul(amountIn).decode144();
	}

	function consultReadonly(address tokenIn, uint amountIn, address tokenOut) external override view returns (uint amountOut) {
		address pair = UniswapV2Library.pairFor(factory, tokenIn, tokenOut);
		(uint224 price0, uint224 price1, , ) = getLastResult(pair);

		(address token0,) = UniswapV2Library.sortTokens(tokenIn, tokenOut);
		uint224 price = price0;
		if (token0 == tokenOut) {
			price = price1;
		}

		amountOut = FixedPoint.uq112x112(price).mul(amountIn).decode144();
	}

	/*** Utilities ***/
	
	function getBlockTimestamp() public view returns (uint32) {
		return uint32(block.timestamp % 2**32);
	}
}
