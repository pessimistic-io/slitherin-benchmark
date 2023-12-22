// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;
pragma abicoder v2;

import "./Ownable.sol";
import "./IERC20.sol";
import "./ERC721.sol";
import "./Strings.sol";

import "./IVault.sol";
import "./IMarket.sol";
import "./IOracle.sol";
import "./SignatureLib.sol";
import "./OddsLib.sol";

// Put these in the ERC721 contract
struct Bet {
	bytes16 propositionId;
	bytes16 marketId;
	uint256 amount;
	uint256 payout;
	uint256 payoutDate;
	uint256 created;
	bool settled;
}

uint256 constant MARGIN = 1500000;

contract Market is IMarket, Ownable, ERC721 {
	using Strings for uint256;

	string internal _metadataBaseURI;

	uint8 internal immutable _margin;
	IVault internal immutable _vault;
	IERC20 internal immutable _underlying;
	address internal immutable _self;
	IOracle internal immutable _oracle;

	uint256 internal _inplayCount; // running count of bets
	Bet[] internal _bets;

	// MarketID => Bets Indexes
	mapping(bytes16 => uint64[]) internal _marketBets;

	// MarketID => amount bet
	mapping(bytes16 => uint256) internal _marketTotal;

	// MarketID => PropositionID => amount bet
	mapping(bytes16 => mapping(uint16 => uint256)) internal _marketBetAmount;

	// PropositionID => winnings that could be paid out for this proposition
	mapping(bytes16 => uint256) internal _potentialPayout;

	uint256 internal _totalInPlay;
	uint256 internal _totalExposure;

	// Can claim after this period regardless
	uint256 public immutable timeout;

	mapping(address => bool) private _signers;

	// Race result constants
	uint8 public constant NULL = 0x00;
	uint8 public constant WINNER = 0x01;
	uint8 public constant LOSER = 0x02;
	uint8 public constant SCRATCHED = 0x03;

	constructor(
		IVault vault,
		uint8 margin,
		uint8 timeoutDays,
		address oracle,
		string memory metadataBaseURI
	) ERC721("Horse Link Bet Slip", "HL-BET") {
		assert(address(vault) != address(0));
		_self = address(this);
		_vault = vault;
		_underlying = IERC20(vault.asset());
		_margin = margin;
		_oracle = IOracle(oracle);
		_signers[owner()] = true;
		_metadataBaseURI = metadataBaseURI;

		timeout = timeoutDays * 1 days;
	}

	// Override of ERC721Metadata. Use base URI specified in contructor
	function _baseURI() internal view override returns (string memory) {
		return _metadataBaseURI;
	}

	function getOwner() external view returns (address) {
		return owner();
	}

	function getMargin() external view returns (uint8) {
		return _margin;
	}

	function getTotalInPlay() external view returns (uint256) {
		return _totalInPlay;
	}

	function getInPlayCount() external view returns (uint256) {
		return _inplayCount;
	}

	function getCount() external view returns (uint64) {
		return _getCount();
	}

	function _getCount() private view returns (uint64) {
		return uint64(_bets.length);
	}

	function getTotalExposure() external view returns (uint256) {
		return _totalExposure;
	}

	function getOracleAddress() external view returns (address) {
		return address(_oracle);
	}

	function getVaultAddress() external view returns (address) {
		return address(_vault);
	}

	function getExpiry(uint64 index) external view returns (uint256) {
		return _getExpiry(index);
	}

	function getMarketTotal(bytes16 marketId) external view returns (uint256) {
		return _marketTotal[marketId];
	}

	function _getExpiry(uint64 index) internal view returns (uint256) {
		return _bets[index].payoutDate + timeout;
	}

	function getBetByIndex(
		uint64 index
	)
		external
		view
		returns (
			uint256,
			uint256,
			uint256, // payoutDate
			uint256, // created
			bool,
			bytes16, // marketId
			bytes16 // propositionId
		)
	{
		return _getBet(index);
	}

	function _getBet(
		uint64 index
	)
		internal
		view
		returns (uint256, uint256, uint256, uint256, bool, bytes16, bytes16)
	{
		Bet memory bet = _bets[index];
		return (
			bet.amount,
			bet.payout,
			bet.payoutDate,
			bet.created,
			bet.settled,
			bet.marketId,
			bet.propositionId
		);
	}

	function getOdds(
		uint256 wager,
		uint256 odds,
		bytes16 propositionId,
		bytes16 marketId
	) external view override returns (uint256) {
		return _getOdds(wager, odds, propositionId, marketId);
	}

	// Given decimal ("European") odds expressed as the amount one wins for ever unit wagered.
	// This number represents the to total payout rather than the profit, i.e it includes the return of ther stake.
	// Hence, these odds will never go below 1, which represents even money.
	// marketId is not used in this implementation because the odds for every proposition are calculated based on the total pool
	function _getOdds(
		uint256 wager,
		uint256 odds,
		bytes16 propositionId,
		bytes16 /*marketId*/
	) internal view returns (uint256) {
		if (wager <= 1 || odds <= 1) return 1;

		uint256 pool = _vault.getMarketAllowance();

		// If the pool is not sufficient to cover a new bet
		if (pool == 0) return 1;
		// exclude the current total potential payout from the pool
		if (_potentialPayout[propositionId] > pool) {
			return 1;
		}

		pool -= _potentialPayout[propositionId];

		// Calculate the new odds
		uint256 adjustedOdds = _getAdjustedOdds(wager, odds, pool);
		return adjustedOdds;
	}

	function _getAdjustedOdds(
		uint256 wager,
		uint256 odds,
		uint256 pool
	) internal view virtual returns (uint256) {
		return OddsLib.getLinearAdjustedOdds(wager, odds, pool);
	}

	function getPotentialPayout(
		bytes16 propositionId,
		bytes16 marketId,
		uint256 wager,
		uint256 odds
	) external view returns (uint256) {
		return _getPayout(propositionId, marketId, wager, odds);
	}

	function _getPayout(
		bytes16 propositionId,
		bytes16 marketId,
		uint256 wager,
		uint256 odds
	) internal view returns (uint256) {
		uint256 trueOdds = _getOdds(wager, odds, propositionId, marketId);
		return Math.max(wager, (trueOdds * wager) / OddsLib.PRECISION);
	}

	function multiBack(
		Back[] calldata backArray
	) external returns (uint256[] memory) {
		uint256[] memory indexes = new uint256[](backArray.length);

		for (uint8 i; i < backArray.length; i++) {
			Back calldata data = backArray[i];
			indexes[i] = back(data);
		}

		return indexes;
	}

	function back(Back calldata backData) public returns (uint256) {
		bytes32 messageHash = keccak256(
			abi.encodePacked(
				backData.nonce,
				backData.propositionId,
				backData.marketId,
				backData.odds,
				backData.close,
				backData.end
			)
		);

		require(
			isValidSignature(messageHash, backData.signature) == true,
			"back: Invalid signature"
		);

		// Note: Now that we are checking the close time, this is not strictly necessary
		require(
			backData.end > block.timestamp && backData.close > block.timestamp,
			"back: Invalid date"
		);

		// Do not allow a bet placed if we know the result
		require(
			IOracle(_oracle).hasResult(backData.marketId) == false,
			"back: Oracle result already set for this market"
		);

		// add underlying to the market
		uint256 payout = _getPayout(
			backData.propositionId,
			backData.marketId,
			backData.wager,
			backData.odds
		);
		assert(payout > 0);

		return
			_back(
				backData.propositionId,
				backData.marketId,
				backData.wager,
				backData.end,
				payout
			);
	}

	function _back(
		bytes16 propositionId,
		bytes16 marketId,
		uint256 wager,
		uint256 end,
		uint256 payout
	) internal returns (uint256) {
		// Escrow the wager
		_underlying.transferFrom(_msgSender(), _self, wager);

		// Add to in play total for this marketId
		_marketTotal[marketId] += wager;
		_totalInPlay += wager;
		_inplayCount++;

		uint64 index = _getCount();

		// If the payout for this proposition will be greater than the current max payout for the market)
		_potentialPayout[propositionId] += payout;
		_totalExposure += _obtainCollateral(
			uint256(index),
			marketId,
			propositionId,
			wager,
			payout
		);

		_bets.push(
			Bet(
				propositionId,
				marketId,
				wager,
				payout,
				end,
				block.timestamp,
				false
			)
		);
		_marketBets[marketId].push(index);
		_mint(_msgSender(), uint256(index));

		emit Placed(
			uint256(index),
			propositionId,
			marketId,
			wager,
			payout,
			_msgSender()
		);

		return index;
	}

	function settle(uint64 index) external {
		Bet memory bet = _bets[index];
		require(bet.settled == false, "settle: Bet has already settled");
		_settle(index);
	}
	
	function _settle(uint64 index) internal {
		Bet memory bet = _bets[index];
		_bets[index].settled = true;

		uint8 result;
		address recipient;

		if (block.timestamp > _getExpiry(index)) {
			result = WINNER;
			recipient = ownerOf(index);
			_payout(index, WINNER);
		} else {
			result = IOracle(_oracle).checkResult(
				bet.marketId,
				bet.propositionId
			);

			require(result != NULL, "_settle: Oracle does not have a result");

			recipient = result != LOSER ? ownerOf(index) : address(_vault);

			_payout(index, result);
			_totalInPlay -= _bets[index].amount;
			_inplayCount--;
		}

		emit Settled(index, _bets[index].payout, result, recipient);

		_burn(uint256(index));
	}

	function scratchAndRefund(
		uint64 index,
		bytes16 marketId,
		bytes16 propositionId,
		uint256 odds,
		SignatureLib.Signature calldata signature
	) external {
		require(
			_bets[index].propositionId == propositionId,
			"scratchAndRefund: propositionId does not match bet"
		);
		require(
			_bets[index].settled == false,
			"scratchAndRefund: Bet has already settled"
		);

		_oracle.setScratchedResult(marketId, propositionId, odds, signature);

		_bets[index].settled = true;
		_refund(index);
	}

	/*
	 * @dev Reverse a bet on a scratched runner. If the bet was on a scratched runner, return the stake to the bettor and the loan to the vault
	 * @param index The index of the bet
	 */
	function refund(uint64 index) external {
		require(
			_bets[index].settled == false,
			"refund: Bet has already settled"
		);

		bytes16 marketId = _bets[index].marketId;

		IOracle.Result memory result = IOracle(_oracle).getResult(marketId);
		// Iterate through scratchings to see if the bet was on a scratched runner
		uint256 count = result.scratched.length;
		for (uint256 i = 0; i < count; i++) {
			if (
				result.scratched[i].propositionId == _bets[index].propositionId
			) {
				_bets[index].settled = true;
				_refund(index);
				return;
			}
		}
		// Not scratched, so revert
		revert("refund: Not eligible for refund");
	}

	function _refund(uint64 index) internal virtual {
		Bet memory bet = _bets[index];

		uint256 loan = _bets[index].payout - _bets[index].amount;
		_totalExposure -= loan;
		_totalInPlay -= _bets[index].amount;
		_inplayCount--;

		address recipient = ownerOf(index);

		_underlying.transfer(recipient, bet.amount);
		_underlying.transfer(address(_vault), loan);

		emit Repaid(address(_vault), loan);
		emit Refunded(index, bet.amount, recipient);

		_burn(uint256(index));
	}

	function _applyScratchings(
		uint64 index
	) internal virtual returns (uint256) {
		// Get marketId of bet
		bytes16 marketId = _bets[index].marketId;
		// Ask the oracle for scratched runners on this market
		IOracle.Result memory result = IOracle(_oracle).getResult(marketId);

		// Get all scratchings with a timestamp after this bet
		// Loop through scratchings
		uint256 scratchedOdds;
		uint256 betCreated = _bets[index].created;
		uint256 count = result.scratched.length;

		for (uint256 i = 0; i < count; i++) {
			// If the timestamp of the scratching is after the bet
			if (result.scratched[i].timestamp > betCreated) {
				// Sum the odds
				scratchedOdds += result.scratched[i].odds;
			}
		}
		// Now apply the scratched odds to get the new odds for the bet
		if (scratchedOdds > 0 && _bets[index].amount > 0) {
			// Calculate the odds of the bet
			uint256 originalOdds = _bets[index].payout / _bets[index].amount;
			uint256 newOdds = OddsLib.rebaseOddsWithScratch(
				originalOdds,
				scratchedOdds,
				MARGIN
			);
			// Calculate the new payout
			_bets[index].payout = _bets[index].amount * newOdds;
		}

		return _bets[index].payout;
	}

	function _payout(uint256 index, uint8 result) internal virtual {
		uint256 payout = _bets[index].payout;
		uint256 amount = _bets[index].amount;
		uint256 loan = payout - amount;

		// Deduct from total exposure first
		_totalExposure -= loan;

		if (result == SCRATCHED) {
			// Transfer the bet amount to the owner of the NFT
			_underlying.transfer(ownerOf(index), amount);

			// Transfer the loaned amount back to the vault
			_underlying.transfer(address(_vault), loan);
			emit Repaid(address(_vault), loan);

			return;
		}

		// Only allow payouts after the payout date, or if the bet has been scratched
		require(
			_bets[index].payoutDate < block.timestamp,
			"_payout: Payout date not reached"
		);

		if (result == WINNER) {
			// Transfer the payout to the owner of the NFT
			_underlying.transfer(ownerOf(index), payout);
		}

		if (result == LOSER) {
			uint256 rate = _vault.getRate();
			assert(rate > 100_000);

			// Transfer the bet amount plus interest to the vault

			uint256 repayment = (loan * rate) / 100_000;

			if (payout > repayment) {
				// Transfer the rest to the market owner
				_underlying.transfer(owner(), payout - repayment);
			}
			_underlying.transfer(address(_vault), repayment);
			emit Repaid(address(_vault), repayment);
		}
	}

	// Allow the Vault to provide cover for this market
	// Standard implementation is to request cover for each and every bet
	// marketId and propositionId are not required here but ARE used in CollateralisedMarket, which inherits this contract
	function _obtainCollateral(
		uint256 index,
		bytes16 /*marketId*/,
		bytes16 /*propositionId*/,
		uint256 wager,
		uint256 payout
	) internal virtual returns (uint256) {
		uint256 amount = payout - wager;

		_underlying.transferFrom(address(_vault), _self, amount);

		emit Borrowed(address(_vault), index, amount);

		return amount;
	}

	function settleMarket(bytes16 marketId) external {
		uint64[] memory bets = _marketBets[marketId];
		uint256 count = bets.length;

		for (uint64 i = 0; i < count; i++) {
			uint64 index = bets[i];

			Bet memory bet = _bets[index];
			if (bet.settled == false) {
				_settle(index);
			}
		}
	}

	function grantSigner(address signer) external onlyOwner {
		require(signer != address(0), "grantSigner: Invalid signer address");
		_signers[signer] = true;
	}

	function revokeSigner(address signer) external onlyOwner {
		require(signer != address(0), "revokeSigner: Invalid signer address");
		_signers[signer] = false;
	}

	function isSigner(address signer) external view returns (bool) {
		return _isSigner(signer);
	}

	function _isSigner(address signer) internal view returns (bool) {
		return _signers[signer];
	}

	function isValidSignature(
		bytes32 messageHash,
		SignatureLib.Signature calldata signature
	) internal view returns (bool) {
		address signer = SignatureLib.recoverSigner(messageHash, signature);
		assert(signer != address(0));
		return _isSigner(signer);
	}

	event Borrowed(address indexed vault, uint256 index, uint256 amount);

	event Placed(
		uint256 index,
		bytes16 propositionId,
		bytes16 marketId,
		uint256 amount,
		uint256 payout,
		address indexed owner
	);

	event Refunded(uint256 index, uint256 amount, address indexed recipient);

	event Repaid(address indexed vault, uint256 amount);

	event Settled(
		uint256 index,
		uint256 payout,
		uint8 result,
		address indexed recipient
	);
}

