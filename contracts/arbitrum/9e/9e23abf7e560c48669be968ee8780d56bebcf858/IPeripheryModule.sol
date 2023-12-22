/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/core/LICENSE
*/
pragma solidity >=0.8.19;

/**
 * @title Module for setting allowed periphery address.
 */
interface IPeripheryModule {

    /**
     * @dev Sets the approved periphery address, which can pe address 0 
     * in case no periphery is allowed. Msg.sender must me the Proxy owner.
     */
    function setPeriphery(address _peripheryAddress) external;
}

