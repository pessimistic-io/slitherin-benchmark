// SPDX-License-Identifier: MIT
pragma solidity >0.7.6 <0.9.0;

import "./IERC20.sol";

interface IProtocolToken is IERC20 {
    function laIProtocolTokenstEmissionTime() external view returns (uint256);

    function claimMasterRewards(uint256 amount) external returns (uint256 effectiveAmount);

    function masterEmissionRate() external view returns (uint256);

    function burn(uint256 amount) external;
}

