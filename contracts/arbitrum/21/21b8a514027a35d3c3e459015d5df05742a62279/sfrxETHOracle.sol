// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "./IRamsesPair.sol";
import "./IOracle.sol";
import "./IERC20Metadata.sol";
import "./Ownable.sol";
import "./AggregatorV3Interface.sol";

contract sfrxETHOracle is IOracle, Ownable{

	struct VolatilityStats {
		uint256 lastRate;
		uint256 lastCheckTime;
		uint256 checkFrequency;
	}
	
	mapping(address => VolatilityStats) public assetStats;

	uint256 public maxDeviationAllowance;
	uint256 public maxDeviationForUpdate;

	AggregatorV3Interface public immutable chainlink;
	address public immutable frxETHETH;
	address public immutable weth;
	address public immutable frxETH;
	address public immutable sfrxETH;
	address public keeper;

	// Use to convert a price answer to an 18-digit precision uint
	uint256 public constant TARGET_DECIMAL_1E18 = 1e18;

	constructor(
		address _frxETHWETH,
		address _weth,
		address _frxETH,
		address _sfrxETH,
		address _chainlink
	) {
		require(_frxETHWETH != address(0), "Invalid frxETHETH address");
		require(_weth != address(0), "Invalid weth address");
		require(_chainlink != address(0), "Invalid chainlink address");
		
		weth = _weth;
		frxETH = _frxETH;
		frxETHETH = _frxETHWETH;
		chainlink = AggregatorV3Interface(_chainlink);
		sfrxETH = _sfrxETH;
		keeper = msg.sender;
		maxDeviationAllowance = 3e16; //3%
		maxDeviationForUpdate = 15e15; //1.5%

		assetStats[frxETH].checkFrequency = 3600; // 1 hour
		assetStats[sfrxETH].checkFrequency = 1 days;
	}

	function setKeeper(address _keeper) external onlyOwner {
		require(_keeper != address(0), "Invalid keeper address");
		keeper = _keeper;
	}

	/**
	* @notice Get the token price price for an underlying token address.
	* @return Price denominated in USDC
	*/
	function getDirectPrice() external view returns (uint256) {
		uint256 _WETHUSDPrice = _getChainlinkPrice();
		uint256 _frxETHPrice = priceRamses(weth, IRamsesPair(frxETHETH));
		uint256 _frxETHAnchorPrice = assetStats[frxETH].lastRate;
		uint256 _sfrxRates = assetStats[sfrxETH].lastRate;

		require(_validatePrice(_frxETHPrice, _frxETHAnchorPrice, maxDeviationAllowance), "Price deviation too large");
		require(block.timestamp - assetStats[sfrxETH].lastCheckTime < assetStats[sfrxETH].checkFrequency + 30 * 60
		,"Price record is too old");

		uint256 _frxETHPriceUSD = _WETHUSDPrice * _frxETHPrice / TARGET_DECIMAL_1E18;
		return _frxETHPriceUSD * _sfrxRates / TARGET_DECIMAL_1E18;
	}

	/**
	* @notice Get and Update the token price price for an underlying token address.
	* @return Price denominated in　USDC
	*/
	function fetchPrice() external returns (uint256) {
			
		uint256 _WETHUSDPrice = _getChainlinkPrice();
		uint256 _frxETHPrice = priceRamses(weth, IRamsesPair(frxETHETH));
		uint256 _frxETHAnchorPrice = assetStats[frxETH].lastRate;
		uint256 _sfrxRates = assetStats[sfrxETH].lastRate;

		require(_validatePrice(_frxETHPrice, _frxETHAnchorPrice, maxDeviationAllowance), "Price deviation too large");
	 	require(block.timestamp - assetStats[sfrxETH].lastCheckTime < assetStats[sfrxETH].checkFrequency + 30 * 60
 		,"Price record is too old");

		uint256 _frxETHPriceUSD = _WETHUSDPrice * _frxETHPrice / TARGET_DECIMAL_1E18;
		return _frxETHPriceUSD * _sfrxRates / TARGET_DECIMAL_1E18;

	}

	/**
	* @notice Return true if price update is needed
	* @return true or false
	*/
	function isRateUpdateNeeded (address _token, uint256 _price) external view returns (bool) {
		require(assetStats[_token].checkFrequency > 0, "Invalid token address");
		uint256 _updateTime = assetStats[_token].lastCheckTime +  assetStats[_token].checkFrequency; 
		bool isPriceValid = true;
		if(_token == frxETH){
			isPriceValid = _validatePrice(_price, assetStats[_token].lastRate, maxDeviationForUpdate);
		}
		if(block.timestamp > _updateTime || !isPriceValid ){
			return true;
		} else {
			return false;
		}
	}

	function setDeviationAlloance(uint256 _allowance) external onlyOwner {
		maxDeviationAllowance = _allowance;
	}

	function setDeviationForUpdate(uint256 _deviation) external onlyOwner {
		maxDeviationForUpdate = _deviation;
	}
	
	function setCheckFrequency(address _token, uint256 _frequency) external onlyOwner {
		require(assetStats[_token].checkFrequency > 0, "Invalid token address");
		assetStats[_token].checkFrequency = _frequency;
	}

	function getCheckFrequency(address _token) external view returns (uint256) {
		return assetStats[_token].checkFrequency;
	}
	
	function commitRate(address _token, uint256 _rates, uint256 _time) external {
		require(msg.sender == keeper, "Only keeper can commit rates");
		require(assetStats[_token].checkFrequency > 0, "Invalid token address");
		require(_time > assetStats[_token].lastCheckTime, "Time does not go back");
		require(_time < block.timestamp + 3, "Future time");
		assetStats[_token].lastRate = _rates;
		assetStats[_token].lastCheckTime = _time;
	}

	function getRate(address _token) external view returns (uint256) {
		return assetStats[_token].lastRate;
	}

	/**
	* @dev Fetches the price for a token from Solidly Pair
	*/
	function priceRamses(address _baseToken, IRamsesPair _pair) public view returns (uint256) {

		address _token0 = _pair.token0();
		address _token1 = _pair.token1();
		address _quoteToken;

		_baseToken == _token0 ? _quoteToken = _token1 : _quoteToken = _token0;

		// base token is USD or another token
		uint256 _baseTokensPerQuoteToken = _pair.current(_quoteToken, 10**uint256(IERC20Metadata(_quoteToken).decimals()));
		
		// scale tokenPrice by TARGET_DECIMAL_1E18
		uint256 _baseTokenDecimals = uint256(IERC20Metadata(_baseToken).decimals());
		uint256 _tokenPriceScaled;

		if (_baseTokenDecimals > 18) {
			_tokenPriceScaled = _baseTokensPerQuoteToken / (10**(_baseTokenDecimals - 18));
		} else {
			_tokenPriceScaled = _baseTokensPerQuoteToken * (10**(18 - _baseTokenDecimals));
		}
	
		return _tokenPriceScaled;

	}

	function _validatePrice(uint256 _price, uint256 _anchorPrice, uint256 _maxDeviationRate) internal pure returns (bool) {
		require(_price > 0, "Price is zero");
		uint256 _maxDeviation = _anchorPrice * _maxDeviationRate / TARGET_DECIMAL_1E18;
		if(_price > _anchorPrice){
			uint256 _deviation = _price - _anchorPrice;
			return _deviation <= _maxDeviation;
		} else {
			uint256 _deviation = _anchorPrice - _price;
			return _deviation <= _maxDeviation;
		}
	}

	function _getChainlinkPrice() internal view returns (uint256) {
		(, int256 _priceInt, , uint256 _updatedAt, ) = chainlink.latestRoundData();
		require(_updatedAt > block.timestamp - 24 hours, "Chainlink price outdated");
		return uint256(_priceInt) * TARGET_DECIMAL_1E18 / 1e8;
	}
	
}
