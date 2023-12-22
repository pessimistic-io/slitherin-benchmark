// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ClonesUpgradeable } from "./ClonesUpgradeable.sol";
import { ERC20Upgradeable } from "./ERC20Upgradeable.sol";
import { ICurveVaultXChain } from "./ICurveVaultXChain.sol";
import { ILGV4XChain } from "./ILGV4XChain.sol";
import { IFeeRegistryXChain } from "./IFeeRegistryXChain.sol";
import { ICommonRegistryXChain } from "./ICommonRegistryXChain.sol";
import { ICurveStrategyXChain } from "./ICurveStrategyXChain.sol";
import { ICurveRewardReceiverXChain } from "./ICurveRewardReceiverXChain.sol";

interface IMinter {
	function is_valid_gauge(address _gauge) external view returns(bool);
}

/**
 * @title Factory contract usefull for creating new curve vaults that supports LP related
 * to the curve platform, and the gauge multi rewards attached to it.
 */

contract CurveVaultFactoryXChain {
	using ClonesUpgradeable for address;

	address public immutable crv;
	address public immutable crvMinter;

	ICommonRegistryXChain public registry;
	bytes32 public constant FEE_REGISTRY = keccak256(abi.encode("FEE_REGISTRY"));
	bytes32 public constant GOVERNANCE = keccak256(abi.encode("GOVERNANCE"));
	bytes32 public constant SD_GAUGE_IMPL = keccak256(abi.encode("SD_GAUGE_IMPL"));
	bytes32 public constant VAULT_IMPL = keccak256(abi.encode("VAULT_IMPL"));
	bytes32 public constant CURVE_STRATEGY = keccak256(abi.encode("CURVE_STRATEGY"));
	bytes32 public constant CLAIMER_REWARD = keccak256(abi.encode("CLAIMER_REWARD"));
	bytes32 public constant REWARD_RECEIVER_IMPL = keccak256(abi.encode("REWARD_RECEIVER_IMPL"));

	event VaultDeployed(address proxy, address lpToken, address impl);
	event GaugeDeployed(address proxy, address stakeToken, address impl);
	event RewardReceiverDeployed(address proxy, address impl);

	constructor(
		address _crv,
		address _registry,
		address _crvMinter
	) {
		require(_crv != address(0), "zero address");
		require(_registry != address(0), "zero address");
		require(_crvMinter != address(0), "zero address");
		crv = _crv;
		crvMinter = _crvMinter;
		registry = ICommonRegistryXChain(_registry);
	}

	/**
	 * @dev Function to clone Curve Vault and its gauge contracts
	 * @param _crvGaugeAddress curve liqudity gauge address
	 */
	function cloneAndInit(address _crvGaugeAddress) external {
		// check if the gauge is valid for the minter
		require(IMinter(crvMinter).is_valid_gauge(_crvGaugeAddress), "gauge not valid");
		address vaultLpToken = ILGV4XChain(_crvGaugeAddress).lp_token();
		string memory tokenSymbol = ERC20Upgradeable(vaultLpToken).symbol();

		address governance = registry.getAddrIfNotZero(GOVERNANCE);
		address sdGaugeImpl = registry.getAddrIfNotZero(SD_GAUGE_IMPL);
		address curveStrategy = registry.getAddrIfNotZero(CURVE_STRATEGY);
		address claimerReward = registry.getAddrIfNotZero(CLAIMER_REWARD);
		address rewardReceiverImpl = registry.getAddrIfNotZero(REWARD_RECEIVER_IMPL);
		address vaultImpl = registry.getAddrIfNotZero(VAULT_IMPL);

		// determine the vault+gauge address
		address vaultAddress = address(vaultImpl).cloneDeterministic(
			keccak256(
				abi.encodePacked(
					vaultLpToken, 
					keccak256(abi.encodePacked(governance, string(abi.encodePacked("sd", tokenSymbol, " Vault")), string(abi.encodePacked("sd", tokenSymbol, "-vault")), curveStrategy))
				)
			));
		address gaugeAddress = address(sdGaugeImpl).cloneDeterministic(
			keccak256(
				abi.encodePacked(
					vaultAddress, 
					keccak256(abi.encodePacked(governance, tokenSymbol))
				)
			));

		// Clone Vault+Gauge+RewardReceiver
		// Vault
		_cloneAndInitVault(
			vaultAddress,
			vaultLpToken,
			string(abi.encodePacked("sd", tokenSymbol, " Vault")),
			string(abi.encodePacked("sd", tokenSymbol, "-vault")),
			gaugeAddress
		);
		emit VaultDeployed(vaultAddress, vaultLpToken, vaultImpl);

		// LGV4
		_cloneAndInitGauge(gaugeAddress, vaultAddress, curveStrategy, claimerReward);
		emit GaugeDeployed(gaugeAddress, vaultAddress, sdGaugeImpl);

		// Reward Receiver 
		address rewardReceiver = _cloneAndInitRewardReceiver(rewardReceiverImpl, governance, tokenSymbol);

		// Curve strategy setters
		ICurveStrategyXChain(curveStrategy).toggleVault(vaultAddress);
		ICurveStrategyXChain(curveStrategy).setCurveGauge(vaultLpToken, _crvGaugeAddress);
		ICurveStrategyXChain(curveStrategy).setSdGauge(_crvGaugeAddress, gaugeAddress);
		ICurveStrategyXChain(curveStrategy).setRewardsReceiver(_crvGaugeAddress, rewardReceiver);
		IFeeRegistryXChain feeRegistry = IFeeRegistryXChain(registry.getAddrIfNotZero(FEE_REGISTRY));
		feeRegistry.manageFee(
			IFeeRegistryXChain.MANAGEFEE.PERFFEE, 
			_crvGaugeAddress,
			crv,
			1500
		); // %15 default
	}

	/**
	 * @dev Internal function to clone the vault
	 * @param _predictedAddr vault address predicted
	 * @param _lpToken curve LP token address
	 * @param _name vault name
	 * @param _symbol vault symbol
	 * @param _gaugePredicted lgv4 address predicted
	 */
	function _cloneAndInitVault(
		address _predictedAddr,
		address _lpToken,
		string memory _name,
		string memory _symbol,
		address _gaugePredicted
	) internal {
		ICurveVaultXChain(_predictedAddr).init(_lpToken, _name, _symbol, address(registry), _gaugePredicted);	
	}

	/**
	 * @dev Internal function to clone the gauge multi rewards
	 * @param _predictedAddr address predicted
	 * @param _stakingToken sd LP token address
	 * @param _curveStrategy curve strategy address
	 * @param _claimerReward claimer reward address
	 */
	function _cloneAndInitGauge(
		address _predictedAddr,
		address _stakingToken,
		address _curveStrategy,
		address _claimerReward
	) internal {
		ILGV4XChain(_predictedAddr).initialize(address(registry), _stakingToken, _stakingToken, crv, _curveStrategy, _claimerReward);
	}

	/**
	 * @dev Internal function to clone the reward receiver
	 * @param _impl address of contract to clone
	 * @param _governance governance address
	 * @param _symbol gauge symbol
	 */
	function _cloneAndInitRewardReceiver(
		address _impl,
		address _governance,
		string memory _symbol
	) internal returns (address) {
		ICurveRewardReceiverXChain deployed = cloneRewardReceiver(_impl, keccak256(abi.encodePacked(_governance, _symbol, address(registry))));
		deployed.init(address(registry));
		return address(deployed);
	}

	/**
	 * @dev Internal function that deploy and returns a clone of rewardReceiver impl
	 * @param _impl address of contract to clone
	 * @param _paramsHash governance+symbol+registry parameters hash
	 */
	function cloneRewardReceiver(
		address _impl,
		bytes32 _paramsHash
	) internal returns (ICurveRewardReceiverXChain) {
		address deployed = address(_impl).cloneDeterministic(
			keccak256(abi.encodePacked(address(registry), _paramsHash))
		);
		emit RewardReceiverDeployed(deployed, _impl);
		return ICurveRewardReceiverXChain(deployed);
	}

	/**
	 * @dev Function that predicts the future address passing the parameters
	 * @param _impl address of contract to clone
	 * @param _token token (LP or sdLP)
	 * @param _paramsHash parameters hash
	 */
	function predictAddress(
		address _impl,
		address _token,
		bytes32 _paramsHash
	) public view returns (address) {
		return address(_impl).predictDeterministicAddress(keccak256(abi.encodePacked(_token, _paramsHash)));
	}
}
