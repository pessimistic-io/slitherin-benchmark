// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./IERC20.sol";

interface IDistToken is IERC20 {
    function token() external view returns (IERC20);
    function tokenAdd() external view returns (address);

    function addHandler(address) external;
    function removeHandler(address) external;
    function mint(address, uint256) external;
    function burn(uint256) external;
    function burnFrom(address, uint256) external;
}
