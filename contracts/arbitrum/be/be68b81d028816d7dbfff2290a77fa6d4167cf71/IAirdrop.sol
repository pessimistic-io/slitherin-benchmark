// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAirdrop {

    /**
     * add no wled addresses to tmp. set
     * @param _address from or to address of _transfer(...)
     */
    function addToTmpSet(address _address) external;

    function setNewAirdrop(address _account, bool _value) external;


    // View function

    function isRegister(address _address) external view returns(bool);
}
