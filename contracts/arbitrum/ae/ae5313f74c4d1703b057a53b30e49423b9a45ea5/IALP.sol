//SPDX-License-Identifier: Unlicense
pragma solidity = 0.8.17;

import "./IERC20.sol";

/// @notice Interface for ALP
interface IALP is IERC20 {
    function depositFee() external view returns (uint);

    function withdrawFee() external view returns (uint);

    function deposit(uint _amountUSDT) external;

    function withdraw(uint _amountALP) external;

    function depositorWhitelist(address) external view returns (bool);

    function getALPFromUSDT(uint _amountUSDT) external view returns (uint);

    function getUSDTFromALP(uint _amountALP) external view returns (uint);

    function open() external view returns (bool);
}

