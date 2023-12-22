// SPDX-License-Identifier: MIT

pragma solidity >0.6.12;
pragma experimental ABIEncoderV2;

interface IPool {
    function collateralArbiTenBalance() external view returns (uint);

    function migrate(address _new_pool) external;

    function getCollateralPrice() external view returns (uint);

    function netSupplyMinted() external view returns (uint);

    function getCollateralToken() external view returns (address);
}

