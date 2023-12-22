// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.4;

import "./IERC20.sol";

interface IBeefy is IERC20 {
    function deposit(uint256) external;
    function depositAll() external;
    function withdraw(uint256) external;
    function withdrawAll() external;
    function getPricePerFullShare() external view returns (uint256);
    function upgradeStrat() external;
    function balance() external view returns (uint256);
    function want() external view returns (IERC20);    
}
