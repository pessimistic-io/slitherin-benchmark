// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

/* Internal imports */
import { ZoneInterface } from "./ZoneInterface.sol";
import { AdvancedOrder, CriteriaResolver, OrderComponents } from "./ConsiderationStructs.sol";
import { SeaportInterface } from "./SeaportInterface.sol";
import { TwoStepOwnableUpgradeable } from "./TwoStepOwnableUpgradeable.sol";

/* External imports */
import { PausableUpgradeable } from "./PausableUpgradeable.sol";
import { Initializable } from "./Initializable.sol";

/**
 * @title  PausableZoneV1Upgradeable
 * @author Sam Goldman
 * @notice PausableZoneV1Upgradeable is a simple upgradeable zone implementation that approves
 *         every order by default. It allows the owner to pause and unpause all orders routed
 *         through this zone, as well as cancel individual orders. This contract sits behind an
 *         OpenZeppelin Transparent proxy. To learn about safely upgrading this contract, check
 *         out this guide: https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
 */
contract PausableZoneV1Upgradeable is
    Initializable,
    ZoneInterface,
    TwoStepOwnableUpgradeable,
    PausableUpgradeable
{
    /**
     * @notice Prevents this implementation contract from being initialized directly so that initialization
     *         most occur through the proxy. Further explanation:
     *         https://docs.openzeppelin.com/contracts/4.x/api/proxy#Initializable-_disableInitializers--
     *
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract. Note that the contract can only be initialized once, and
     *         it must be initialized immediately after being deployed. The initializer makes use
     *         of the pattern described here:
     *         https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#initializers
     */
    function initialize() public initializer {
        __TwoStepOwnable_init();
        __Pausable_init();
    }

    /**
     * @notice Check if a given order is currently valid. This is called by Seaport
     *         whenever extraData is not provided by the caller.
     *
     * @param orderHash The hash of the order.
     * @param caller    The caller in question.
     * @param offerer   The offerer in question.
     * @param zoneHash  The hash to provide upon calling the zone.
     *
     * @return A magic value indicating if the order is
     *         currently valid.
     */
    function isValidOrder(
        bytes32 orderHash,
        address caller,
        address offerer,
        bytes32 zoneHash
    )
        external
        view
        override
        whenNotPaused
        returns (bytes4)
    {
        // Return the selector of isValidOrder as the magic value.
        return ZoneInterface.isValidOrder.selector;
    }

    /**
     * @notice Check if a given order including extraData is currently valid. This is called
     *         by Seaport whenever any extraData is provided by the caller.
     *
     * @param orderHash         The hash of the order.
     * @param caller            The caller in question.
     * @param order             The order in question.
     * @param priorOrderHashes  The order hashes of each order supplied prior to
     *                          the current order as part of a "match" variety
     *                          of order fulfillment.
     * @param criteriaResolvers The criteria resolvers corresponding to
     *                          the order.
     *
     * @return A magic value indicating if the order is
     *         currently valid.
     */
    function isValidOrderIncludingExtraData(
        bytes32 orderHash,
        address caller,
        AdvancedOrder calldata order,
        bytes32[] calldata priorOrderHashes,
        CriteriaResolver[] calldata criteriaResolvers
    )
        external
        view
        override
        whenNotPaused
        returns (bytes4)
    {
        // Return the selector of isValidOrder as the magic value.
        return ZoneInterface.isValidOrder.selector;
    }

    /**
     * @notice Cancels an arbitrary number of orders. Only callable by the owner.
     *         Callers should ensure that the intended order was cancelled by
     *         calling `getOrderStatus` on the Seaport contract and confirming
     *         that `isCancelled` returns `true`.
     *
     * @param seaport  The Seaport address.
     * @param orderComponents   The orders to cancel.
     */
    function cancelOrders(
        SeaportInterface seaport,
        OrderComponents[] calldata orderComponents
    ) external onlyOwner {
        seaport.cancel(orderComponents);
    }

    /**
     * @notice Pauses all trading on the exchange in case of an emergency. Only callable
     *         by the owner of the exchange.
     */
    function pauseMarketplace() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses trading on the exchange. Only callable by the owner of the exchange.
     *         Note that this does not unpause orders that have been individually cancelled by
     *         the owner.
     */
    function unpauseMarketplace() external onlyOwner {
        _unpause();
    }
}

