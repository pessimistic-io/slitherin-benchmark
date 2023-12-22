// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./IChainlinkPricer.sol";
import "./IAddressBook.sol";
import "./IOracle.sol";
import "./AggregatorInterface.sol";

contract OpynPricerResolver {
	uint256 constant expiryHour = 8;
	uint256 constant secondsPerHour = 3600;
	uint256 constant secondsPerDay = secondsPerHour * 24;
	address constant pricerAsset = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH address mainnet
	address constant chainlinkPriceFeedAddress = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612; // ETH/USD on arbitrum

	IAddressBook addressBook;
	AggregatorInterface priceFeed = AggregatorInterface(chainlinkPriceFeedAddress);

	constructor(address _addressBook) {
		addressBook = IAddressBook(_addressBook);
	}

	function checker() external view returns (bool canExec, bytes memory execPayload) {
		uint256 currentTimestamp = block.timestamp;

		// if current time is not between 8 and 9am, do not execute.
		if (
			currentTimestamp % secondsPerDay < secondsPerHour * expiryHour ||
			currentTimestamp % secondsPerDay > secondsPerHour * (expiryHour + 1)
		) {
			return (false, bytes("Incorrect time"));
		}

		// take current timestamp, subtract amount of seconds through current day, add number of seconds in 8 hours.
		uint256 expiryTimestamp = currentTimestamp -
			(currentTimestamp % secondsPerDay) +
			(expiryHour * secondsPerHour);
		(uint256 expiryPrice, ) = IOracle(addressBook.getOracle()).getExpiryPrice(
			pricerAsset,
			expiryTimestamp
		);
		bool isLockingPeriodOver = IOracle(addressBook.getOracle()).isLockingPeriodOver(
			pricerAsset,
			expiryTimestamp
		);
		// check if otoken price is not on-chain and locking period over
		if (expiryPrice != 0 || !isLockingPeriodOver) {
			return (false, bytes("Price already set"));
		}

		uint256 priceRoundId = priceFeed.latestRound();
		uint256 priceRoundTimestamp = priceFeed.getTimestamp(priceRoundId);
		// check if latest chainlink round timestamp is greater than otoken expiry timestamp
		if (priceRoundTimestamp < expiryTimestamp) {
			return (false, bytes("latest chainlink price before expiry"));
		}

		uint256 previousRoundId;
		uint256 previousRoundTimestamp;
		// loop and decrease round id until previousRoundTimestamp < expiryTimestamp && priceRoundTimestamp >= expiryTimestamp
		// if previous round timestamp != 0 && less than expiry timestamp then exit => price round id found
		// else store previous round id in price round id (as we are searching for the first round id that it timestamp >= expiry timestamp)
		uint256 i = priceRoundId - 1;
		for (i; i > 0; i--) {
			previousRoundId = i;
			previousRoundTimestamp = priceFeed.getTimestamp(i);

			if (previousRoundTimestamp != 0) {
				if (previousRoundTimestamp < expiryTimestamp) {
					break;
				} else {
					priceRoundId = previousRoundId;
					priceRoundTimestamp = previousRoundTimestamp;
				}
			}
		}
		return (
			true,
			abi.encodeCall(IChainlinkPricer.setExpiryPriceInOracle, (expiryTimestamp, uint80(priceRoundId)))
		);
	}
}

