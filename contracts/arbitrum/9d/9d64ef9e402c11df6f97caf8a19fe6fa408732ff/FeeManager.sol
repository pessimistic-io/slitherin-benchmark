// SPDX-License-Identifier: BSD-3-Clause
// Copyright © 2023 TXA PTE. LTD.
pragma solidity 0.8.19;

import "./Math.sol";
import "./Id.sol";

abstract contract FeeManager {
    using IdLib for Id;

    struct TradingFees {
        uint256 makerFee;
        uint256 takerFee;
    }

    uint256 public constant BASE = 10;
    uint256 public constant DENOMINATOR = 10 ** BASE;
    uint256 public constant ONE_PERCENT_NUMERATOR = 10 ** (BASE - 2); // 1.00%
    uint256 public constant ONE_BPS_NUMERATOR = 10 ** (BASE - 4); // 0.01%

    uint256 public constant MAX_FEE_NUMERATOR = 5 * (10 ** (BASE - 3)); // 0.50%
    uint256 public constant MIN_FEE_NUMERATOR = ONE_BPS_NUMERATOR; // 0.01%

    uint256 proposalTime = type(uint256).max;
    TradingFees public currentFees = TradingFees(1 * ONE_BPS_NUMERATOR, 5 * ONE_BPS_NUMERATOR);
    TradingFees public proposedFees = currentFees;
    Id public feeSequenceId = ID_ZERO;
    mapping(Id => TradingFees) public feeHistory;
    // Amount of time that must pass before a proposed fee can be enacted.
    uint256 public constant FEE_TIMEOUT = 1 days;

    // Determines which percentage of trading fees go to the settlement layer.
    // Remaining goes to the participating interface.
    // uint256 public protocolFee = 50 * ONE_PERCENT_NUMERATOR;

    uint256 public settlementFeeNumerator = ONE_BPS_NUMERATOR * 10; // 0.1 %

    // Determines how much of settlement fee goes to the insurance fund.
    // Remaining goes to stakers
    uint256 public insuranceFundFee = 50 * ONE_PERCENT_NUMERATOR;

    // Given a settlement amount, returns the portions that go to the insurance fund and staker rewards
    function calculateSettlementFees(uint256 settlementAmount) external view returns(uint256 insuranceFee, uint256 stakerReward) {
        uint256 settlementFee = (settlementAmount * settlementFeeNumerator) / DENOMINATOR;
        insuranceFee = (settlementFee * insuranceFundFee) / DENOMINATOR;
        stakerReward = settlementFee - insuranceFee;
    }

    function calculateInsuranceFee(uint256 amount) external view returns(uint256) {
        return (amount * insuranceFundFee) / DENOMINATOR;
    }

    // How much of staking rewards go to the stable coin pool
    // Remaining goes to the protocol token pool
    uint256 public stablePoolPortion = ONE_BPS_NUMERATOR * 8696;

    function calculateStakingRewards(uint256 stakingReward) external view returns (uint256 stablePoolReward, uint256 protocolPoolReward) {
        stablePoolReward = (stakingReward * stablePoolPortion) / DENOMINATOR;
        protocolPoolReward = stakingReward - stablePoolReward;
    }

    event TradingFeesProposed(uint256 makerFee, uint256 takerFee);
    event TradingFeesUpdated(Id indexed feeSequenceId, uint256 makerFee, uint256 takerFee);

    constructor() {
        feeHistory[ID_ZERO] = currentFees;
        emit TradingFeesUpdated(ID_ZERO, currentFees.makerFee, currentFees.takerFee);
    }

    function proposeFees(uint256 _makerFee, uint256 _takerFee) external virtual;
    function updateFees() external virtual;

    modifier withinFeeLimits(uint256 _makerFee, uint256 _takerFee) {
        if (_takerFee > MAX_FEE_NUMERATOR || _makerFee > MAX_FEE_NUMERATOR) revert();
        if (_takerFee != 0 && _takerFee < MIN_FEE_NUMERATOR) revert();
        if (_makerFee != 0 && _makerFee < MIN_FEE_NUMERATOR) revert();
        _;
    }

    function _proposeFees(uint256 _makerFee, uint256 _takerFee) internal withinFeeLimits(_makerFee, _takerFee) {
        proposedFees = TradingFees(_makerFee, _takerFee);
        proposalTime = block.timestamp;
        emit TradingFeesProposed(_makerFee, _takerFee);
    }

    function _updateFees() internal {
        if (block.timestamp < proposalTime + FEE_TIMEOUT) revert();
        currentFees = proposedFees;
        feeSequenceId = feeSequenceId.increment();
        feeHistory[feeSequenceId] = proposedFees;
        proposalTime = type(uint256).max;
        emit TradingFeesUpdated(feeSequenceId, proposedFees.makerFee, proposedFees.takerFee);
    }
}

