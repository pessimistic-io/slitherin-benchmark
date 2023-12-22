// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC20.sol";

interface IRETH is IERC20 {
    function burn(uint256 _rethAmount) external;
    function depositExcess() external payable;
    function depositExcessCollateral() external;
    function getEthValue(uint256 _rethAmount) external view returns (uint256);
    function getRethValue(uint256 _ethAmount) external view returns (uint256);
    function getExchangeRate() external view returns (uint256);
    function getTotalCollateral() external view returns (uint256);
    function getCollateralRate() external view returns (uint256);
    function mint(uint256 _ethAmount, address _to) external;
}

