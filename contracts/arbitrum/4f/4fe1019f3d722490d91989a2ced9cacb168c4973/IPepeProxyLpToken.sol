//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "./IERC20.sol";

interface IPepeProxyLpToken is IERC20 {
    function approveContract(address contract_) external;

    function revokeContract(address contract_) external;

    function mint(address _to, uint256 _amount) external;

    function burn(address _from, uint256 _amount) external;

    function retrieve(address _token) external;
}

