//SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./Ownable.sol";
import "./Clones.sol";

import "./CheckContract.sol";
import "./Initializable.sol";
import "./IStabilityPoolManager.sol";
import "./IPSYParameters.sol";
import "./IStabilityPool.sol";
import "./ICommunityIssuance.sol";

contract AdminContract is Ownable, Initializable {
	string public constant NAME = "AdminContract";

	bytes32 public constant STABILITY_POOL_NAME_BYTES =
		0xf704b47f65a99b2219b7213612db4be4a436cdf50624f4baca1373ef0de0aac7;
	bool public isInitialized;

	IPSYParameters private psyParameters;
	IStabilityPoolManager private stabilityPoolManager;
	ICommunityIssuance private communityIssuance;

	address borrowerOperationsAddress;
	address troveManagerAddress;
	address troveManagerHelpersAddress;
	address slsdTokenAddress;
	address sortedTrovesAddress;

	bool isPSYReady;

	function setAddresses(
		address _paramaters,
		address _stabilityPoolManager,
		address _borrowerOperationsAddress,
		address _troveManagerAddress,
		address _troveManagerHelpersAddress,
		address _slsdTokenAddress,
		address _sortedTrovesAddress,
		address _communityIssuanceAddress
	) external initializer onlyOwner {
		require(!isInitialized, "Already initialized");
		CheckContract(_paramaters);
		CheckContract(_stabilityPoolManager);
		CheckContract(_borrowerOperationsAddress);
		CheckContract(_troveManagerAddress);
		CheckContract(_troveManagerHelpersAddress);
		CheckContract(_slsdTokenAddress);
		CheckContract(_sortedTrovesAddress);
		isInitialized = true;

		borrowerOperationsAddress = _borrowerOperationsAddress;
		troveManagerAddress = _troveManagerAddress;
		troveManagerHelpersAddress = _troveManagerHelpersAddress;
		slsdTokenAddress = _slsdTokenAddress;
		sortedTrovesAddress = _sortedTrovesAddress;

		if(_communityIssuanceAddress != address(0)){
			CheckContract(_communityIssuanceAddress);
			communityIssuance = ICommunityIssuance(_communityIssuanceAddress);
			isPSYReady = true;
		}

		psyParameters = IPSYParameters(_paramaters);
		stabilityPoolManager = IStabilityPoolManager(_stabilityPoolManager);
	}

	//Needs to approve Community Issuance to use this function.
	function addNewCollateral(
		address _stabilityPoolProxyAddress,
		address _oracle,
		uint256 assignedToken,
		uint256 _tokenPerWeekDistributed,
		uint256 redemptionLockInDay
	) external onlyOwner {
		address _asset = IStabilityPool(_stabilityPoolProxyAddress).getAssetType();

		require(
			stabilityPoolManager.unsafeGetAssetStabilityPool(_asset) == address(0),
			"This collateral already exists"
		);
		
		psyParameters.priceFeed().addOracle(_asset, _oracle);
		psyParameters.setAsDefaultWithRemptionBlock(_asset, redemptionLockInDay);
		
		stabilityPoolManager.addStabilityPool(_asset, _stabilityPoolProxyAddress);
		
		if(isPSYReady){
			communityIssuance.addFundToStabilityPoolFrom(
				_stabilityPoolProxyAddress,
				assignedToken,
				msg.sender
			);
			communityIssuance.setWeeklyPSYDistribution(
				_stabilityPoolProxyAddress,
				_tokenPerWeekDistributed
			);
		}
		
	}


}

