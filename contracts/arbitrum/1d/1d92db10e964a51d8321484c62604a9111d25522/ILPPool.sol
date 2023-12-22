// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.9;
import "./DataTypes.sol";

interface ILPPool {
    function reservationWithdrawal(address lPAddress, uint256 purchaseHeightInfo) external returns (bool);

    function addLPAmountInfo(uint256 _amount, address _lPAddress) external returns (bool);

    function dealLPPendingInit(uint256 coefficient) external returns (bool);

    function deleteLPAmountInfoByParam(address lPAddress, uint256 purchaseHeightInfo) external returns (bool);

    function addHedgingAggregator(DataTypes.HedgingAggregatorInfo memory hedgingAggregator) external returns (bool);

    function deleteHedgingAggregator(uint256 _releaseHeight) external returns (bool);

    function getLPAmountInfo(address lPAddress) external view returns (DataTypes.LPAmountInfo[] memory);

    function getLPAmountInfoByParams(
        address lPAddress,
        uint256 purchaseHeightInfo
    ) external view returns (DataTypes.LPAmountInfo memory);

    function getProductHedgingAggregatorPool() external view returns (DataTypes.HedgingAggregatorInfo[] memory);
}

