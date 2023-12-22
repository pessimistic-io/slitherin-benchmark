// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { IModuleInterest } from "./IModuleInterest.sol";
import { IInterestManager } from "./IInterestManager.sol";

import { CropJoinAdapter } from "./CropJoinAdapter.sol";
import { FullMath } from "./FullMath.sol";

import { SD59x18, sd, intoUint256 } from "./SD59x18.sol";
import { UD60x18, ud, intoUint256 } from "./UD60x18.sol";

contract VestaEIR is CropJoinAdapter, IModuleInterest {
	uint256 public constant PRECISION = 1e18;
	uint256 public constant YEAR_MINUTE = 1.901285e6;
	uint256 public constant COMPOUND = 2.71828e18;

	uint256 public currentEIR;
	uint256 public lastUpdate;
	uint256 public totalDebt;

	uint8 public risk;

	address public interestManager;
	mapping(address => uint256) private balances;

	modifier onlyInterestManager() {
		if (msg.sender != interestManager) {
			revert NotInterestManager();
		}

		_;
	}

	function setUp(
		address _interestManager,
		string memory _moduleName,
		uint8 _defaultRisk
	) external initializer {
		__INIT_ADAPTOR(_moduleName);

		interestManager = _interestManager;
		risk = _defaultRisk;

		lastUpdate = block.timestamp;
		_updateEIR(IInterestManager(_interestManager).getLastVstPrice());
	}

	function setRisk(uint8 _newRisk) external onlyOwner {
		risk = _newRisk;
		_updateEIR(IInterestManager(interestManager).getLastVstPrice());

		emit RiskChanged(_newRisk);
	}

	function increaseDebt(address _vault, uint256 _debt)
		external
		override
		onlyInterestManager
		returns (uint256 addedInterest_)
	{
		uint256 newShare = PRECISION;
		addedInterest_ = _distributeInterestRate(_vault);

		uint256 totalBalance = balances[_vault] += _debt;

		if (totalWeight > 0) {
			newShare = (totalWeight * (_debt + addedInterest_)) / totalDebt;
		}

		_addShare(_vault, newShare);
		totalDebt += _debt;

		emit DebtChanged(_vault, totalBalance);
		emit SystemDebtChanged(totalDebt);

		return addedInterest_;
	}

	function decreaseDebt(address _vault, uint256 _debt)
		external
		override
		onlyInterestManager
		returns (uint256 addedInterest_)
	{
		if (_debt == 0) revert CannotBeZero();

		addedInterest_ = _distributeInterestRate(_vault);

		uint256 newShare = 0;
		uint256 balanceTotal = balances[_vault];

		balanceTotal = balances[_vault] -= _debt;

		if (totalWeight > 0 && balanceTotal > 0) {
			newShare = (totalWeight * balanceTotal) / totalDebt;
		}

		_exitShare(_vault, shareOf(_vault));
		_addShare(_vault, newShare);

		totalDebt -= _debt;

		emit DebtChanged(_vault, balanceTotal);
		emit SystemDebtChanged(totalDebt);

		return addedInterest_;
	}

	function exit(address _vault)
		external
		override
		onlyInterestManager
		returns (uint256 addedInterest_)
	{
		uint256 userBalance = balances[_vault];
		if (userBalance == 0) revert NoDebtFound();

		addedInterest_ = _distributeInterestRate(_vault);
		userBalance += addedInterest_;

		if (totalDebt <= userBalance) {
			totalDebt = 0;
		} else {
			totalDebt -= userBalance;
		}

		balances[_vault] = 0;

		_exitShare(_vault, shareOf(_vault));

		if (totalWeight == 0) totalDebt = 0;

		return addedInterest_;
	}

	function updateEIR(uint256 _vstPrice)
		external
		override
		onlyInterestManager
		returns (uint256 mintedInterest_)
	{
		return _updateEIR(_vstPrice);
	}

	function _updateEIR(uint256 _vstPrice)
		internal
		returns (uint256 mintedInterest_)
	{
		uint256 newEIR = calculateEIR(risk, _vstPrice);
		uint256 oldEIR = currentEIR;

		uint256 lastDebt = totalDebt;
		uint256 minuteDifference = (block.timestamp - lastUpdate) / 1 minutes;
		currentEIR = newEIR;

		emit EIRChanged(newEIR);

		if (minuteDifference == 0) return 0;

		lastUpdate = block.timestamp;

		totalDebt += compound(
			oldEIR,
			totalDebt,
			minuteDifference * YEAR_MINUTE
		);

		uint256 interest = totalDebt - lastDebt;

		interestMinted += interest;
		emit InterestMinted(interest);

		return interest;
	}

	function _distributeInterestRate(address _user)
		internal
		returns (uint256 emittedFee_)
	{
		if (totalWeight > 0) {
			share = share + FullMath.rdiv(_crop(), totalWeight);
		}

		uint256 last = crops[_user];
		uint256 curr = FullMath.rmul(userShares[_user], share);
		if (curr > last) {
			emittedFee_ = curr - last;
			balances[_user] += emittedFee_;
			interestMinted -= emittedFee_;
		}

		stock = interestMinted;
		return emittedFee_;
	}

	function compound(
		uint256 _eir,
		uint256 _debt,
		uint256 _timeInYear
	) public pure returns (uint256) {
		return
			FullMath.mulDiv(
				_debt,
				intoUint256(ud(COMPOUND).pow(ud((_eir * 100) * _timeInYear))),
				1e18
			) - _debt;
	}

	function getNotEmittedInterestRate(address user)
		external
		view
		override
		returns (uint256)
	{
		if (totalWeight == 0) return 0;

		uint256 minuteDifference = (block.timestamp - lastUpdate) / 1 minutes;
		uint256 incomingMinting = 0;

		if (minuteDifference != 0) {
			incomingMinting = compound(
				currentEIR,
				totalDebt,
				minuteDifference * YEAR_MINUTE
			);
		}

		// duplicate harvest logic
		uint256 crop = (interestMinted + incomingMinting) - stock;
		uint256 newShare = share + FullMath.rdiv(crop, totalWeight);

		uint256 last = this.crops(user);
		uint256 curr = FullMath.rmul(this.userShares(user), newShare);
		if (curr > last) return curr - last;
		return 0;
	}

	function calculateEIR(uint8 _risk, uint256 _price)
		public
		pure
		returns (uint256)
	{
		if (_price < 0.95e18) {
			_price = 0.95e18;
		} else if (_price > 1.05e18) {
			_price = 1.05e18;
		}

		int256 P = ((int256(_price) - 1 ether)) * -1.0397e4;

		uint256 a;

		if (_risk == 0) {
			a = 0.5e4;
		} else if (_risk == 1) {
			a = 0.75e4;
		} else {
			a = 1.25e4;
		}

		int256 exp = (P / 1e2);
		return FullMath.mulDivRoundingUp(a, intoUint256(sd(exp).exp()), 1e20); // Scale to BPS
	}

	function getDebtOf(address _vault)
		external
		view
		override
		returns (uint256)
	{
		return balances[_vault];
	}

	function syncWithProtocol(uint256 _amount)
		external
		override
		onlyInterestManager
	{
		totalDebt = _amount + interestMinted;
	}
}


