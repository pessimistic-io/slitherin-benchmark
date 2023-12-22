// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;
pragma abicoder v2;

import "./Market.sol";

abstract contract MarketCollateralised is Market {
	// MarketID => amount of collateral taken for this market
	mapping(bytes16 => uint256) private _marketCollateral;
	uint256 internal _totalCollateral;
	mapping(bytes16 => bytes16) internal _mostExpensivePropositionId;
	mapping(uint256 => uint256) internal _betExposure;

	function getMarketCollateral(
		bytes16 marketId
	) external view returns (uint256) {
		return _marketCollateral[marketId];
	}

	function _payout(uint256 index, uint8 result) internal override {
		require(
			_bets[index].payoutDate < block.timestamp,
			"_payout: Payout date not reached"
		);

		// Deduct from total exposure
		_totalExposure -= _betExposure[index];

		if (result == SCRATCHED) {
			// Transfer the bet amount to the owner of the NFT
			IERC20(_vault.asset()).transfer(
				ownerOf(index),
				_bets[index].amount
			);
		} 
		
		address underlying = _vault.asset();
		if (result == WINNER) {
			// Send the payout to the NFT owner
			_totalCollateral -= _betExposure[index];
			IERC20(underlying).transfer(ownerOf(index), _bets[index].payout);
		} else {
			// Else, the bet was a loser
			// Send the bet amount to the vault
			IERC20(underlying).transfer(address(_vault), _bets[index].amount);
		}
	}

	/*function _isMostExpensiveProposition(
		bytes16 propositionId,
		bytes16 marketId
	) internal view returns (bool) {
		return
			keccak256(abi.encodePacked(propositionId)) ==
			keccak256(abi.encodePacked(_mostExpensivePropositionId[marketId]));
	}*/

	// Overidden to make this "collateralised" - it will hold on to the collateral amounts for future bets
	// If the payout for this proposition will be greater than the amount of collateral set aside for the market
	// Return the new exposure amount
	// wager and payout are not required in this implement because the calculation is based on:
	// 1. The amount of collateral already set aside for the market
	// 2. The size of the most expensive proposition in the market
	// 3. The potential payout of this proposition (which already includes the current wager)
	function _obtainCollateral(
		uint256 index,
		bytes16 marketId,
		bytes16 propositionId,
		uint256 /* wager */, 
		uint256 /* payout */
	) internal override returns (uint256) {		
		// The collateral reserved for this race
		uint256 existingMarketCollateral = _marketCollateral[marketId] + _marketTotal[marketId];

		// If we have enough collateral in this market already, we're done	
		if (_potentialPayout[propositionId] <= existingMarketCollateral) {
			return 0;
		}
		
		// Otherwise, this must be the new "most expensive" proposition and we need to obtain more collateral to cover the gap.
		_mostExpensivePropositionId[marketId] = propositionId;
		
		// The amount needed is the difference between the potential payout and the existing collateral on this race
		uint256 amountToObtain = _potentialPayout[propositionId] - existingMarketCollateral;
		
		// If the total amount of collateral in the contracts is greater than the amount backing bets, we can use some
		uint256 internalCollateralToUse;
		if (_totalCollateral > _totalExposure) {
			// We have some collateral available to use (from previous bets)
			// This is the total collateral not already covering bets
			uint256 internallyAvailableCollateral = _totalCollateral - _totalExposure;

			// We can only use the amount of collateral that is available
			internalCollateralToUse = Math.min(amountToObtain, internallyAvailableCollateral);
		}

		// If the amount we need to borrow is greater than the amount of collateral we can use, we need to get more collateral from the Vault
		if (internalCollateralToUse < amountToObtain) {
			// We need to get more collateral from the Vault
			uint256 amountToBorrow = amountToObtain - internalCollateralToUse;
			IERC20(_vault.asset()).transferFrom(
				address(_vault),
				_self,
				amountToBorrow
			);

			// Add the amount we borrowed to the total collateral				
			emit Borrowed(index, amountToBorrow);
			_totalCollateral += amountToBorrow;
		}

		// Store the amount of exposure that this bet added. This will be deducted from the total exposure when the bet is paid out
		_betExposure[index] = amountToObtain;

		// Add to the market collateral						
		_marketCollateral[marketId] += amountToObtain;
		
		// The exposure added by this bet
		return amountToObtain;
	}

	function getTotalCollateral() external view returns (uint256) {
		return _totalCollateral;
	}

	// Return any unused collateral to the Vault
	function refundCollateral() external onlyOwner {
		require(_totalCollateral > _totalExposure, "refundCollateral: No collateral to refund");

		_totalCollateral = _totalExposure;
		IERC20(_vault.asset()).transfer(
			address(_vault),
			_totalCollateral - _totalExposure
		);	
	}
}

