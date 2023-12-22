// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;
import { IAddressProvider } from "./IAddressProvider.sol";
import { IERC20Upgradeable as IERC20 } from "./IERC20Upgradeable.sol";
import { ICore } from "./ICore.sol";
import { IHedgeToken } from "./IHedgeToken.sol";
import { ISponsorToken } from "./ISponsorToken.sol";
import "./AggregatorV3Interface.sol";
import "./AddressUpgradeable.sol";

/**
 * @title HedgeCoreStorage
 * @author Entropyfi
 * @notice Contract used as storage of the `HedgeCoreUpgradable` contract.
 * @dev It defines the storage layout of the `HedgeCoreUpgradable` contract. For upgradable contract, place the storage at the last the inheritance contracts.
 */
contract CoreStorageV1 {
	// ------------------------------ modifiers ----------------------------------
	/// @dev dao
	modifier onlyDAO() {
		require(msg.sender == addressProvider.getDAO(), "HC:NO ACCESS");
		_;
	}

	/// @dev emergencyAdmin or dao
	modifier onlyEmergencyAdmin() {
		require((msg.sender == addressProvider.getEmergencyAdmin()) || (msg.sender == addressProvider.getDAO()), "HC:NO ACCESS");
		_;
	}

	/// @dev only EOA/whitelisted contract/admin can interact with this protocol
	modifier isEligibleSender() {
		bool isAdmin = (msg.sender == addressProvider.getDAO() || msg.sender == addressProvider.getEmergencyAdmin());
		// check if address whitelisted if it's not EOA or Admins
		if (AddressUpgradeable.isContract(msg.sender) && !isAdmin) {
			require(whitelistedContracts[msg.sender], "HC:CONTRACT NOT WHITELISTED");
		}
		_;
	}

	modifier onlyInitialized() {
		require(initialized, "HC:NOT INIT");
		_;
	}

	modifier onlyWithdrawAllNotPaused() {
		require(!withdrawAllPaused, "HC:WA PAUSED");
		_;
	}

	modifier onlyAfterRebase(uint256 index_) {
		require(index_ > currSTokenIndex, "HC: NOT REBASED!");
		_;
	}

	modifier minAmount(uint256 hedgeAmount_, uint256 levAmount_) {
		if (hedgeAmount_ != 0) {
			require(hedgeAmount_ >= minSingleSideDepositAmount, "HC:H<= MIN");
		}
		if (levAmount_ != 0) {
			require(levAmount_ >= minSingleSideDepositAmount, "HC:L<= MIN");
		}

		_;
	}

	// precision for updating token index
	uint256 public constant PRECISION = 1E18;
	// precision for ratio calculation => priceRatio and toGaugeRatio
	uint256 public constant RATIO_PRECISION = 1E5;
	// precision for price
	uint256 public constant PRICE_PRECISION = 1E8;

	// contract name
	string public name;

	// for init gnensis hedge
	bool public initialized;

	// Address provider
	IAddressProvider public addressProvider;

	// tokens
	IERC20 public wToken; // the underlying token which user can deposit and withdraw
	IHedgeToken public hgeToken; // < for soft hedge
	IHedgeToken public levToken; // >= for soft leverage
	ISponsorToken public sponsorToken; // for sponsorship

	// game related
	bool public withdrawAllPaused; // for pause withdrawall
	uint256 public lastPriceUpdateTimestamp; // updated with price fetch
	uint256 public priceRatio; // 1e5 pricision (0-1e5) lev winning pric will be price*(1 + ratio(%))
	bool public isPriceRatioUp; // true: tune up, false tune down
	uint256 public resctrictedPeriod; // period of time when user can/cannot deposit withdraw and swap
	uint256 public currSTokenIndex; // current sToken epoch number
	uint256 public hedgeRebaseCnt; // increment when hedge win
	uint256 public levRebaseCnt; // increment when lev win
	ICore.HedgeInfo public hedgeInfo; // store important game related data

	// log related
	ICore.Log[] public logs;

	// gauge related
	address public gauge; // onlyOwner can change
	uint256 public toGaugeRatio; // 1000 means 1%.   div by 10^5 to get the actual number (e.g. 0.01)

	// for whitelist contract
	mapping(address => bool) public whitelistedContracts;

	// user view earned profits
	mapping(address => uint256) public userDeposited;

	uint256 public minSingleSideDepositAmount;
}

