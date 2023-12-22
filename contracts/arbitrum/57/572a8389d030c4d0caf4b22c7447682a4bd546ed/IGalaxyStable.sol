// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20Mintable.sol";

interface IGalaxyStable is IERC20Mintbale{
    function setDynamicFee(uint _dynamicFee) external;
    function setTheasuryAddress(address _address) external;
}


