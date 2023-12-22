// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import "./BaseRebateHandler.sol";
import "./IHandle.sol";
import "./WeeklyRebateLimit.sol";
import "./Address.sol";

contract HpsmRebateHandler is BaseRebateHandler, WeeklyRebateLimit {
    using Address for address;

    bytes32 public constant PSM_DEPOSIT = keccak256("PSM_DEPOSIT");

    uint256 public baseRebateFraction = 0.3 * 1 ether;
    uint256 public userReferralRebateFraction = 0.05 * 1 ether;
    uint256 public referrerReferralRebateFraction = 0.15 * 1 ether;

    address public immutable handle;

    event UpdateRebateFractions(
        uint256 baseRebateFraction,
        uint256 userReferralRebateFraction,
        uint256 referrerReferralRebateFraction
    );

    constructor(
        address _rebatesContract,
        address _referralContract,
        address _forex,
        address _handle,
        uint256 _weeklyLimit
    )
        BaseRebateHandler(_rebatesContract, _referralContract, _forex)
        WeeklyRebateLimit(_weeklyLimit)
    {
        require(_handle.isContract(), "Handle not contract");
        handle = _handle;
    }

    /**
     * @dev sets the rebate distribution fractions, where 100% = 1 ether
     * Note these values may, individually or combined, exceed 100%
     */
    function setRebateDistribution(
        uint256 _baseRebateFraction,
        uint256 _userReferralRebateFraction,
        uint256 _referrerReferralRebateFraction
    ) external onlyOwner {
        baseRebateFraction = _baseRebateFraction;
        userReferralRebateFraction = _userReferralRebateFraction;
        referrerReferralRebateFraction = _referrerReferralRebateFraction;

        emit UpdateRebateFractions(
            _baseRebateFraction,
            _userReferralRebateFraction,
            _referrerReferralRebateFraction
        );
    }

    /// @dev see {IRebateHandler-executeRebates}
    function executeRebates(bytes32 action, bytes calldata params)
        external
        override
        onlyRebates
    {
        if (action != PSM_DEPOSIT) return;

        (uint256 feeInEth, address user) = abi.decode(
            params,
            (uint256, address)
        );
        uint256 forexInEth = IHandle(handle).getTokenPrice(address(forex));

        uint256 forexAmount = (feeInEth * 1 ether) / forexInEth;
        (address referrer, bool isReferrerEligible) = _getReferral(user);

        uint256 amountToUser = (forexAmount * baseRebateFraction) / 1 ether;
        uint256 amountToRebater;

        if (isReferrerEligible) {
            amountToUser +=
                (forexAmount * userReferralRebateFraction) /
                1 ether;
            amountToRebater +=
                (forexAmount * referrerReferralRebateFraction) /
                1 ether;
        }

        if (_isRebateOverWeeklyLimit(amountToRebater + amountToUser)) return;
        _increaseCumulativeWeeklyRebates(amountToRebater + amountToUser);

        if (amountToUser > 0) {
            rebatesContract.registerRebate(
                user,
                address(forex),
                amountToUser,
                action
            );
        }

        if (amountToRebater > 0) {
            rebatesContract.registerRebate(
                referrer,
                address(forex),
                amountToRebater,
                action
            );
        }
    }
}

