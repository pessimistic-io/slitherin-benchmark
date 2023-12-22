// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./Pausable.sol";
import "./Ownable.sol";
import "./IWINROracleRouter.sol";
import "./IPriceFeed.sol";
import "./IChainlinkFlags.sol";

contract WINROracleRouter is Pausable, Ownable, IWINROracleRouter {
	uint256 public constant PRICE_PRECISION = 1e30;
	uint256 public constant ONE_USD = PRICE_PRECISION;
	uint256 public constant CHAINLINK_PRICE_PRECISION = 1e8;
	address private constant FLAG_ARBITRUM_SEQ_OFFLINE =
		address(
			bytes20(
				bytes32(
					uint256(keccak256("chainlink.flags.arbitrum-seq-offline")) -
						1
				)
			)
		);

	address public immutable controllerAddress;
	address public immutable chainlinkFlagAddress;
	IChainlinkFlags public immutable chainlinkFlags;

	// tokenaddress => chainlink price feed address
	mapping(address => address) public priceFeeds;

	mapping(address => IPriceFeed) public priceFeedsInterface;

	// tokenaddress => price decimals of cl return
	mapping(address => uint256) public priceDecimals;

	// tokenaddress => is stablecoin
	mapping(address => bool) public isStableCoin;

	constructor(address _controllerAddress, address _chainlinkFlagAddress) {
		controllerAddress = _controllerAddress;
		chainlinkFlagAddress = _chainlinkFlagAddress;
		chainlinkFlags = IChainlinkFlags(_chainlinkFlagAddress);
		_transferOwnership(_controllerAddress);
	}

	function pauseOracle() external onlyOwner {
		_pause();
	}

	function unpauseOracle() external onlyOwner {
		_unpause();
	}

	function addToken(
		address _token,
		address _priceFeed,
		uint256 _priceDecimals,
		bool _isStableCoin
	) external onlyOwner {
		// check if token is already added
		require(priceFeeds[_token] == address(0), "WINROracleRouter: token exists");

		IPriceFeed priceFeed = IPriceFeed(_priceFeed);

		// check if price feed is valid
		int256 latestAnswer = priceFeed.latestAnswer();
		require(latestAnswer > 0, "WINROracleRouter: invalid price feed");

		// check if latestRound is non zero
		uint80 latestRound = priceFeed.latestRound();
		require(latestRound > 0, "WINROracleRouter: invalid price feed");

		priceFeeds[_token] = _priceFeed;
		priceFeedsInterface[_token] = IPriceFeed(_priceFeed);
		priceDecimals[_token] = _priceDecimals;
		isStableCoin[_token] = _isStableCoin;

		emit TokenAdded(_token, _priceFeed, _priceDecimals, _isStableCoin);
	}

	// add remove token function
	function removeToken(address _token) external onlyOwner {
		require(priceFeeds[_token] != address(0), "WINROracleRouter: token not exists");
		delete priceFeeds[_token];
		delete priceFeedsInterface[_token];
		delete priceDecimals[_token];
		delete isStableCoin[_token];
		emit TokenRemoved(_token);
	}

	function getPriceMax(address _token) external view returns (uint256 price_) {
		_checkChainlinkFlagsAndPausable();
		price_ = _getPriceChainlink(_token);
	}

	function getPriceMin(address _token) external view returns (uint256 price_) {
		_checkChainlinkFlagsAndPausable();
		price_ = _getPriceChainlink(_token);
	}

	function _checkChainlinkFlagsAndPausable() internal view {
		_requireNotPaused();
		require(
			!chainlinkFlags.getFlag(FLAG_ARBITRUM_SEQ_OFFLINE),
			"WINROracleRouter: Arbitrum sequence is offline"
		);
	}

	function _getPriceChainlink(address _token) internal view returns (uint256 priceScaled_) {
		IPriceFeed feed_ = priceFeedsInterface[_token];
		require(address(feed_) != address(0), "WINROracleRouter: token not exists");
		int256 price_ = feed_.latestAnswer();
		require(price_ > 0, "WINROracleRouter: invalid price");
		unchecked {
			priceScaled_ =
				(uint256(price_) * PRICE_PRECISION) /
				CHAINLINK_PRICE_PRECISION;
		}
		if (isStableCoin[_token]) {
			priceScaled_ = priceScaled_ > ONE_USD ? ONE_USD : priceScaled_;
			return priceScaled_;
		} else {
			return priceScaled_;
		}
	}
}

