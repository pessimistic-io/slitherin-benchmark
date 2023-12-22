// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Initializable } from "./Initializable.sol";
import { IERC20 } from "./IERC20.sol";
import { ILGV4XChain } from "./ILGV4XChain.sol";
import { IFeeRegistryXChain } from "./IFeeRegistryXChain.sol";
import { ICommonRegistryXChain } from "./ICommonRegistryXChain.sol";
import { ICurveRewardReceiverXChain } from "./ICurveRewardReceiverXChain.sol";

contract CurveRewardReceiverXChain is Initializable, ICurveRewardReceiverXChain {

    ICommonRegistryXChain public registry;

	bytes32 public constant ACCUMULATOR = keccak256(abi.encode("ACCUMULATOR"));
	bytes32 public constant FEE_REGISTRY = keccak256(abi.encode("FEE_REGISTRY"));
	bytes32 public constant PERF_FEE_RECIPIENT = keccak256(abi.encode("PERF_FEE_RECIPIENT"));
	bytes32 public constant VE_SDT_FEE_PROXY = keccak256(abi.encode("VE_SDT_FEE_PROXY"));

    event Claimed(
        address indexed gauge, 
        address indexed rewardToken, 
        uint256 netClaimed, 
        uint256 feesCharged
    );

    function init(address _registry) public override initializer {
		require(_registry != address(0), "zero address");
        registry = ICommonRegistryXChain(_registry);
	}

	/// @notice function to claim on behalf of a user 
	/// @param _curveGauge curve gauge address
	/// @param _sdGauge stake DAO gauge address 
	/// @param _user user address to claim for 
    function claimExtraRewards(
        address _curveGauge, 
        address _sdGauge,
        address _user
    ) external override {
        // Claim all extra rewards, they will be send here
        ILGV4XChain(_curveGauge).claim_rewards(_user);
        uint256 nrRewardTokens = ILGV4XChain(_curveGauge).reward_count();
	    for(uint256 i; i < nrRewardTokens; ++i) {
			address rewardToken = ILGV4XChain(_curveGauge).reward_tokens(i);
			uint256 rewardBalance = IERC20(rewardToken).balanceOf(address(this));
            if (rewardBalance > 0) {
                uint256 netReward = sendFee(_curveGauge, rewardToken, rewardBalance);
			    IERC20(rewardToken).approve(_sdGauge, netReward);
			    ILGV4XChain(_sdGauge).deposit_reward_token(rewardToken, netReward);
			    require(IERC20(rewardToken).balanceOf(address(this)) == 0, "something left");
			    emit Claimed(_curveGauge, rewardToken, netReward, rewardBalance - netReward);
            }
		}
    }

	/// @notice internal function to send fees to recipients 
	/// @param _gauge curve gauge address
	/// @param _rewardToken reward token address
	/// @param _rewardBalance reward balance total amount
    function sendFee(
		address _gauge,
		address _rewardToken,
		uint256 _rewardBalance
	) internal returns (uint256) {
		// calculate the amount for each fee recipient
        IFeeRegistryXChain feeRegistry = IFeeRegistryXChain(registry.getAddrIfNotZero(FEE_REGISTRY));
        uint256 baseFee = feeRegistry.BASE_FEE();
		uint256 multisigFee = (_rewardBalance * feeRegistry.getFee(_gauge, _rewardToken, IFeeRegistryXChain.MANAGEFEE.PERFFEE)) / baseFee;
		uint256 accumulatorPart = (_rewardBalance * feeRegistry.getFee(_gauge, _rewardToken, IFeeRegistryXChain.MANAGEFEE.ACCUMULATORFEE)) / baseFee;
		uint256 veSDTPart = (_rewardBalance * feeRegistry.getFee(_gauge, _rewardToken, IFeeRegistryXChain.MANAGEFEE.VESDTFEE)) / baseFee;
		uint256 claimerPart = (_rewardBalance * feeRegistry.getFee(_gauge, _rewardToken, IFeeRegistryXChain.MANAGEFEE.CLAIMERREWARD)) / baseFee;
		// send
		if (accumulatorPart > 0) {
			address accumulator = registry.getAddrIfNotZero(ACCUMULATOR);
			IERC20(_rewardToken).transfer(accumulator, accumulatorPart);
		}
		if (multisigFee > 0) {
			address perfFeeRecipient = registry.getAddrIfNotZero(PERF_FEE_RECIPIENT);
			IERC20(_rewardToken).transfer(perfFeeRecipient, multisigFee);
		} 
		if (veSDTPart > 0) {
			address veSDTFeeProxy = registry.getAddrIfNotZero(VE_SDT_FEE_PROXY);
			IERC20(_rewardToken).transfer(veSDTFeeProxy, veSDTPart);
		}
		if (claimerPart > 0) IERC20(_rewardToken).transfer(msg.sender, claimerPart);
		return _rewardBalance - multisigFee - accumulatorPart - veSDTPart - claimerPart;
	}    
}
