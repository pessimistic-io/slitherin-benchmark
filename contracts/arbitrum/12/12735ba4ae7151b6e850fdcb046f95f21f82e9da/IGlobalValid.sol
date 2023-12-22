// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "./GlobalDataTypes.sol";

interface IGlobalValid {
    function BASIS_POINTS_DIVISOR() external view returns (uint256);

    function maxSizeLimit() external view returns (uint256);

    function maxNetSizeLimit() external view returns (uint256);

    function maxUserNetSizeLimit() external view returns (uint256);

    function maxMarketSizeLimit(address market) external view returns (uint256);

    function setMaxSizeLimit(uint256 limit) external;

    function setMaxNetSizeLimit(uint256 limit) external;

    function setMaxUserNetSizeLimit(uint256 limit) external;

    function setMaxMarketSizeLimit(address market, uint256 limit) external;

    function isIncreasePosition(
        GlobalDataTypes.ValidParams memory params
    ) external view returns (bool);

    function getMaxIncreasePositionSize(
        GlobalDataTypes.ValidParams memory params
    ) external view returns (uint256);
}

