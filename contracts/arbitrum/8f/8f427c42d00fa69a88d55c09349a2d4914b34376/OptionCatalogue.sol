// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import "./ERC20.sol";
import "./Types.sol";
import "./CustomErrors.sol";
import "./AccessControl.sol";
import "./OptionsCompute.sol";

import "./PRBMathSD59x18.sol";

/**
 *  @title OptionCatalogue
 *  @dev Store information on options approved for sale and to buy as well as netDhvExposure of the option
 */
contract OptionCatalogue is AccessControl {
	using PRBMathSD59x18 for int256;
	///////////////////////////
	/// immutable variables ///
	///////////////////////////

	// asset that is used for collateral asset
	address public immutable collateralAsset;

	/////////////////////////////////////
	/// governance settable variables ///
	/////////////////////////////////////

	// storage of option information and approvals
	mapping(bytes32 => OptionStores) public optionStores;
	// array of expirations currently supported (mainly for frontend use)
	uint64[] public expirations;
	// details of supported options first key is expiration then isPut then an array of strikes (mainly for frontend use)
	mapping(uint256 => mapping(bool => uint128[])) public optionDetails;

	//////////////////////////
	/// constant variables ///
	//////////////////////////

	// oToken decimals
	uint8 private constant OPYN_DECIMALS = 8;
	// scale otoken conversion decimals
	uint8 private constant CONVERSION_DECIMALS = 18 - OPYN_DECIMALS;

	/////////////////////////
	/// structs && events ///
	/////////////////////////

	struct OptionStores {
		bool approvedOption;
		bool isBuyable;
		bool isSellable;
	}

	event SeriesApproved(
		bytes32 indexed optionHash,
		uint64 expiration,
		uint128 strike,
		bool isPut,
		bool isBuyable,
		bool isSellable
	);
	event SeriesAltered(
		bytes32 indexed optionHash,
		uint64 expiration,
		uint128 strike,
		bool isPut,
		bool isBuyable,
		bool isSellable
	);

	constructor(address _authority, address _collateralAsset) AccessControl(IAuthority(_authority)) {
		collateralAsset = _collateralAsset;
	}

	//////////////////////////////////////////////////////
	/// access-controlled state changing functionality ///
	//////////////////////////////////////////////////////

	/**
	 * @notice issue an option series for buying or sale
	 * @param  options option type to approve - strike in e18
	 * @dev    only callable by the manager
	 */
	function issueNewSeries(Types.Option[] memory options) external {
		_onlyManager();
		uint256 addressLength = options.length;
		for (uint256 i = 0; i < addressLength; i++) {
			Types.Option memory o = options[i];
			// make sure the strike gets formatted properly
			uint128 strike = uint128(
				OptionsCompute.formatStrikePrice(o.strike, collateralAsset) * 10 ** (CONVERSION_DECIMALS)
			);
			if ((o.expiration - 28800) % 86400 != 0) {
				revert CustomErrors.InvalidExpiry();
			}
			// get the hash of the option (how the option is stored on the books)
			bytes32 optionHash = keccak256(abi.encodePacked(o.expiration, strike, o.isPut));
			// if the option is already issued then skip it
			if (optionStores[optionHash].approvedOption) {
				continue;
			}
			// store information on the series
			optionStores[optionHash] = OptionStores(
				true, // approval
				o.isBuyable,
				o.isSellable
			);
			// store it in an array, these are mainly for frontend/informational use
			// if the strike array is empty for calls and puts for that expiry it means that this expiry hasnt been issued yet
			// so we should save the expory
			if (
				optionDetails[o.expiration][true].length == 0 && optionDetails[o.expiration][false].length == 0
			) {
				expirations.push(o.expiration);
			}
			// we wouldnt get here if the strike already existed, so we store it in the array
			// there shouldnt be any duplicates in the strike array or expiration array
			optionDetails[o.expiration][o.isPut].push(strike);
			// emit an event of the series creation, now users can write options on this series
			emit SeriesApproved(optionHash, o.expiration, strike, o.isPut, o.isBuyable, o.isSellable);
		}
	}

	/**
	 * @notice change whether an issued option is for buy or sale
	 * @param  options option type to change status on - strike in e18
	 * @dev    only callable by the manager
	 */
	function changeOptionBuyOrSell(Types.Option[] memory options) external {
		_onlyManager();
		uint256 adLength = options.length;
		for (uint256 i = 0; i < adLength; i++) {
			Types.Option memory o = options[i];
			// make sure the strike gets formatted properly, we get it to e8 format in the converter
			// then convert it back to e18
			uint128 strike = uint128(
				OptionsCompute.formatStrikePrice(o.strike, collateralAsset) * 10 ** (CONVERSION_DECIMALS)
			);
			// get the option hash
			bytes32 optionHash = keccak256(abi.encodePacked(o.expiration, strike, o.isPut));
			// if its already approved then we can change its parameters, if its not approved then revert as there is a mistake
			if (optionStores[optionHash].approvedOption) {
				optionStores[optionHash].isBuyable = o.isBuyable;
				optionStores[optionHash].isSellable = o.isSellable;
				emit SeriesAltered(optionHash, o.expiration, strike, o.isPut, o.isBuyable, o.isSellable);
			} else {
				revert CustomErrors.UnapprovedSeries();
			}
		}
	}

	///////////////////////////
	/// non-complex getters ///
	///////////////////////////

	/**
	 * @notice get list of all expirations ever activated
	 * @return list of expirations
	 */
	function getExpirations() external view returns (uint64[] memory) {
		return expirations;
	}

	/**
	 * @notice get list of all strikes for a specific expiration and flavour
	 * @return list of strikes for a specific expiry and flavour
	 */
	function getOptionDetails(uint64 expiration, bool isPut) external view returns (uint128[] memory) {
		return optionDetails[expiration][isPut];
	}

	function getOptionStores(bytes32 oHash) external view returns (OptionStores memory) {
		return optionStores[oHash];
	}

	function isBuyable(bytes32 oHash) external view returns (bool) {
		return optionStores[oHash].isBuyable;
	}

	function isSellable(bytes32 oHash) external view returns (bool) {
		return optionStores[oHash].isSellable;
	}

	function approvedOptions(bytes32 oHash) external view returns (bool) {
		return optionStores[oHash].approvedOption;
	}
}

