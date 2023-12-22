// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.7;

import "./BaseVesta.sol";
import "./ILendingParameters.sol";

/**
@title LendingParameters
@notice Holds the parameters of the Lending Service
@dev All percentages are in BPS. (1e18 / 10_000) * X BPS = Y%
	 BPS = percentage wanted * 100
	 BPS in ether = percentage wanted / 100 ether
*/

contract LendingParameters is ILendingParameters, BaseVesta {
	bytes1 public constant CONFIG = 0x01;

	CompactedParameters private DEFAULT_PARAMTERS =
		CompactedParameters({
			mintCap: 0,
			stabilityPoolLiquidationRatio: 1.1 ether, // 110%
			stabilityPoolLiquidationBonus: 0.1 ether, // 10%
			borrowingFeeFloor: 0.005 ether, // 0.5%
			borrowingMaxFloor: 0.05 ether, // 5%
			redemptionFeeFloor: 0.005 ether, // 0.5%
			lockable: false,
			riskable: false
		});

	uint256 private gasCompensation = 30 ether;
	uint256 private minimumNetDebt = 300 ether;
	uint256 private liquidationCompensationCollateral = 0.01 ether; //1%

	mapping(address => CompactedParameters) lendingServiceParameters;

	function setUp() external initializer {
		__BASE_VESTA_INIT();
	}

	function setGasCompensation(uint256 _gasCompensation)
		external
		override
		hasPermissionOrOwner(CONFIG)
	{
		gasCompensation = _gasCompensation;
		emit GasCompensationChanged(gasCompensation);
	}

	function setMinimumNetDebt(uint256 _minDebt)
		external
		override
		hasPermissionOrOwner(CONFIG)
	{
		minimumNetDebt = _minDebt;
		emit MinimumNetDebtChanged(minimumNetDebt);
	}

	function setLendingServiceParameters(
		address _lendingService,
		CompactedParameters calldata _parameters
	) external override hasPermissionOrOwner(CONFIG) {
		lendingServiceParameters[_lendingService] = _parameters;
		emit ParameterChanged(_lendingService, _parameters);
	}

	function setLendingServiceParametersToDefault(address _lendingService)
		external
		override
		hasPermissionOrOwner(CONFIG)
	{
		lendingServiceParameters[_lendingService] = DEFAULT_PARAMTERS;
		emit ParameterChanged(_lendingService, DEFAULT_PARAMTERS);
	}

	function setDefaultParameters(CompactedParameters calldata _parameters)
		external
		onlyOwner
	{
		DEFAULT_PARAMTERS = _parameters;
		emit DefaultParametersChanged(_parameters);
	}

	function getGasCompensation() external view override returns (uint256) {
		return gasCompensation;
	}

	function getMinimumNetDebt() external view override returns (uint256) {
		return minimumNetDebt;
	}

	function getMintCap(address _lendingService)
		external
		view
		override
		returns (uint256)
	{
		return lendingServiceParameters[_lendingService].mintCap;
	}

	function getLiquidationParameters(address _lendingService)
		external
		view
		override
		returns (
			uint64 stabilityPoolLiquidationRatio_,
			uint64 stabilityPoolLiquidationBonus_,
			uint256 liquidationCompensationCollateral_
		)
	{
		CompactedParameters memory parameter = lendingServiceParameters[_lendingService];
		return (
			parameter.stabilityPoolLiquidationRatio,
			parameter.stabilityPoolLiquidationBonus,
			liquidationCompensationCollateral
		);
	}

	function getBorrowingFeeFloors(address _lendingService)
		external
		view
		override
		returns (uint64 floor_, uint64 maxFloor_)
	{
		CompactedParameters memory parameter = lendingServiceParameters[_lendingService];
		return (parameter.borrowingFeeFloor, parameter.borrowingMaxFloor);
	}

	function isLockable(address _lendingService)
		external
		view
		override
		returns (bool)
	{
		return lendingServiceParameters[_lendingService].lockable;
	}

	function isRiskable(address _lendingService)
		external
		view
		override
		returns (bool)
	{
		return lendingServiceParameters[_lendingService].riskable;
	}

	function getAssetParameters(address _lendingService)
		external
		view
		override
		returns (CompactedParameters memory)
	{
		return lendingServiceParameters[_lendingService];
	}

	function getDefaultParameters()
		external
		view
		override
		returns (CompactedParameters memory)
	{
		return DEFAULT_PARAMTERS;
	}
}

