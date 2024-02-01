pragma solidity ^0.5.17;

import "./IERC20.sol";

contract IDollar is IERC20 {
    function burn(uint256 amount) public;

    function burnFrom(address account, uint256 amount) public;

    function mint(address account, uint256 amount) public returns (bool);
}
