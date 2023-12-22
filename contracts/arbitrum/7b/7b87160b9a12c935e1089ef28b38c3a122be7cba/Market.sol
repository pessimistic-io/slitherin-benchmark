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
    uint8 internal constant WINNER = 0x01;
    uint8 internal constant LOSER = 0x02;
    uint8 internal constant SCRATCHED = 0x03;

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

	function getMarketTotal(bytes16 marketId)
		external
		view
		returns (uint256)
	{
		return _marketTotal[marketId];
	}

	function _getExpiry(uint64 index) internal view returns (uint256) {
		return _bets[index].payoutDate + timeout;
	}

	function getBetByIndex(uint64 index)
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

	function _getBet(uint64 index)
		internal
		view
		returns (
			uint256,
			uint256,
			uint256,
			uint256,
			bool,
			bytes16,
			bytes16
		)
	{
		Bet memory bet = _bets[index];
		return (bet.amount, bet.payout, bet.payoutDate, bet.created, bet.settled, bet.marketId, bet.propositionId);
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

	function back(
		Back calldata backData
	) public returns (uint256) {
		bytes32 messageHash = keccak256(
			abi.encodePacked(backData.nonce, backData.propositionId, backData.marketId, backData.odds, backData.close, backData.end)
		);

		require(
			isValidSignature(messageHash, backData.signature) == true,
			"back: Invalid signature"
		);

		// add underlying to the market
		uint256 payout = _getPayout(backData.propositionId, backData.marketId, backData.wager, backData.odds);
		assert(payout > 0);

		return _back(backData.propositionId, backData.marketId, backData.wager, backData.close, backData.end, payout);
	}

	function _back(
		bytes16 propositionId,
		bytes16 marketId,
		uint256 wager,
		uint256 close,
		uint256 end,
		uint256 payout
	) internal returns (uint256) {
		require(
			end > block.timestamp && close > block.timestamp,
			"_back: Invalid date"
		);

		// Do not allow a bet placed if we know the result
		// Note: Now that we are checking the close time, this is not strictly necessary
		require(
			IOracle(_oracle).checkResult(marketId, propositionId) == 0x02,
			"_back: Oracle result already set for this market"
		);

		address underlying = _vault.asset();

		// Escrow the wager
		IERC20(underlying).transferFrom(_msgSender(), _self, wager);

		// Add to in play total for this marketId
		_marketTotal[marketId] += wager;
		_totalInPlay += wager;
		_inplayCount++;

		uint64 index = _getCount();

		// If the payout for this proposition will be greater than the current max payout for the market)
		_potentialPayout[propositionId] += payout;
		_totalExposure += _obtainCollateral(uint256(index), marketId, propositionId, wager, payout);

		_bets.push(
			Bet(propositionId, marketId, wager, payout, end, block.timestamp, false)
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
		/*require(
			_bets[index].payoutDate < block.timestamp,
			"_settle: Payout date not reached"
		);*/
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
			recipient = result != LOSER ? ownerOf(index) : address(_vault);
			if (result == WINNER) {
				_applyScratchings(index);
			}
			_payout(index, result);
			_totalInPlay -= _bets[index].amount;
			_inplayCount--;
		}

		emit Settled(index, _bets[index].payout, result, recipient);

		_burn(index);
	}

	function _applyScratchings(uint64 index) internal virtual returns (uint256) {
		// Get marketId of bet
		bytes16 marketId = _bets[index].marketId;
		// Ask the oracle for scratched runners on this market
		IOracle.Result memory result = IOracle(_oracle).getResult(marketId);

		// Get all scratchings with a timestamp after this bet
		// Loop through scratchings
		uint256 scratchedOdds;
		uint256 betCreated = _bets[index].created;
		uint256 scratchedCount = result.scratched.length;
		for (uint256 i = 0; i < scratchedCount; i++) {
			// If the timestamp of the scratching is after the bet
			if (result.scratched[i].timestamp > betCreated) {
				// Sum the odds
				scratchedOdds += result.scratched[i].odds;
			}
		}
		// Now apply the scratched odds to get the new odds for the bet
		if (scratchedOdds > 0 && _bets[index].amount > 0) {
			// Calculate the odds of the bet
			uint256 originalOdds = _bets[index].payout / _bets[index].amount ;
			uint256 newOdds = OddsLib.rebaseOddsWithScratch(originalOdds, scratchedOdds, MARGIN);
			// Calculate the new payout
			_bets[index].payout = _bets[index].amount * newOdds;
		}

		return _bets[index].payout;
	}


	function _payout(uint256 index, uint8 result) internal virtual {
		if (result == SCRATCHED) {
			uint256 lay = _bets[index].payout - _bets[index].amount;
			// Transfer the bet amount to the owner of the NFT
			IERC20(_vault.asset()).transfer(ownerOf(index), _bets[index].amount);
			// Transfer the lay back to the vault
			IERC20(_vault.asset()).transfer(address(_vault), lay);
		} else {
			address recipient = result == WINNER ? ownerOf(index) : address(_vault);
			uint256 amount = _bets[index].payout;

			// event for vault rewarded
			if (recipient == address(_vault)) {
				emit Repaid(recipient, amount);
			}

			IERC20(_vault.asset()).transfer(recipient, amount);
		}
		_totalExposure -= _bets[index].payout - _bets[index].amount;
	}
	
	// Allow the Vault to provide cover for this market
	// Standard implementation is to request cover for each and every bet
	// marketId and propositionId are not required here but ARE used in CollateralisedMarket, which inherits this contract
	function _obtainCollateral(uint256 index, bytes16 /*marketId*/, bytes16 /*propositionId*/, uint256 wager, uint256 payout) internal virtual returns (uint256) {
		uint256 amount = payout - wager;

		IERC20(_vault.asset()).transferFrom(
			address(_vault),
			_self,
			amount
		);

		emit Borrowed(index, amount);

		return amount;
	}

	function settleMarket(bytes16 marketId) external {
		uint64[] memory bets = _marketBets[marketId];
		uint256 total = bets.length;

		for (uint64 i = 0; i < total; i++) {
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

	event Placed(
		uint256 index,
		bytes16 propositionId,
		bytes16 marketId,
		uint256 amount,
		uint256 payout,
		address indexed owner
	);

	event Settled(
		uint256 index,
		uint256 payout,
		uint8 result,
		address indexed recipient
	);

	event Borrowed(
		uint256 index,
		uint256 amount
	);

	event Repaid(
		address indexed vault,
		uint256 amount
	);
}

