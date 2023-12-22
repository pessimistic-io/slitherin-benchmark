// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./AccessControl.sol";
import "./BeaconProxy.sol";
import {EventBeacon} from "./EventBeacon.sol";
import {Event} from "./Event.sol";
import {Utils} from "./Utils.sol";

contract EventFactory is Utils {
    address[] public deployedEvents;
    address public manager;
    EventBeacon public beacon;

    constructor(address creator, address _initBlueprint) {
        manager = creator;
        beacon = new EventBeacon(_initBlueprint);
    }

    function createEvent(
        string[] calldata tickets,
        uint256[] calldata amounts,
        string memory _uri,
        uint256[] memory costs,
        // EventDetails calldata details
        string[] calldata details
    ) external {
        //deploys events and returns address
        BeaconProxy e = new BeaconProxy(
            address(beacon),
            abi.encodeWithSelector(
                Event(address(0)).initialize.selector,
                address(msg.sender),
                tickets,
                amounts,
                _uri,
                costs,
                details
            )
        );

        deployedEvents.push(address(e));
    }

    // Returns the first found token type if user has one.  -1 if no tickets.
    function hasTicket(address user, uint256 eventId)
        public
        view
        returns (int256)
    {
        require(
            user != address(0),
            "EventFactory: address zero is not a valid owner"
        );

        Event deployedEvent = Event(deployedEvents[eventId]);

        return deployedEvent.hasTicket(user);
    }

    function transferTicket(
        uint256 eventId,
        address to,
        uint256 token,
        uint256 amount
    ) public {
        Event deployedEvent = Event(deployedEvents[eventId]);

        deployedEvent.transferTicket(manager, to, token, amount);
    }

    function getDeployedEvents() public view returns (address[] memory) {
        return deployedEvents;
    }
}

