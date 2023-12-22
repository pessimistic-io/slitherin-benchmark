// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import "./BaseRebateHandler.sol";
import "./IHandle.sol";
import "./WeeklyRebateLimit.sol";
import "./Address.sol";

contract HlpSwapTradeRebateHandler is BaseRebateHandler, WeeklyRebateLimit {
    using Address for address;

    bytes32 public constant HLP_SWAP_ACTION = keccak256("HLP_SWAP_ACTION");
    bytes32 public constant HLP_TRADE_ACTION = keccak256("HLP_TRADE_ACTION");

    uint256 public baseRebateFraction = 0.3 * 1 ether;
    uint256 public userReferralRebateFraction = 0.05 * 1 ether;
    uint256 public referrerReferralRebateFraction = 0.15 * 1 ether;

    address public immutable handle;
    address public immutable fxUsd;

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
        uint256 _weeklyLimit,
        address _fxUsd
    )
        BaseRebateHandler(_rebatesContract, _referralContract, _forex)
        WeeklyRebateLimit(_weeklyLimit)
    {
        require(_handle.isContract(), "Handle not contract");
        require(_fxUsd.isContract(), "fxUSD not contract");
        handle = _handle;
        fxUsd = _fxUsd;
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
        (
            address account,
            uint256 feeUsd,
            bool isValidAction
        ) = _getValidAccountAndFeeUsd(action, params);

        // if not valid action, return early. This does not need to revert
        if (!isValidAction) return;

        (address referrer, bool isReferrerValid) = _getReferral(account);
        (
            uint256 rebateToUser,
            uint256 rebateToReferrer
        ) = _getRebateToUserAndReferrer(
                _getForexAmountFromUsd(feeUsd),
                isReferrerValid
            );

        if (_isRebateOverWeeklyLimit(rebateToUser + rebateToReferrer)) return;
        _increaseCumulativeWeeklyRebates(rebateToUser + rebateToReferrer);

        if (rebateToUser > 0) {
            rebatesContract.registerRebate(
                account,
                address(forex),
                rebateToUser,
                action
            );
        }

        if (rebateToReferrer > 0) {
            rebatesContract.registerRebate(
                referrer,
                address(forex),
                rebateToReferrer,
                action
            );
        }
    }

    /**
     * @dev returns the account, fee in USD with 18 decimals, and whether or not the action
     * is valid for this handler
     */
    function _getValidAccountAndFeeUsd(bytes32 action, bytes calldata params)
        private
        pure
        returns (
            address account,
            uint256 feeUsd,
            bool isValidAction
        )
    {
        if (action == HLP_SWAP_ACTION) {
            (feeUsd, account, , ) = abi.decode(
                params,
                (uint256, address, address, address)
            );
            // fee from swap has 18 decimals already
            return (account, feeUsd, true);
        }

        if (action == HLP_TRADE_ACTION) {
            // feeUsd has precision of 18
            (feeUsd, account, , , , ) = abi.decode(
                params,
                (uint256, address, address, address, bool, bool)
            );

            // convert from 30 decimals to 18 decimals
            feeUsd = feeUsd / 10**12;

            return (account, feeUsd, true);
        }

        // no action for this handler, so return without calculating rebates
        return (address(0), 0, false);
    }

    /// @dev calculates the rebate to the user and referrer in forex
    function _getRebateToUserAndReferrer(uint256 forex, bool isReferrerValid)
        private
        view
        returns (uint256 rebateToUser, uint256 rebateToReferrer)
    {
        (
            uint256 baseUserRebate,
            uint256 userReferralRebate,
            uint256 referrerReferralRebate
        ) = _divideForex(forex);
        rebateToUser = baseUserRebate;

        if (isReferrerValid) {
            rebateToUser += userReferralRebate;
            rebateToReferrer = referrerReferralRebate;
        }
    }

    /**
     * @param feeUsd the usd amount (18 decimals) for which to get the forex equivilant
     * @return forexAmount the forex amount equal to {feeUsd}
     */
    function _getForexAmountFromUsd(uint256 feeUsd)
        private
        view
        returns (uint256)
    {
        // FOREX / ETH
        uint256 forexEth = IHandle(handle).getTokenPrice(address(forex));
        // USD / ETH
        uint256 fxUsdEth = IHandle(handle).getTokenPrice(fxUsd);

        /**
         * forex amount to return = FEE * FOREX
         * = (FEE * 1 USD) * 1 FOREX / 1 USD
         * = (FEE * 1 USD) * (1 FOREX / 1 ETH) / (1 USD / 1 ETH)
         */
        return (feeUsd * forexEth) / fxUsdEth;
    }

    /**
     * @param forexAmount the forex to divide
     * @return baseUserRebate the base rebate to go to the user
     * @return userReferralRebate the rebate to go to the user if they have a valid referrer
     * @return referrerReferralRebate the rebate to go to the referrer if the refferer is valid
     */
    function _divideForex(uint256 forexAmount)
        private
        view
        returns (
            uint256 baseUserRebate,
            uint256 userReferralRebate,
            uint256 referrerReferralRebate
        )
    {
        baseUserRebate = (forexAmount * baseRebateFraction) / 1 ether;
        userReferralRebate =
            (forexAmount * userReferralRebateFraction) /
            1 ether;
        referrerReferralRebate =
            (forexAmount * referrerReferralRebateFraction) /
            1 ether;
    }
}

