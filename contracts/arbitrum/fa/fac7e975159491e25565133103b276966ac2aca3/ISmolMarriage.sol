// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./ICreatureOwnerResolverRegistry.sol";

/**
 * @title  ISmolMarriage interface
 * @author Archethect
 * @notice This interface contains all functionalities for marrying Smols.
 */
interface ISmolMarriage {
    event Married(
        ICreatureOwnerResolverRegistry.Creature creature1,
        ICreatureOwnerResolverRegistry.Creature creature2,
        uint256 ring1,
        uint256 ring2,
        uint256 timestamp
    );
    event Divorced(
        ICreatureOwnerResolverRegistry.Creature creature1,
        ICreatureOwnerResolverRegistry.Creature creature2
    );
    event CancelDivorceRequest(
        ICreatureOwnerResolverRegistry.Creature creature1,
        ICreatureOwnerResolverRegistry.Creature creature2
    );
    event DivorceRequest(
        ICreatureOwnerResolverRegistry.Creature creature1,
        ICreatureOwnerResolverRegistry.Creature creature2
    );
    event CancelMarriageRequest(
        ICreatureOwnerResolverRegistry.Creature creature1,
        ICreatureOwnerResolverRegistry.Creature creature2
    );
    event RequestMarriage(
        ICreatureOwnerResolverRegistry.Creature creature1,
        ICreatureOwnerResolverRegistry.Creature creature2,
        uint256 ring1,
        uint256 ring2
    );
    event RedeemedDivorcedRing(ICreatureOwnerResolverRegistry.Creature creature, uint256 ring, uint256 penaltyFee);

    struct Marriage {
        bool valid;
        ICreatureOwnerResolverRegistry.Creature creature1;
        ICreatureOwnerResolverRegistry.Creature creature2;
        uint256 ring1;
        uint256 ring2;
        uint256 marriageTimestamp;
    }

    struct RequestedMarriage {
        bool valid;
        ICreatureOwnerResolverRegistry.Creature partner;
        uint256 ring;
        uint256 partnerRing;
    }

    struct RequestedDivorce {
        bool valid;
        ICreatureOwnerResolverRegistry.Creature partner;
    }

    struct RedeemableDivorce {
        bool valid;
        uint256 ring;
        uint256 penaltyFee;
    }

    function requestMarriage(
        ICreatureOwnerResolverRegistry.Creature memory creature1,
        ICreatureOwnerResolverRegistry.Creature memory creature2,
        uint256 ring1,
        uint256 ring2
    ) external;

    function cancelMarriageRequest(
        ICreatureOwnerResolverRegistry.Creature memory creature1,
        ICreatureOwnerResolverRegistry.Creature memory creature2
    ) external;

    function requestDivorce(ICreatureOwnerResolverRegistry.Creature memory creature) external;

    function cancelDivorceRequest(
        ICreatureOwnerResolverRegistry.Creature memory creature1,
        ICreatureOwnerResolverRegistry.Creature memory creature2
    ) external;

    function marry(
        ICreatureOwnerResolverRegistry.Creature memory creature1,
        ICreatureOwnerResolverRegistry.Creature memory creature2,
        uint256 ring1,
        uint256 ring2,
        address partner
    ) external;

    function divorce(
        ICreatureOwnerResolverRegistry.Creature memory creature1,
        ICreatureOwnerResolverRegistry.Creature memory creature2
    ) external;

    function redeemDivorcedRings(ICreatureOwnerResolverRegistry.Creature memory creature) external;

    function setDivorcePenaltyFee(uint256 divorcePenaltyFee_) external;

    function setDivorceCoolOff(uint256 divorceCoolOff_) external;

    function areMarried(
        ICreatureOwnerResolverRegistry.Creature memory creature1,
        ICreatureOwnerResolverRegistry.Creature memory creature2
    ) external view returns (bool);

    function isMarried(ICreatureOwnerResolverRegistry.Creature memory creature) external view returns (bool);

    function getMarriage(ICreatureOwnerResolverRegistry.Creature memory creature)
        external
        view
        returns (Marriage memory);

    function hasMarriageRequest(ICreatureOwnerResolverRegistry.Creature memory creature) external view returns (bool);

    function getPendingMarriageRequests(ICreatureOwnerResolverRegistry.Creature memory creature)
        external
        view
        returns (ICreatureOwnerResolverRegistry.Creature[] memory);

    function getRedeemableDivorces(ICreatureOwnerResolverRegistry.Creature memory creature)
        external
        view
        returns (RedeemableDivorce[] memory);

    function hasPendingMarriageRequests(ICreatureOwnerResolverRegistry.Creature memory creature)
        external
        view
        returns (bool);

    function hasDivorceRequest(ICreatureOwnerResolverRegistry.Creature memory creature) external view returns (bool);

    function hasPendingDivorceRequest(ICreatureOwnerResolverRegistry.Creature memory creature)
        external
        view
        returns (bool);

    function getPendingDivorceRequest(ICreatureOwnerResolverRegistry.Creature memory creature)
        external
        view
        returns (ICreatureOwnerResolverRegistry.Creature memory);

    function getMarriageProposerAddressForCreature(ICreatureOwnerResolverRegistry.Creature memory creature)
        external
        view
        returns (address);

    function setMarriageEnabled(bool status) external;
}

