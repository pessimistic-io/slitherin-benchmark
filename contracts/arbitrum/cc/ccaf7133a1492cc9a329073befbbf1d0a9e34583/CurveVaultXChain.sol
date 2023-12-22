//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { AddressUpgradeable } from "./AddressUpgradeable.sol";
import { ERC20Upgradeable } from "./ERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import { ILGV4XChain } from "./ILGV4XChain.sol";
import { ICommonRegistryXChain } from "./ICommonRegistryXChain.sol";
import { ICurveStrategyXChain } from "./ICurveStrategyXChain.sol";
import { ICurveVaultXChain } from "./ICurveVaultXChain.sol";

contract CurveVaultXChain is ERC20Upgradeable, ICurveVaultXChain {
	using SafeERC20Upgradeable for ERC20Upgradeable;
	using AddressUpgradeable for address;

	ERC20Upgradeable public token;
	address public sdGauge;
	address public newVault; // In case of migration
	bool public active; // In case of migration

	ICommonRegistryXChain public registry;
	bytes32 public constant GOVERNANCE = keccak256(abi.encode("GOVERNANCE"));
	bytes32 public constant STRATEGY = keccak256(abi.encode("CURVE_STRATEGY"));

	event Deposit(address _depositor, address _staker, uint256 _amount);
	event Withdraw(address _depositor, uint256 _amount);

	modifier onlyGovernance() {
		address governance = registry.getAddrIfNotZero(GOVERNANCE);
		require(msg.sender == governance, "!gov");
		_;
	}

	function init(
		address _token,
		string memory name_,
		string memory symbol_,
		address _registry,
		address _sdGauge
	) external override initializer {
		__ERC20_init(name_, symbol_);
		require(_token != address(0), "zero adress");
		token = ERC20Upgradeable(_token);
		require(_registry != address(0), "zero adress");
		registry = ICommonRegistryXChain(_registry);
		active = true;
		require(_sdGauge != address(0), "zero adress");
		sdGauge = _sdGauge;
	}

	/// @notice function to deposit a new amount
	/// @param _staker address to stake for
	/// @param _amount amount to deposit
	function deposit(address _staker, uint256 _amount) external override {
		require(active, "Vault is not active");
		require(address(sdGauge) != address(0), "Gauge not yet initialized");
		token.safeTransferFrom(msg.sender, address(this), _amount);
		_mint(address(this), _amount);
		_approve(address(this), sdGauge, _amount);
		ILGV4XChain(sdGauge).deposit(_amount, _staker);
		address curveStrategy = registry.getAddrIfNotZero(STRATEGY);
		token.approve(curveStrategy, 0);
		token.approve(curveStrategy, _amount);
		ICurveStrategyXChain(curveStrategy).deposit(address(token), _amount);
		emit Deposit(msg.sender, _staker, _amount);
	}

	/// @notice function to withdraw
	/// @param _amount amount to withdraw
	function withdraw(uint256 _amount) public override {
		uint256 userTotalShares = ILGV4XChain(sdGauge).balanceOf(msg.sender);
		require(_amount <= userTotalShares, "Not enough staked");
		ILGV4XChain(sdGauge).withdraw(_amount, msg.sender, true);
		_burn(address(this), _amount);
		if (active) {
			address curveStrategy = registry.getAddrIfNotZero(STRATEGY);
			ICurveStrategyXChain(curveStrategy).withdraw(address(token), _amount);
		}
		token.safeTransfer(msg.sender, _amount);
		emit Withdraw(msg.sender, _amount);
	}

	/// @notice function to withdraw all curve LPs deposited
	function withdrawAll() external {
		withdraw(ILGV4XChain(sdGauge).balanceOf(msg.sender));
	}

	/// @notice function to return the vault token decimals
	function decimals() public view override returns (uint8) {
		return token.decimals();
	}

	/// @notice function to help migrate to a new vault if there would be migration case
	function migrate() external {
		require(active == false, "Vault is active");
		uint256 userTotalShares = ILGV4XChain(sdGauge).balanceOf(msg.sender);
		ILGV4XChain(sdGauge).withdraw(userTotalShares, msg.sender, true);
		_burn(address(this), userTotalShares);
		token.approve(newVault, userTotalShares);
		ICurveVaultXChain(newVault).deposit(msg.sender, userTotalShares);
	}

	/// @notice function to set the new vault address and set the vault to non active
	/// @param _newVault new vault address
	function setMigration(address _newVault) external onlyGovernance {
		require(_newVault != address(0), "zero address");
		newVault = _newVault;
		active = false;
		address curveStrategy = registry.getAddrIfNotZero(STRATEGY);
		ICurveStrategyXChain(curveStrategy).withdraw(address(token), totalSupply());
	}
}
