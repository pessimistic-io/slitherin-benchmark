// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;
import { IAddressProvider } from "./IAddressProvider.sol";

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./ERC20Upgradeable.sol";

/**
 * @title HedgeTokenUpgradable (1:1 to the underlying asset)
 * @author Entropyfi
 * @notice Implementation of the interest bearing token( HedgeToken/Leverage Token ) for `Soft hedge & leverage` protocol
 */
contract HedgeToken is Initializable, ERC20Upgradeable, UUPSUpgradeable {
	event LogBalance(address indexed account_, uint256 indexed rawBalance_);
	uint8 private _decimals;
	uint256 constant PRECISION = 1E18;
	uint256 public index;
	address public core;
	IAddressProvider public addressProvider;

	modifier onlyCore() {
		require(msg.sender == core, "HT:CORE ONLY");
		_;
	}

	modifier onlyOwner() {
		if (address(addressProvider) != address(0)) {
			require((msg.sender == addressProvider.getEmergencyAdmin()) || (msg.sender == addressProvider.getDAO()), "HC:NO ACCESS");
		}
		_;
	}

	/**
	 * @notice Initializes the Hedge token
	 * we do not make it can only be called once bc we might need to update those params
	 * @param addressProvider_ The address of `addressProvider` which provide the address of `DAO`, which can authorize new implementation
	 * @param core_ The address of `Soft hedge & leverage` protocol, which can mint or burn new hedge tokens
	 * @param name_ The name of the Hedge token
	 * @param symbol_ The symbol of the Hedge token
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
		require(core_ != address(0), "HT:CORE ADDR ZERO");
		require(IAddressProvider(addressProvider_).getDAO() != address(0), "HT:AP INV");

		// 2. inheritance contract init
		__ERC20_init(name_, symbol_);
		__UUPSUpgradeable_init();

		// 3. init variables
		index = PRECISION;

		_decimals = decimals_;
		core = core_;
		addressProvider = IAddressProvider(addressProvider_);
	}

	//---------------------------------- onlyCore ------------------------------//
	/**
	 * @notice Mints `amount` hedge token to user
	 * @dev [onlyCore] action. The amount will be transformed to `rawAmount`(= amount/index)
	 * @param account_ The address of the user that will receive the minted hedge tokens
	 * @param amount_ The amount of tokens getting minted (1:1 to the underlying asset)
	 */
	function mint(address account_, uint256 amount_) external onlyCore {
		require(account_ != address(0), "HT:MT ZR AD");

		// 1. calc rawAmount
		uint256 rawAmount = computeRawAmount(amount_, index);

		// 2. _mint rawAmount to `account_`
		_mint(account_, rawAmount);

		// 3. emit event`Transfer` and balance event for graph
		emit Transfer(address(0), account_, amount_);
		emit LogBalance(account_, rawBalanceOf(account_));
	}

	/**
	 * @notice Burn `amount` hedge token from users
	 * @dev [onlyCore] action. The amount will be transformed to `rawAmount`(= amount/index)
	 * @param account_ The address of which the hedge tokens will be burned
	 * @param amount_ The amount of tokens being minted (1:1 to the underlying asset)
	 */
	function burn(address account_, uint256 amount_) external onlyCore {
		require(account_ != address(0), "HT:BRN ZR AD");

		// 1. calc rawAmount
		uint256 rawAmount = computeRawAmount(amount_, index);

		// 2. _burn rawAmount from `account_`
		_burn(account_, rawAmount);

		// 3. emit event`Transfer`
		emit Transfer(account_, address(0), amount_);
		emit LogBalance(account_, rawBalanceOf(account_));
	}

	/**
	 * @notice Update `index`
	 * @dev [onlyCore] action. The new index must be greater than the old index.
	 * @param index_ The new index to update.
	 */
	function updateIndex(uint256 index_) external onlyCore {
		require(index_ >= index, "HT:IDX INV");
		index = index_;
	}

	//--------------------------- transfer & transferFrom -------------------------//
	/**
	 * @notice Transfer `amount` hedge token from `msg.sender` to `recipient_`
	 * @dev The amount will be transformed to `rawAmount`(= amount/index)
	 */
	function transfer(address recipient_, uint256 amount_) public override returns (bool res_) {
		// 1. calc rawAmount
		uint256 rawAmount = computeRawAmount(amount_, index);
		// 2. ERC20.transfer with rawAmount and return
		res_ = super.transfer(recipient_, rawAmount);

		emit LogBalance(msg.sender, rawBalanceOf(msg.sender));
		emit LogBalance(recipient_, rawBalanceOf(recipient_));
	}

	/**
	 * @notice Transfer `amount` hedge token from `sender_` to `recipient_`
	 * @dev The msg.sender must have sufficient allowance for `sender_`'s token. The amount will be transformed to `rawAmount`(= amount/index)
	 */
	function transferFrom(
		address sender_,
		address recipient_,
		uint256 amount_
	) public override returns (bool) {
		uint256 rawAmount = computeRawAmount(amount_, index);

		uint256 currentAllowance = allowance(sender_, _msgSender());
		if (currentAllowance != type(uint256).max) {
			require(currentAllowance >= amount_, "HT:TF EXD ALLWNCE");
			unchecked {
				_approve(sender_, _msgSender(), currentAllowance - amount_);
			}
		}
		_transfer(sender_, recipient_, rawAmount);

		emit LogBalance(sender_, rawBalanceOf(sender_));
		emit LogBalance(msg.sender, rawBalanceOf(msg.sender));
		emit LogBalance(recipient_, rawBalanceOf(recipient_));

		return true;
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

	function balanceOf(address account_) public view override returns (uint256) {
		uint256 rawAmount = super.balanceOf(account_);
		return computeFromRawAmount(rawAmount, index);
	}

	function totalSupply() public view override returns (uint256) {
		uint256 rawAmount = super.totalSupply();
		return computeFromRawAmount(rawAmount, index);
	}

	function rawTotalSupply() public view returns (uint256) {
		return super.totalSupply();
	}

	function rawBalanceOf(address account_) public view returns (uint256) {
		return super.balanceOf(account_);
	}

	function computeRawAmount(uint256 amount_, uint256 index_) public pure returns (uint256) {
		return (amount_ * PRECISION) / index_;
	}

	function computeFromRawAmount(uint256 amount_, uint256 index_) public pure returns (uint256) {
		return (amount_ * index_) / PRECISION;
	}
}

