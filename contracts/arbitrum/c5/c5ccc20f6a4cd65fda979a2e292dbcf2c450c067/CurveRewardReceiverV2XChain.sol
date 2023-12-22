// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "./IERC20.sol";
import { ILGV4XChain } from "./ILGV4XChain.sol";
import { IFeeRegistryXChain } from "./IFeeRegistryXChain.sol";
import { ICommonRegistryXChain } from "./ICommonRegistryXChain.sol";
import { ICurveRewardReceiverV2XChain } from "./ICurveRewardReceiverV2XChain.sol";

contract CurveRewardReceiverV2XChain {
    ICommonRegistryXChain public immutable registry;
    ILGV4XChain public immutable curveGauge;
    ILGV4XChain public immutable sdGauge;
    address public immutable locker;

	bytes32 public constant ACCUMULATOR = keccak256(abi.encode("ACCUMULATOR"));
	bytes32 public constant FEE_REGISTRY = keccak256(abi.encode("FEE_REGISTRY"));
	bytes32 public constant PERF_FEE_RECIPIENT = keccak256(abi.encode("PERF_FEE_RECIPIENT"));
	bytes32 public constant VE_SDT_FEE_PROXY = keccak256(abi.encode("VE_SDT_FEE_PROXY"));

    event ClaimedAndNotified(
        address indexed sdgauge, 
        address indexed rewardToken, 
        uint256 notified, 
        uint256 feesCharged
    );

    event Notified(
        address indexed sdgauge, 
        address indexed rewardToken, 
        uint256 notified, 
        uint256 feesCharged
    );

    constructor(
        address _registry, 
        address _curveGauge, 
        address _sdGauge, 
        address _locker
    ) {
        registry = ICommonRegistryXChain(_registry);
        curveGauge = ILGV4XChain(_curveGauge);
        sdGauge = ILGV4XChain(_sdGauge);
        locker = _locker;
	}

    /// @notice function to claim on behalf of a user
	/// @param _curveGauge curve gauge address
	/// @param _sdGauge stake DAO gauge address 
	/// @param _user user address to claim for 
    function claimExtraRewards(
        address _curveGauge, 
        address _sdGauge,
        address _user
    ) external {
        // input params won't be used (defined for backward compatibility with the strategy)
        _claimExtraRewards();
    }

    /// @notice function to claim all extra rewards on behalf of the locker
    function claimExtraReward() external {
        _claimExtraRewards();
    }

    /// @notice function to claim all extra rewards on behalf of the locker
    function _claimExtraRewards() internal {
        curveGauge.claim_rewards(locker);
        uint256 nrRewardTokens = curveGauge.reward_count();
	    for(uint256 i; i < nrRewardTokens; ++i) {
			address rewardToken = curveGauge.reward_tokens(i);
			uint256 rewardBalance = IERC20(rewardToken).balanceOf(address(this));
            if (rewardBalance > 0) {
                uint256 netReward = _sendFee(rewardToken, rewardBalance);
			    IERC20(rewardToken).approve(address(sdGauge), netReward);
			    sdGauge.deposit_reward_token(rewardToken, netReward);
			    emit ClaimedAndNotified(address(sdGauge), rewardToken, netReward, rewardBalance - netReward);
            }
		}
    }

    /// @notice function to notify the reward passing any extra token added as reward
    /// @param _token token to notify 
	/// @param _amount amount to notify
    function notifyReward(address _token, uint256 _amount) external {
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        uint256 netReward = _sendFee(_token, _amount);
        IERC20(_token).approve(address(sdGauge), netReward);
		sdGauge.deposit_reward_token(_token, netReward);
        emit Notified(address(sdGauge), _token, netReward, _amount - netReward);
    }

	/// @notice internal function to send fees to recipients 
	/// @param _rewardToken reward token address
	/// @param _rewardBalance reward balance total amount
    function _sendFee(
		address _rewardToken,
		uint256 _rewardBalance
	) internal returns (uint256) {
		// calculate the amount for each fee recipient
        IFeeRegistryXChain feeRegistry = IFeeRegistryXChain(registry.getAddrIfNotZero(FEE_REGISTRY));
        uint256 baseFee = feeRegistry.BASE_FEE();
        uint256 accumulatorFee = feeRegistry.getFee(address(curveGauge), _rewardToken, IFeeRegistryXChain.MANAGEFEE.ACCUMULATORFEE);
        uint256 multisigFee = feeRegistry.getFee(address(curveGauge), _rewardToken, IFeeRegistryXChain.MANAGEFEE.PERFFEE);
        uint256 veSdtFee = feeRegistry.getFee(address(curveGauge), _rewardToken, IFeeRegistryXChain.MANAGEFEE.VESDTFEE);
        uint256 claimerFee = feeRegistry.getFee(address(curveGauge), _rewardToken, IFeeRegistryXChain.MANAGEFEE.CLAIMERREWARD);
        uint256 amountToNotify = _rewardBalance;
        if (accumulatorFee > 0) {
            uint256 accumulatorPart = (_rewardBalance * accumulatorFee) / baseFee;
            address accumulator = registry.getAddrIfNotZero(ACCUMULATOR);
			IERC20(_rewardToken).transfer(accumulator, accumulatorPart);
            amountToNotify -= accumulatorPart;
        }
		if (multisigFee > 0) {
            uint256 multisigPart = (_rewardBalance * multisigFee) / baseFee;
			address perfFeeRecipient = registry.getAddrIfNotZero(PERF_FEE_RECIPIENT);
			IERC20(_rewardToken).transfer(perfFeeRecipient, multisigPart);
            amountToNotify -= multisigPart;
		} 
		if (veSdtFee > 0) {
            uint256 veSDTPart = (_rewardBalance * veSdtFee) / baseFee;
			address veSDTFeeProxy = registry.getAddrIfNotZero(VE_SDT_FEE_PROXY);
			IERC20(_rewardToken).transfer(veSDTFeeProxy, veSDTPart);
            amountToNotify -= veSDTPart;
		}
		if (claimerFee > 0) {
            uint256 claimerPart = (_rewardBalance * claimerFee) / baseFee;
            IERC20(_rewardToken).transfer(msg.sender, claimerPart);
            amountToNotify -= claimerPart;
        }
		return amountToNotify;
	}  
}
