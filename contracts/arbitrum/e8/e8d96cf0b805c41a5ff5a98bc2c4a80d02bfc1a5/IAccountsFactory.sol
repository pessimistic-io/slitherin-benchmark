// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
interface IAccountsFactory  {
   
    
    /**
     * create paxu.io deposit account
     * @param userId The users paxu Id
     */
    function createAccount(uint256 userId) external returns (address account) ;
    

    /**
     * create several paxu.io accounts
     * @param userIds Array of paxu userids
     */
    function createAccounts(
        uint256[] calldata userIds
    ) external;

    /**
     * predict paxu account
     * @param userId paxu userid
     */
    function predict(uint256 userId) external view returns (address) ;


    /**
     * calculate userId Salt;
     * @param uid paxu userId
     */

    function salt(uint256 uid) external view returns (bytes32 _salt);
}

