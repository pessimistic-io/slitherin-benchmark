// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import "./AirdropFlashClaimReceiver.sol";
import "./IUserFlashclaimRegistry.sol";
import "./Clones.sol";

contract UserFlashclaimRegistry is IUserFlashclaimRegistry {
    address public immutable pool;
    mapping(address => address) public userReceivers;

    address public immutable receiverImplementation;

    constructor(address pool_, address receiverImplementation_) {
        pool = pool_;
        receiverImplementation = receiverImplementation_;
    }

    /**
     * @notice create a default receiver contract for the user
     */
    function createReceiver() public virtual override {
        address caller = msg.sender;
        address receiverAddress = Clones.clone(receiverImplementation);

        AirdropFlashClaimReceiver(receiverAddress).initialize(msg.sender);

        userReceivers[caller] = receiverAddress;
    }

    /**
     * @notice get receiver contract address for the user
     * @param user The user address
     */
    function getUserReceivers(address user)
        external
        view
        virtual
        override
        returns (address)
    {
        return userReceivers[user];
    }
}

