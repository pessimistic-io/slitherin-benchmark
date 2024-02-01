// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./ERC20.sol";
import "./Crowdsale.sol";
import "./AllowanceCrowdsale.sol";
import "./TimedCrowdsale.sol";

contract SHIATokenCrowdsale is AllowanceCrowdsale, TimedCrowdsale {
	constructor(
		uint256 _rate,
		address payable _wallet,
		ERC20 _token,
		ERC20 _usdt,
		address _tokenWallet,
		uint256 _openingTime,
		uint256 _closingTime,

		uint256 maxInvestment,
        uint256 minInvestment
	)
		Crowdsale(_rate, _wallet, _token, _usdt, maxInvestment, minInvestment)
		AllowanceCrowdsale(_tokenWallet)
		TimedCrowdsale(_openingTime, _closingTime)
	{}

	/**
	 * @dev Extend parent behavior requiring to be within contributing period.
	 * @param beneficiary Token purchaser
	 * @param weiAmount Amount of wei contributed
	 */
	function _preValidatePurchase(address beneficiary, uint256 weiAmount)
		internal
		view
		override(Crowdsale, TimedCrowdsale)
		onlyWhileOpen
	{
		super._preValidatePurchase(beneficiary, weiAmount);
	}

	/**
	 * @dev Overrides parent behavior by transferring tokens from wallet.
	 * @param beneficiary Token purchaser
	 * @param tokenAmount Amount of tokens purchased
	 */
	function _deliverTokens(address beneficiary, uint256 tokenAmount)
		internal
		override(Crowdsale, AllowanceCrowdsale)
	{
		super._deliverTokens(beneficiary, tokenAmount);
	}
}

