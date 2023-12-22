// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface IMintBurn {
    function burn(uint amount) external;
    function mint(address account, uint amount) external;
}
