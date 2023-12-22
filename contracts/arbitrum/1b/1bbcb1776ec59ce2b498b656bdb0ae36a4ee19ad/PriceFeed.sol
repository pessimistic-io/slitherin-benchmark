// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.7;

import "./BaseVesta.sol";
import { IPriceFeed } from "./IPriceFeed.sol";

import { Oracle, OracleAnswer } from "./OracleModels.sol";
import { IOracleVerificationV1 as Verificator } from "./IOracleVerificationV1.sol";
import { IOracleWrapper } from "./IOracleWrapper.sol";

contract PriceFeed is BaseVesta, IPriceFeed {
	Verificator public verificator;

	mapping(address => uint256) private lastGoodPrice;
	mapping(address => Oracle) private oracles;

	function setUp(address _verificator)
		external
		initializer
		onlyContract(_verificator)
	{
		__BASE_VESTA_INIT();
		verificator = Verificator(_verificator);
	}

	function fetchPrice(address _token) external override returns (uint256) {
		Oracle memory oracle = oracles[_token];

		if (oracle.primaryWrapper == address(0)) revert OracleNotFound();
		if (oracle.disabled) revert OracleDisabled();

		uint256 lastPrice = lastGoodPrice[_token];
		uint256 goodPrice = _getValidPrice(
			_token,
			oracle.primaryWrapper,
			oracle.secondaryWrapper,
			lastPrice
		);

		if (lastPrice != goodPrice) {
			lastGoodPrice[_token] = goodPrice;
			emit TokenPriceUpdated(_token, goodPrice);
		}

		return goodPrice;
	}

	function _getValidPrice(
		address _token,
		address primary,
		address secondary,
		uint256 lastPrice
	) internal view returns (uint256) {
		OracleAnswer memory primaryResponse = IOracleWrapper(primary).getPrice(_token);

		OracleAnswer memory secondaryResponse = secondary == address(0)
			? OracleAnswer(0, 0, 0)
			: IOracleWrapper(secondary).getPrice(_token);

		return verificator.verify(lastPrice, [primaryResponse, secondaryResponse]);
	}

	function addOracle(
		address _token,
		address _primaryOracle,
		address _secondaryOracle
	) external onlyOwner onlyContract(_primaryOracle) {
		Oracle storage oracle = oracles[_token];
		oracle.primaryWrapper = _primaryOracle;
		oracle.secondaryWrapper = _secondaryOracle;
		uint256 price = _getValidPrice(_token, _primaryOracle, _secondaryOracle, 0);

		if (price == 0) revert OracleDown();

		lastGoodPrice[_token] = price;

		emit OracleAdded(_token, _primaryOracle, _secondaryOracle);
	}

	function removeOracle(address _token) external onlyOwner {
		delete oracles[_token];
		emit OracleRemoved(_token);
	}

	function setOracleDisabledState(address _token, bool _disabled)
		external
		onlyOwner
	{
		oracles[_token].disabled = _disabled;
		emit OracleDisabledStateChanged(_token, _disabled);
	}

	function changeVerificator(address _verificator)
		external
		onlyOwner
		onlyContract(_verificator)
	{
		verificator = Verificator(_verificator);
		emit OracleVerificationChanged(_verificator);
	}

	function getOracle(address _token) external view override returns (Oracle memory) {
		return oracles[_token];
	}

	function isOracleDisabled(address _token) external view override returns (bool) {
		return oracles[_token].disabled;
	}

	function getLastUsedPrice(address _token)
		external
		view
		override
		returns (uint256)
	{
		return lastGoodPrice[_token];
	}

	function getExternalPrice(address _token)
		external
		view
		override
		returns (uint256[2] memory answers_)
	{
		Oracle memory oracle = oracles[_token];

		if (oracle.primaryWrapper == address(0)) {
			revert UnsupportedToken();
		}

		answers_[0] = IOracleWrapper(oracle.primaryWrapper)
			.getPrice(_token)
			.currentPrice;

		if (oracle.secondaryWrapper != address(0)) {
			answers_[1] = IOracleWrapper(oracle.secondaryWrapper)
				.getPrice(_token)
				.currentPrice;
		}

		return answers_;
	}
}

