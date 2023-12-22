// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import "./IRebateHandler.sol";
import "./IReferral.sol";
import "./IRebates.sol";
import "./ERC20_IERC20.sol";
import "./Address.sol";

abstract contract BaseRebateHandler is IRebateHandler {
    using Address for address;

    /// @dev address of the referral manager contract
    IReferral public immutable referralContract;
    /// @dev address of forex, which is the reward sent to users
    IERC20 public immutable forex;
    /// @dev address of the Rebates contract
    IRebates public immutable rebatesContract;

    constructor(
        address _rebatesContract,
        address _referralContract,
        address _forex
    ) {
        require(_rebatesContract.isContract(), "Rebates not contract");
        require(_referralContract.isContract(), "Referral not contract");
        require(_forex.isContract(), "FOREX not contract");

        rebatesContract = IRebates(_rebatesContract);
        referralContract = IReferral(_referralContract);
        forex = IERC20(_forex);
    }

    /// @dev throws if the caller is not {rebatesContract}
    modifier onlyRebates() {
        require(
            msg.sender == address(rebatesContract),
            "BaseRebateHandler: Unauthorized caller"
        );
        _;
    }

    /**
     * @dev gets the referral for {user} and checks if the referral is valid
     * @param user the user to get the referral for
     * @return referrer the referrer of {user}
     * @return isReferrerEligible whether or not {referrer} is valid
     */
    function _getReferral(address user)
        internal
        view
        returns (address referrer, bool isReferrerEligible)
    {
        referrer = referralContract.getReferral(user);
        isReferrerEligible = referrer != address(0) && referrer != user;
    }
}

