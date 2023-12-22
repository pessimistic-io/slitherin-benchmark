// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;
pragma abicoder v2;

import "./access_Ownable.sol";
import "./ERC20_IERC20.sol";
import "./ERC721_ERC721.sol";

import "./IVault.sol";
import "./IMarket.sol";
import "./IOracle.sol";
import "./SignatureLib.sol";
import "./OddsLib.sol";
import "./Market.sol";

contract MarketWithRisk is Market {
    constructor(
        IVault vault,
        uint8 fee,
		uint8 timeoutDays,
        address oracle,
		string memory baseMetadataURI
	) Market(vault, fee, timeoutDays, oracle, baseMetadataURI) {
    }

	function getOddsWithRisk(
		uint256 wager,
		uint256 odds,
		bytes16 propositionId,
		bytes16 marketId,
		uint256 risk
	) external view returns (uint256) {
		return _getOddsWithRisk(wager, odds, propositionId, marketId, risk);
	}

	function _getOddsWithRisk(
		uint256 wager,
		uint256 odds,
		bytes16 propositionId,
		bytes16 marketId,
		uint256 risk
	) private view returns (uint256) {
		return _getOdds(wager, odds, propositionId, marketId) / risk ** 2;
	}

	function backWithRisk(
		bytes16 nonce,
		bytes16 propositionId,
		bytes16 marketId,
		uint256 wager,
		uint256 odds,
		uint256 close,
		uint256 end,
		uint256 risk,
		SignatureLib.Signature calldata signature
	) external returns (uint256) {
		bytes32 messageHash = keccak256(abi.encodePacked(
			nonce,
			propositionId,
			marketId,
			odds,
			close,
			end,
			risk
		));

		require(isValidSignature(messageHash, signature) == true, "back: Invalid signature");

		uint256 payout = wager * _getOddsWithRisk(wager, odds, propositionId, marketId, risk);
		return _back(
			propositionId,
			marketId,
			wager,
			close,
			end,
			payout
		);
	}
}

