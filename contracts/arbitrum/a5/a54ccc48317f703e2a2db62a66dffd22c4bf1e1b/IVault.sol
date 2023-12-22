/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/products/dated-irs/LICENSE
*/
pragma solidity >=0.8.19;

interface IVault {
    function getMinPrice(address _token) external view returns (uint256);
    function getMaxPrice(address _token) external view returns (uint256);
}
