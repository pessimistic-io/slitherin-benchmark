// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IGMXVault {

    function validateLiquidation(address _account, address _collateralToken, address _indexToken, bool _isLong, bool _raise) external view returns (uint256, uint256);

    function getPositionKey(address _account, address _collateralToken, address _indexToken, bool _isLong) external pure returns (bytes32);

    // returns:
    // 0: position.size
    // 1: position.collateral
    // 2: position.averagePrice
    // 3: position.entryFundingRate
    // 4: position.reserveAmount
    // 5: realisedPnl
    // 6: position.realisedPnl >= 0
    // 7: position.lastIncreasedTime
    function getPosition(address _account, address _collateralToken, address _indexToken, bool _isLong) external view returns (uint256, uint256, uint256, uint256, uint256, uint256, bool, uint256);
}
