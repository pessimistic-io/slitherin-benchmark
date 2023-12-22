// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;
import { IAddressProvider } from "./IAddressProvider.sol";

import "./UUPSUpgradeable.sol";
import "./ERC20Upgradeable.sol";

/**
 * @title SponsorTokenUpgradable
 * @author Entropyfi
 * @notice sponsorToken for `Soft hedge & leverage` protocol
 */
contract SponsorToken is Initializable, ERC20Upgradeable, UUPSUpgradeable {
	event LogBalance(address indexed account_, uint256 balance_);
	uint8 private _decimals;
	address public core;
	IAddressProvider public addressProvider;

	modifier onlyCore() {
		require(msg.sender == core, "SP:CORE ONLY");
		_;
	}

	modifier onlyOwner() {
		if (address(addressProvider) != address(0)) {
			require((msg.sender == addressProvider.getEmergencyAdmin()) || (msg.sender == addressProvider.getDAO()), "SP:NO ACCESS");
		}
		_;
	}

	/**
	 * @notice Initializes the sponsorToken
	 * @param addressProvider_ The address of `addressProvider` which provide the address of `DAO`, which can authorize new implementation
	 * @param core_ The address of `Soft hedge & leverage` protocol, which can mint or burn new sponsor tokens
	 * @param name_ The name of the sponsorToken
	 * @param symbol_ The symbol of the sponsorToken
	 * @param decimals_ The decimals of token, same as the underlying asset's (e.g. sToken)
	 */
	function initialize(
		address addressProvider_,
		address core_,
		string memory name_,
		string memory symbol_,
		uint8 decimals_
	) public initializer {
		// 1. param checks
		require(core_ != address(0), "SP:CORE ADDR ZERO");
		require(IAddressProvider(addressProvider_).getDAO() != address(0), "SP:AP INV");

		// 2. inheritance contract init
		__ERC20_init(name_, symbol_);
		__UUPSUpgradeable_init();

		// 3. init variables
		_decimals = decimals_;
		core = core_;
		addressProvider = IAddressProvider(addressProvider_);
	}

	//---------------------------------- onlyCore ------------------------------//
	/**
	 * @notice Mints `amount` sponsorToken to user
	 * @dev [onlyCore] action.
	 * @param account_ The address of the user that will receive the minted hedge tokens
	 * @param amount_ The amount of tokens getting minted (1:1 to the underlying asset)
	 */
	function mint(address account_, uint256 amount_) external onlyCore {
		require(account_ != address(0), "SP:MT ZR AD");

		// 1. _mint amount to `account_`
		_mint(account_, amount_);

		// 2. emit event`Transfer`
		emit Transfer(address(0), account_, amount_);
		emit LogBalance(account_, balanceOf(account_));
	}

	/**
	 * @notice Burn `amount`  sponsorToken from users
	 * @dev [onlyCore] action.
	 * @param account_ The address of which the sponsorToken will be burned
	 * @param amount_ The amount of tokens being minted (1:1 to the underlying asset)
	 */
	function burn(address account_, uint256 amount_) external onlyCore {
		require(account_ != address(0), "SP:BRN ZR AD");

		// 1. _burn amount from `account_`
		_burn(account_, amount_);

		// 2. emit event`Transfer`
		emit Transfer(account_, address(0), amount_);
		emit LogBalance(account_, balanceOf(account_));
	}

	//---------------------------------- onlyOwner ----------------------------------//
	/**
	 * @dev onlyOwner can update implementation
	 */
	function _authorizeUpgrade(address) internal override onlyOwner {}

	//---------------------------------- view / pure ------------------------------//
	function decimals() public view override returns (uint8) {
		return _decimals;
	}

	function _afterTokenTransfer(
		address from,
		address to,
		uint256
	) internal override {
		emit LogBalance(from, balanceOf(from));
		emit LogBalance(msg.sender, balanceOf(msg.sender));
		emit LogBalance(to, balanceOf(to));
	}
}

