// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import { ERC20 } from "./ERC20.sol";
import { SafeTransferLib } from "./SafeTransferLib.sol";
import { LinkTokenInterface } from "./LinkTokenInterface.sol";
import { IKeeperRegistrar } from "./IKeeperRegistrar.sol";
import { LimitOrderRegistry } from "./LimitOrderRegistry.sol";
import { TradeManager } from "./TradeManager.sol";
import { Clones } from "./Clones.sol";

/**
 * @title Trade Manager Factory
 * @notice Factory to deploy Trade Managers using Open Zeppelin Clones.
 * @author crispymangoes
 */
contract TradeManagerFactory {
    using SafeTransferLib for ERC20;
    using Clones for address;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ManagerCreated(address manager);

    /*//////////////////////////////////////////////////////////////
                              IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Trade Manager Implementation contract.
     */
    address public immutable implementation;

    constructor(address _implementation) {
        implementation = _implementation;
    }

    /*//////////////////////////////////////////////////////////////
                        MANAGER CREATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows caller to create a new trade manager for themselves.
     * @dev Requires caller has approved this contract to spend their LINK.
     */
    function createTradeManager(
        LimitOrderRegistry _limitOrderRegistry,
        LinkTokenInterface LINK,
        IKeeperRegistrar registrar,
        uint256 initialUpkeepFunds
    ) external returns (TradeManager manager) {
        address payable clone = payable(implementation.clone());
        if (initialUpkeepFunds > 0) {
            ERC20(address(LINK)).safeTransferFrom(msg.sender, address(this), initialUpkeepFunds);
            ERC20(address(LINK)).safeApprove(clone, initialUpkeepFunds);
        }
        manager = TradeManager(clone);
        manager.initialize(msg.sender, _limitOrderRegistry, LINK, registrar, initialUpkeepFunds);
        emit ManagerCreated(address(manager));
    }
}

