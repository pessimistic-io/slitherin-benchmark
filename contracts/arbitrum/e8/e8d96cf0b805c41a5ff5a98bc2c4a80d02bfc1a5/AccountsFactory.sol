// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Clones.sol";
import "./SafeMath.sol";
import "./IAccount.sol";
import "./IAccountsFactory.sol";
import "./Multicall.sol";
contract AccountsFactory is IAccountsFactory, Multicall {
    address public implementation;
    mapping(address => uint256) public users;
    event ACCOUNT(
        uint256 indexed userId,
        address indexed account,
        address indexed creator
    );

    constructor(address _implementation) {
        implementation = _implementation;
    }

    /**
     * create paxu.io deposit account
     * @param userId The users paxu Id
     */

    function createAccount(
        uint256 userId
    ) external override returns (address account) {
        account = Clones.cloneDeterministic(implementation, salt(userId));
        IAccount(account).initialize();
    }

    

    /**
     * create several paxu.io accounts
     * @param userIds Array of paxu userids
     */
    function createAccounts(uint256[] calldata userIds) external override {
        for (uint8 i = 0; i < userIds.length; i++) {
            address account = Clones.cloneDeterministic(
                implementation,
                salt(userIds[i])
            );
            IAccount(account).initialize();
        }
    }

    /**
     * predict paxu account
     * @param userId paxu userid
     */
    function predict(uint256 userId) external view override returns (address) {
        return Clones.predictDeterministicAddress(implementation, salt(userId));
    }

    /**
     * calculate userId Salt;
     * @param uid paxu userId
     */

    function salt(uint256 uid) public view override returns (bytes32 _salt) {
        _salt = keccak256(abi.encodePacked(implementation, uid));
    }

    
    
}

