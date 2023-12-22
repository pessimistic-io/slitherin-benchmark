// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./IERC20.sol";

interface IERC20X is IERC20 {
    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external;

    function flashFee(address token, uint256 amount) external view returns (uint256);

    function maxFlashLoan(address token) external view returns (uint256);
}
