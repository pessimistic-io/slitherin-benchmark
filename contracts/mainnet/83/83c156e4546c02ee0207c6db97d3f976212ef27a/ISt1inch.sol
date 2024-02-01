// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;
pragma abicoder v1;

import "./IERC20.sol";
import "./IERC20Pods.sol";

interface ISt1inch is IERC20Pods {
    function oneInch() external view returns (IERC20);
    function emergencyExit() external view returns (bool);
    function depositFor(address account, uint256 amount) external;
}

