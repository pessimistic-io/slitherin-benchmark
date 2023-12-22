// SPDX-License-Identifier: BSL 1.1

pragma solidity ^0.8.17;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./IAddressProvider.sol";

/**
 * @dev Contract module that manages access from non EOA accounts (other contracts)
 *
 * Inheriting from `BlockNonEOAUpgradeable` will make the {onlyEOA} modifier
 * available, which can be applied to functions to make sure that only whitelisted
 * contracts or EOAs can call them if contract calls are disabled.
 */
abstract contract BlockNonEOAUpgradeable is Initializable {
    
    IAddressProvider public addressProvider;

    bool public allowContractCalls;

    mapping (address=>bool) public whitelistedUsers;

    function __BlockNonEOAUpgradeable_init(address _provider) internal onlyInitializing {
        addressProvider = IAddressProvider(_provider);
    }

    function _checkEOA() private view {
        if (!allowContractCalls && !whitelistedUsers[msg.sender]) {
            require(msg.sender == tx.origin, "E35");
        }
    }

    /**
     * @notice If contract calls are disabled, block non whitelisted contracts
     */
    modifier onlyEOA() {
        _checkEOA();
        _;
    }

    /**
     * @notice Set whether other contracts can call onlyEOA functions
     */
    function setAllowContractCalls(bool _allowContractCalls) public {
        require(msg.sender==addressProvider.governance(), "Unauthorized");
        allowContractCalls = _allowContractCalls;
    }

    /**
     * @notice Whitelist or remove whitelist access for nonEOAs for accessing onlyEOA functions
     */
    function setWhitelistUsers(address[] memory users, bool[] memory allowed) public {
        require(msg.sender==addressProvider.governance(), "Unauthorized");
        for (uint i = 0; i<users.length; i++) {
            whitelistedUsers[users[i]] = allowed[i];
        }
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}
