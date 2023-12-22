// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.7;

import "./ILendingWallet.sol";
import "./IERC20Callback.sol";

import { TokenTransferrer } from "./TokenTransferrer.sol";
import "./BaseVesta.sol";
import "./StableCoin.sol";

/**
@title LendingWallet
@notice 
	Lending Wallet is basically the wallet of our protocol "Lending Service". 
	All the funds are held inside this and only this contract will handle the transfers.
*/

contract LendingWallet is
	ILendingWallet,
	IERC20Callback,
	TokenTransferrer,
	BaseVesta
{
	using AddressUpgradeable for address;

	bytes1 public constant DEPOSIT = 0x01;
	bytes1 public constant WITHDRAW = 0x02;
	bytes1 public constant DEBT_ACCESS = 0x04;
	bytes1 public constant REDISTRIBUTION_ACCESS = 0x08;
	bytes1 public constant LENDING_MANAGER = 0x10;
	bytes1 public constant STABILITY_POOL_MANAGER = 0x20;
	// bytes1 public constant WITHDRAWER_HANDLER = 0x80;  VApp

	StableCoin public VST_TOKEN;

	uint256 internal gasCompensation;

	// asset => amount
	mapping(address => uint256) internal totalSurplusCollaterals;

	// wallet => asset => amount
	mapping(address => mapping(address => uint256)) internal userSurplusCollaterals;

	mapping(address => uint256) internal collaterals;
	mapping(address => uint256) internal debts;

	mapping(address => uint256) internal redistributionCollaterals;
	mapping(address => uint256) internal redistributionDebts;

	function setUp(
		address _vstToken,
		address _lendingManager,
		address _stabilityPoolManager
	) external initializer {
		if (
			!_vstToken.isContract() ||
			!_lendingManager.isContract() ||
			!_stabilityPoolManager.isContract()
		) revert InvalidContract();

		__BASE_VESTA_INIT();

		VST_TOKEN = StableCoin(_vstToken);

		_setPermission(_lendingManager, LENDING_MANAGER);
		_setPermission(_stabilityPoolManager, STABILITY_POOL_MANAGER);
	}

	function registerNewLendingEntity(address _entity)
		external
		hasPermission(LENDING_MANAGER)
		onlyContract(_entity)
	{
		_setPermission(_entity, WITHDRAW | DEPOSIT | DEBT_ACCESS);
	}

	function unregisterLendingEntity(address _entity)
		external
		hasPermissionOrOwner(LENDING_MANAGER)
	{
		_clearPermission(_entity);
	}

	function registerNewStabilityPoolEntity(address _entity)
		external
		hasPermission(STABILITY_POOL_MANAGER)
		onlyContract(_entity)
	{
		_setPermission(_entity, WITHDRAW);
	}

	function unregisterStabilityPoolEntity(address _entity)
		external
		hasPermissionOrOwner(STABILITY_POOL_MANAGER)
	{
		_clearPermission(_entity);
	}

	function transfer(
		address _token,
		address _to,
		uint256 _amount
	) external override hasPermission(WITHDRAW) {
		_transfer(_token, _to, _amount, true);

		emit CollateralChanged(_token, collaterals[RESERVED_ETH_ADDRESS]);
	}

	function _transfer(
		address _token,
		address _to,
		uint256 _amount,
		bool _vaultBalance
	) internal nonReentrant {
		uint256 sanitizedAmount = _sanitizeValue(_token, _amount);

		if (sanitizedAmount == 0) return;

		if (_vaultBalance) {
			collaterals[_token] -= _amount;
		}

		_performTokenTransfer(_token, _to, sanitizedAmount, true);

		emit Withdraw(_token, _to, _amount);
	}

	receive() external payable {
		if (hasPermissionLevel(msg.sender, DEPOSIT)) {
			collaterals[RESERVED_ETH_ADDRESS] += msg.value;
			emit Deposit(RESERVED_ETH_ADDRESS, msg.value);
			emit CollateralChanged(
				RESERVED_ETH_ADDRESS,
				collaterals[RESERVED_ETH_ADDRESS]
			);
		}
	}

	function receiveERC20(address _token, uint256 _amount)
		external
		override
		hasPermission(DEPOSIT)
	{
		if (RESERVED_ETH_ADDRESS == _token) {
			revert CannotBeNativeChainToken();
		}

		collaterals[_token] += _amount;
		emit Deposit(_token, _amount);
		emit CollateralChanged(_token, collaterals[_token]);
	}

	function decreaseDebt(
		address _token,
		address _from,
		uint256 _amount
	) external override hasPermission(DEBT_ACCESS) {
		debts[_token] -= _amount;
		VST_TOKEN.burn(_from, _amount);

		emit DebtChanged(_token, debts[_token]);
	}

	function increaseDebt(
		address _token,
		address _to,
		uint256 _amountToMint,
		uint256 _amountToDebt
	) external override hasPermission(DEBT_ACCESS) {
		debts[_token] += _amountToDebt;
		VST_TOKEN.mintDebt(_token, _to, _amountToMint);

		emit DebtChanged(_token, debts[_token]);
	}

	function moveCollateralToRedistribution(address _token, uint256 _amount)
		external
		override
		hasPermission(REDISTRIBUTION_ACCESS)
	{
		collaterals[_token] -= _amount;
		redistributionCollaterals[_token] += _amount;

		emit CollateralChanged(_token, collaterals[_token]);
		emit RedistributionCollateralChanged(_token, redistributionCollaterals[_token]);
	}

	function moveDebtToRedistribution(address _token, uint256 _amount)
		external
		override
		hasPermission(REDISTRIBUTION_ACCESS)
	{
		debts[_token] -= _amount;
		redistributionDebts[_token] += _amount;

		emit DebtChanged(_token, debts[_token]);
		emit RedistributionDebtChanged(_token, redistributionDebts[_token]);
	}

	function returnRedistributionCollateral(address _token, uint256 _amount)
		external
		override
		hasPermission(REDISTRIBUTION_ACCESS)
	{
		redistributionCollaterals[_token] -= _amount;
		collaterals[_token] += _amount;

		emit CollateralChanged(_token, collaterals[_token]);
		emit RedistributionCollateralChanged(_token, redistributionCollaterals[_token]);
	}

	function returnRedistributionDebt(address _token, uint256 _amount)
		external
		override
		hasPermission(REDISTRIBUTION_ACCESS)
	{
		redistributionDebts[_token] -= _amount;
		debts[_token] += _amount;

		emit DebtChanged(_token, debts[_token]);
		emit RedistributionDebtChanged(_token, redistributionDebts[_token]);
	}

	function mintGasCompensation(uint256 _amount)
		external
		override
		hasPermission(DEPOSIT)
	{
		gasCompensation += _amount;
		VST_TOKEN.mint(address(this), _amount);
		emit GasCompensationChanged(gasCompensation);
	}

	function burnGasCompensation(uint256 _amount)
		external
		override
		hasPermission(WITHDRAW)
	{
		gasCompensation -= _amount;
		VST_TOKEN.burn(address(this), _amount);
		emit GasCompensationChanged(gasCompensation);
	}

	function refundGasCompensation(address _user, uint256 _amount)
		external
		override
		hasPermission(WITHDRAW)
	{
		gasCompensation -= _amount;
		_transfer(address(VST_TOKEN), _user, _amount, false);
		emit GasCompensationChanged(gasCompensation);
	}

	function mintVstTo(
		address _token,
		address _to,
		uint256 _amount,
		bool _depositCallback
	) external override hasPermission(WITHDRAW) nonReentrant {
		VST_TOKEN.mintDebt(_token, _to, _amount);

		if (_depositCallback && _to.isContract()) {
			IERC20Callback(_to).receiveERC20(_token, _amount);
		}

		emit VstMinted(_to, _amount);
	}

	function addSurplusCollateral(
		address _token,
		address _user,
		uint256 _amount
	) external override hasPermission(DEPOSIT) {
		uint256 newSurplusTotal = totalSurplusCollaterals[_token] += _amount;
		uint256 newUserSurplusTotal = userSurplusCollaterals[_user][_token] += _amount;

		emit SurplusCollateralChanged(newSurplusTotal);
		emit UserSurplusCollateralChanged(_user, newUserSurplusTotal);
	}

	function claimSurplusCollateral(address _token) external override {
		uint256 supply = userSurplusCollaterals[msg.sender][_token];

		if (supply == 0) return;

		uint256 newSurplusTotal = totalSurplusCollaterals[_token] -= supply;
		userSurplusCollaterals[msg.sender][_token] = 0;

		_transfer(_token, msg.sender, supply, false);

		emit SurplusCollateralChanged(newSurplusTotal);
		emit UserSurplusCollateralChanged(msg.sender, 0);
	}

	function getGasCompensation() external view override returns (uint256) {
		return gasCompensation;
	}

	function getLendingBalance(address _token)
		external
		view
		override
		returns (uint256 collaterals_, uint256 debts_)
	{
		return (collaterals[_token], debts[_token]);
	}

	function getLendingCollateral(address _token)
		external
		view
		override
		returns (uint256)
	{
		return collaterals[_token];
	}

	function getLendingDebts(address _token) external view override returns (uint256) {
		return debts[_token];
	}

	function getRedistributionCollateral(address _token)
		external
		view
		override
		returns (uint256)
	{
		return redistributionCollaterals[_token];
	}

	function getRedistributionDebt(address _token)
		external
		view
		override
		returns (uint256)
	{
		return redistributionDebts[_token];
	}

	function getTotalSurplusCollateral(address _token)
		external
		view
		override
		returns (uint256)
	{
		return totalSurplusCollaterals[_token];
	}

	function getUserSurplusCollateral(address _token, address _user)
		external
		view
		override
		returns (uint256)
	{
		return userSurplusCollaterals[_user][_token];
	}
}

