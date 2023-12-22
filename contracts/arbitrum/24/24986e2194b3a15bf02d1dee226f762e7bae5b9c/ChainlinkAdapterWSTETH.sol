// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {IChainlinkAdapter} from "./IChainlinkAdapter.sol";
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

/// @title WSTETHOracle Contract
/// @notice Provides wstETH/USD price using stETH/USD Chainlink oracle and wstETH/stETH exchange rate provided by stETH smart contract
/// @author Radiant
contract ChainlinkAdapterWSTETH is OwnableUpgradeable, IChainlinkAdapter {
	/// @notice stETH/USD price feed
	IChainlinkAdapter public stETHUSDOracle;
	/// @notice wstETHRatio feed
	IChainlinkAdapter public stEthPerWstETHOracle;

	error AddressZero();

	/**
	 * @notice Initializer
	 * @param _stETHUSDOracle stETH/USD price feed
	 * @param _stEthPerWstETHOracle wstETHRatio feed
	 */
	function initialize(address _stETHUSDOracle, address _stEthPerWstETHOracle) public initializer {
		if (_stETHUSDOracle == address(0)) revert AddressZero();
		if (_stEthPerWstETHOracle == address(0)) revert AddressZero();

		stETHUSDOracle = IChainlinkAdapter(_stETHUSDOracle); // 8 decimals
		stEthPerWstETHOracle = IChainlinkAdapter(_stEthPerWstETHOracle); // 18 decimals
		__Ownable_init();
	}

	/**
	 * @notice Returns wstETH/USD price. Checks for Chainlink oracle staleness with validate() in BaseChainlinkAdapter
	 * @return answer wstETH/USD price with 8 decimals
	 */
	function latestAnswer() external view returns (uint256 answer) {
		// decimals 8
		uint256 stETHPrice = stETHUSDOracle.latestAnswer();
		// decimals 18
		uint256 wstETHRatio = stEthPerWstETHOracle.latestAnswer();
		answer = (stETHPrice * wstETHRatio) / 1 ether;
	}

	function decimals() external view returns (uint8) {
		return 8;
	}
}

