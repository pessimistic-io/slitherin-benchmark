

// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.8.15;

import "./Ownable.sol";
import "./Account.sol";
import "./GasStation.sol";
import "./IProtocolsManager.sol";
import "./Constant.sol";

contract AccountFactory is Ownable {

    IProtocolsManager public immutable protocolManager;
    IGasStation public immutable gasStation;

    uint private _index;
    mapping (address => address) private userAccountMap; // Map user's Main address to Account address

    event CreateNewAccount(address indexed main, address oneCT, address newAccount);

    constructor(IProtocolsManager manager) {
        protocolManager = manager;
        gasStation = new GasStation(msg.sender, address(this));
    }

    // Anyone can create a new account with their main wallet address.
    function createNewAccount(address oneCT) external {
        require(userAccountMap[msg.sender] == Constant.ZERO_ADDRESS, "Account exist");
        bytes32 salt = keccak256(abi.encodePacked(_index++, msg.sender, oneCT));
        address newAccount = address(new Account{salt: salt}(msg.sender, oneCT, protocolManager, gasStation));
        
        userAccountMap[msg.sender] = newAccount;
        gasStation.addUser(oneCT);

        emit CreateNewAccount(msg.sender, oneCT, newAccount);
    }

    function getAccountInfo(address main) external view returns (address account, address oneCT) {
        account = userAccountMap[main];
        if (account != Constant.ZERO_ADDRESS) {
            (, oneCT) = IAccount(account).query();
        }
    }
}



