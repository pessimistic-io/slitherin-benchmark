// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./IAccessControl.sol";
import "./IERC20.sol";

interface IEUROs is IERC20, IAccessControl {
    function MINTER_ROLE() external returns (bytes32);
    function BURNER_ROLE() external returns (bytes32);
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}
