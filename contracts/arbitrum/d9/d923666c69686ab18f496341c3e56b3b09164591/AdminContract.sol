pragma solidity ^0.8.10;

import "./ProxyAdmin.sol";
import "./TransparentUpgradeableProxy.sol";
import "./ClonesUpgradeable.sol";

import "./CheckContract.sol";
import "./ArbitroveBase.sol";

import "./IStabilityPoolManager.sol";
import "./IVestaParameters.sol";
import "./IStabilityPool.sol";
import "./ICommunityIssuance.sol";

contract AdminContract is ProxyAdmin, ArbitroveBase {
	string public constant NAME = "AdminContract";

	bytes32 public constant STABILITY_POOL_NAME_BYTES =
		0xf704b47f65a99b2219b7213612db4be4a436cdf50624f4baca1373ef0de0aac7;
	bool public isInitialized;

	IVestaParameters private vestaParameters;
	IStabilityPoolManager private stabilityPoolManager;
	ICommunityIssuance private communityIssuance;

	address borrowerOperationsAddress;
	address troveManagerAddress;
	address uTokenAddress;
	address sortedTrovesAddress;

	function setAddresses(
		address _paramaters,
		address _stabilityPoolManager,
		address _borrowerOperationsAddress,
		address _troveManagerAddress,
		address _uTokenAddress,
		address _sortedTrovesAddress,
		address _communityIssuanceAddress,
		address _wstETHAddress
	) external onlyOwner {
		require(!isInitialized);
		CheckContract(_paramaters);
		CheckContract(_stabilityPoolManager);
		CheckContract(_borrowerOperationsAddress);
		CheckContract(_troveManagerAddress);
		CheckContract(_uTokenAddress);
		CheckContract(_sortedTrovesAddress);
		CheckContract(_communityIssuanceAddress);
		CheckContract(_wstETHAddress);
		isInitialized = true;

		borrowerOperationsAddress = _borrowerOperationsAddress;
		troveManagerAddress = _troveManagerAddress;
		uTokenAddress = _uTokenAddress;
		sortedTrovesAddress = _sortedTrovesAddress;
		communityIssuance = ICommunityIssuance(_communityIssuanceAddress);
		wstETH = _wstETHAddress;

		vestaParameters = IVestaParameters(_paramaters);
		stabilityPoolManager = IStabilityPoolManager(_stabilityPoolManager);
	}

	//Needs to approve Community Issuance to use this fonction.
	function addNewCollateral(
		address _asset,
		address _stabilityPoolImplementation,
		address _chainlinkOracle,
		bytes32 _tellorId,
		uint256 assignedToken,
		uint256 _tokenPerWeekDistributed,
		uint256 redemptionLockInDay
	) external onlyOwner onlyWstETH(_asset) {
		require(
			stabilityPoolManager.unsafeGetAssetStabilityPool(_asset) == address(0),
			"This collateral already exists"
		);
		require(
			IStabilityPool(_stabilityPoolImplementation).getNameBytes() == STABILITY_POOL_NAME_BYTES,
			"Invalid Stability pool"
		);

		vestaParameters.priceFeed().addOracle(_asset, _chainlinkOracle, _tellorId);
		vestaParameters.setAsDefaultWithRemptionBlock(_asset, redemptionLockInDay);

		address clonedStabilityPool = ClonesUpgradeable.clone(_stabilityPoolImplementation);
		require(clonedStabilityPool != address(0), "Failed to clone contract");

		TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
			clonedStabilityPool,
			address(this),
			abi.encodeWithSignature(
				"setAddresses(address,address,address,address,address,address,address)",
				_asset,
				borrowerOperationsAddress,
				troveManagerAddress,
				uTokenAddress,
				sortedTrovesAddress,
				address(communityIssuance),
				address(vestaParameters)
			)
		);

		address proxyAddress = address(proxy);
		stabilityPoolManager.addStabilityPool(_asset, proxyAddress);
		communityIssuance.addFundToStabilityPoolFrom(proxyAddress, assignedToken, msg.sender);
		communityIssuance.setWeeklyYouDistribution(proxyAddress, _tokenPerWeekDistributed);
	}
}

