// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

import { CompactedParameters } from "./ParameterModel.sol";

interface ILendingParameters {
	event ParameterChanged(address indexed asset, CompactedParameters parameters);
	event GasCompensationChanged(uint256 gasCompensation);
	event MinimumNetDebtChanged(uint256 minimumDebt);
	event DefaultParametersChanged(CompactedParameters);

	/** 
	@notice setGasCompensation to change the whole protocol gas compensation
	@dev requires CONFIG or Owner permission to execute this function
	@param _gasCompensation new gas compensation value
	*/
	function setGasCompensation(uint256 _gasCompensation) external;

	/** 
	@notice setMinimumNetDebt to change the minimum debt to open a vault in the system
	@dev requires CONFIG or Owner permission to execute this function
	@param _minDebt new gas minimum net debt value
	*/
	function setMinimumNetDebt(uint256 _minDebt) external;

	/** 
	@notice setLendingServiceParameters to change the parameters of a specific asset 
	@dev requires CONFIG or Owner permission to execute this function
	@param _lendingService address of the Lending Service
	@param _parameters new parameters
	*/
	function setLendingServiceParameters(
		address _lendingService,
		CompactedParameters calldata _parameters
	) external;

	/** 
	@notice setLendingServiceParametersToDefault to put an asset to the default protocol values
	@dev requires CONFIG or Owner permission to execute this function
	@param _lendingService address of the Lending Service
	*/
	function setLendingServiceParametersToDefault(address _lendingService) external;

	/** 
	@notice getGasCompensation to get the current gas compensation value
	@return gasCompensation current value
	*/
	function getGasCompensation() external view returns (uint256);

	/** 
	@notice getMinimumNetDebt to get the current minimum net debt value
	@return minimumNetDebt current value
	*/
	function getMinimumNetDebt() external view returns (uint256);

	/** 
	@notice getMintCap to get the maxmimum mint cap of vst
	@dev 0 means unlimited / uncapped
	@param _lendingService address of the Lending Service
	@return mintCap return the max mintable vst from this asset
	*/
	function getMintCap(address _lendingService) external view returns (uint256);

	/** 
	@notice getLiquidationParameters to get liquidation info of an asset
	@param _lendingService address of the Lending Service
	@return stabilityPoolLiquidationRatio_ is the ratio that a vault will get liquidated
	@return stabilityPoolLiquidationBonus_ is the percentage that goes to Stability pool
	@return liquidationCompensationCollateral_ is the percentage that goes to the caller for gas compensation
	*/
	function getLiquidationParameters(address _lendingService)
		external
		view
		returns (
			uint64 stabilityPoolLiquidationRatio_,
			uint64 stabilityPoolLiquidationBonus_,
			uint256 liquidationCompensationCollateral_
		);

	/** 
	@notice getBorrowingFeeFloors to get the fee floors of an asset
	@param _lendingService address of the Lending Service
	@return floor_ is the minimum the user need to accept as fee
	@return maxFloor_ is the maximum fee that can be accepted
	*/
	function getBorrowingFeeFloors(address _lendingService)
		external
		view
		returns (uint64 floor_, uint64 maxFloor_);

	/** 
	@notice isLockable check if the asset can be locked
	@param _lendingService address of the Lending Service
	@return isLocakble
	*/
	function isLockable(address _lendingService) external view returns (bool);

	/** 
	@notice isRiskable check if the asset can use in the riskzone
	@param _lendingService address of the Lending Service
	@return isRiskable
	*/
	function isRiskable(address _lendingService) external view returns (bool);

	/** 
	@notice getAssetParameters to get the parameters of an asset
	@param _lendingService address of the Lending Service
	@return compactedParameters all the parameters of the asset
	*/
	function getAssetParameters(address _lendingService)
		external
		view
		returns (CompactedParameters memory);

	/** 
	@notice getDefaultParameters returns the default constant of the protocol
	@return defaultParameters return the private constant DEFAULT_PARAMETERS
	*/
	function getDefaultParameters() external view returns (CompactedParameters memory);
}

