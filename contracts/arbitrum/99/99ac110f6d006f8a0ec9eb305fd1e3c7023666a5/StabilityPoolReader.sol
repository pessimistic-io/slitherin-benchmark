pragma solidity ^0.8.10;

import { StabilityPool } from "./StabilityPool.sol";
import { CommunityIssuance } from "./CommunityIssuance.sol";

contract StabilityPoolReader {
	CommunityIssuance private communityIssuance;

	constructor(CommunityIssuance _communityIssuance) {
		communityIssuance = _communityIssuance;
	}

	function getPendingIssuanceRewards(StabilityPool _stabilityPool, address _user)
		external
		view
		returns (uint256)
	{
		uint256 initialDeposit = _stabilityPool.deposits(_user);
		if (initialDeposit == 0) return 0;

		(, uint256 snapP, uint256 snapG, uint128 snapScale, uint128 snapEpoch) = _stabilityPool
			.depositSnapshots(_user);

		uint128 systemCurrentEpoch = _stabilityPool.currentEpoch();
		uint128 systemCurrentScale = _stabilityPool.currentScale();

		if (systemCurrentEpoch != snapEpoch || systemCurrentScale - snapScale > 1) {
			return _stabilityPool.getDepositorVSTAGain(_user);
		}

		uint256 epochToScaleToG = _stabilityPool.epochToScaleToG(
			systemCurrentEpoch,
			systemCurrentScale
		);

		epochToScaleToG += _updateG(
			_stabilityPool,
			_estimateNextIssueVSTA(address(_stabilityPool))
		);

		bool isSystemAhead = systemCurrentScale > snapScale;
		uint256 firstPortion = isSystemAhead
			? _stabilityPool.epochToScaleToG(snapEpoch, snapScale)
			: epochToScaleToG;
		uint256 secondPortion = isSystemAhead
			? epochToScaleToG
			: _stabilityPool.epochToScaleToG(snapEpoch, snapScale + 1);

		return
			_getVSTAGainFromSnapshots(
				_stabilityPool,
				initialDeposit,
				firstPortion,
				secondPortion,
				snapG,
				snapP
			);
	}

	function _updateG(StabilityPool _stabilityPool, uint256 _VSTAIssuance)
		internal
		view
		returns (uint256)
	{
		uint256 totalVST = _stabilityPool.getTotalVSTDeposits();
		if (totalVST == 0 || _VSTAIssuance == 0) {
			return 0;
		}

		uint256 VSTANumerator = (_VSTAIssuance * _stabilityPool.DECIMAL_PRECISION()) +
			_stabilityPool.lastVSTAError();

		return VSTANumerator / totalVST;
	}

	function _getVSTAGainFromSnapshots(
		StabilityPool _stabilityPool,
		uint256 initialStake,
		uint256 _firstPosition,
		uint256 _secondPortion,
		uint256 G_Snapshot,
		uint256 P_Snapshot
	) internal view returns (uint256) {
		uint256 firstPortion = _firstPosition - G_Snapshot;
		uint256 secondPortion = _secondPortion / _stabilityPool.SCALE_FACTOR();

		uint256 VSTAGain = (initialStake * (firstPortion + secondPortion)) /
			(P_Snapshot) /
			(_stabilityPool.DECIMAL_PRECISION());

		return VSTAGain;
	}

	function _estimateNextIssueVSTA(address _pool) internal view returns (uint256) {
		(
			,
			uint256 totalRewardIssued,
			uint256 lastUpdateTime,
			uint256 totalRewardSupply,
			uint256 rewardDistributionPerMin
		) = communityIssuance.stabilityPoolRewards(_pool);

		uint256 maxPoolSupply = totalRewardSupply;
		uint256 totalIssued = totalRewardIssued;

		if (totalIssued >= maxPoolSupply) return 0;

		uint256 timePassed = (block.timestamp - lastUpdateTime) / (60);
		uint256 issuance = rewardDistributionPerMin * timePassed;

		uint256 totalIssuance = issuance + totalIssued;

		if (totalIssuance > maxPoolSupply) {
			issuance = maxPoolSupply - totalIssued;
			totalIssuance = maxPoolSupply;
		}

		return issuance;
	}
}

