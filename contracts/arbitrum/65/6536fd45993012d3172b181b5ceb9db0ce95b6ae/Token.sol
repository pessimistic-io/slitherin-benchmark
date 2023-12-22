// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./ContextUpgradeable.sol";
import "./ERC20Upgradeable.sol";
import "./SafeMathUpgradeable.sol";

import "./IRouter.sol";
import "./IToken.sol";
import "./ERC20TokenRecover.sol";

interface IFactory {
	function createPair(
		address tokenA,
		address tokenB
	) external returns (address pair);
}

abstract contract Token is
	Initializable,
	ContextUpgradeable,
	OwnableUpgradeable,
	IToken,
	ERC20Upgradeable,
	ERC20TokenRecover
{

	address private deployer;

	bool public tradingEnabled;

	address public constant DEAD = address(0xdead);

	mapping(address => uint256) private _balances;
	mapping(address => bool) public excludedFromFees;

	IRouter public router;
	address public pair;

	uint256 public maxTxAmount;
	uint256 public maxWalletAmount;

	uint8 _decimals;

	uint256[50] __gap;

	constructor() {
		deployer = _msgSender();
	}

	function __BaseToken_init(
		string memory name,
		string memory symbol,
		uint8 decim,
		uint256 supply
	) public virtual {
		// msg.sender = address(0) when using Clone.
		require(
			deployer == address(0) || _msgSender() == deployer,
			"UNAUTHORIZED"
		);
		require(decim > 3 && decim < 19, "DECIM");

		deployer = _msgSender();

		super.__ERC20_init(name, symbol);
		super.__Ownable_init_unchained();
		// super.__ERC20Capped_init_unchained(supply);
		// super.__ERC20Burnable_init_unchained(true);
		_decimals = decim;

		_mint(_msgSender(), supply);
		transferOwnership(tx.origin);
	}

	function decimals()
		public
		view
		virtual
		override(ERC20Upgradeable, IERC20MetadataUpgradeable)
		returns (uint8)
	{
		return _decimals;
	}

	//== BEP20 owner function ==
	function getOwner() public view override returns (address) {
		return owner();
	}

	//== Mandatory overrides ==/
	function _mint(
		address account,
		uint256 amount
	) internal virtual override(ERC20Upgradeable) {
		super._mint(account, amount);
	}

	function updateExcludedFromFees(
		address _address,
		bool state
	) external onlyOwner {
		excludedFromFees[_address] = state;
	}

	function updateMaxTxAmount(uint256 amount) external onlyOwner {
		require(amount > (totalSupply() / 10000), "maxTxAmount < 0.01%");
		maxTxAmount = amount;
	}

	function updateMaxWalletAmount(uint256 amount) external onlyOwner {
		require(amount > (totalSupply() / 10000), "maxWalletAmount < 0.01%");
		maxWalletAmount = amount;
	}

	function enableTrading() external onlyOwner {
		require(!tradingEnabled, "Trading already active");

		tradingEnabled = true;
	}

	// fallbacks
	receive() external payable {}
}

