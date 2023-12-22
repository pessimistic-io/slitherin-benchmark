// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

import "./OwnableWithoutContextUpgradeable.sol";

import "./SimpleIERC20.sol";

import "./TreasuryDependencies.sol";
import "./TreasuryEventError.sol";

/**
 * @notice Treasury Contract
 *
 *         Treasury will receive 5% of the premium income (usdc) from policyCenter.
 *         They are counted as different pools.
 *
 *         When a reporter gives a correct report (passed voting and executed),
 *         he will get 10% of the income of that project pool.
 *
 */
contract Treasury is
    TreasuryEventError,
    OwnableWithoutContextUpgradeable,
    TreasuryDependencies
{
    // ---------------------------------------------------------------------------------------- //
    // ************************************* Constants **************************************** //
    // ---------------------------------------------------------------------------------------- //

    uint256 public constant REPORTER_REWARD = 1000; // 10%

    address public constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Variables **************************************** //
    // ---------------------------------------------------------------------------------------- //

    mapping(uint256 => uint256) public poolIncome;

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Constructor ************************************** //
    // ---------------------------------------------------------------------------------------- //

    function initialize(
        address _executor,
        address _policyCenter
    ) public initializer {
        __Ownable_init();

        executor = _executor;
        policyCenter = _policyCenter;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ Main Functions ************************************ //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Reward the correct reporter
     *
     *         Part of the priority pool income will be given to the reporter
     *         Only called from executor when executing a report
     *
     * @param _poolId   Pool id
     * @param _reporter Reporter address
     */
    function rewardReporter(uint256 _poolId, address _reporter) external {
        if (msg.sender != executor) revert Treasury__OnlyExecutor();

        uint256 amount = (poolIncome[_poolId] * REPORTER_REWARD) / 10000;

        poolIncome[_poolId] -= amount;
        SimpleIERC20(USDC).transfer(_reporter, amount);

        emit ReporterRewarded(_reporter, amount);
    }

    /**
     * @notice Record when receiving new premium income
     *
     *         Only called from policy center
     *
     * @param _poolId Pool id
     * @param _amount Premium amount (usdc)
     */
    function premiumIncome(uint256 _poolId, uint256 _amount) external {
        if (msg.sender != policyCenter) revert Treasury__OnlyPolicyCenter();

        poolIncome[_poolId] += _amount;

        emit NewIncomeToTreasury(_poolId, _amount);
    }

    /**
     * @notice Claim usdc by the owner
     *
     * @param _amount Amount to claim
     */
    function claim(uint256 _amount) external onlyOwner {
        SimpleIERC20(USDC).transfer(owner(), _amount);

        emit ClaimedByOwner(_amount);
    }
}

