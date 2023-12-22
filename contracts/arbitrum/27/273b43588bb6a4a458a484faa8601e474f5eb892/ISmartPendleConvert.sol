// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ISmartPendleConvert {
    
    function smartConvert(uint256 _amountIn, uint256 _mode) external returns (uint256);

    function depositFor(uint256 _amount, address _for) external;

}

