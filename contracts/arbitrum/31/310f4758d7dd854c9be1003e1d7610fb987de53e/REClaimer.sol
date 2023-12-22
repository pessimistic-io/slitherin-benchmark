// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.19;

import "./IREClaimer.sol";
import "./IREYIELD.sol";
import "./UpgradeableBase.sol";

/**
    A convenience contract for users to be able to collect all the rewards
    from our ecosystem in a single transaction
 */
contract REClaimer is UpgradeableBase(3), IREClaimer
{
    bool public constant isREClaimer = true;

    function claim(ICurveGauge gauge, ISelfStakingERC20 token)
        public
    {
        gauge.claim_rewards(msg.sender);
        token.claimFor(msg.sender);
    }

    function multiClaim(ICurveGauge[] memory gauges, ISelfStakingERC20[] memory tokens)
        public
    {
        unchecked
        {
            for (uint256 x = gauges.length; x > 0;)
            {
                gauges[--x].claim_rewards(msg.sender);
            }
            for (uint256 x = tokens.length; x > 0;)
            {
                tokens[--x].claimFor(msg.sender);
            }
        }
    }

    function checkUpgradeBase(address newImplementation)
        internal
        override
        view
    {
        assert(IREClaimer(newImplementation).isREClaimer());
    }
}
