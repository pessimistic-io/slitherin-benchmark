// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

interface IRates {
    // Functions
    function setHoldingFee(uint256 _newApy) external returns (bool);

    function setSafeCollateralRate(uint256 _newSafeRate) external returns (bool);

    function setKeeperRate(uint256 _newRate) external returns (bool);

    function setRedemptionFee(uint256 _newFee) external returns (bool);

    function setBadCollateralRate(uint256 _newBadRate) external returns (bool);

    function setTreasuryFee(uint256 _newfee) external returns (bool);

    function setExcessDistributionReward(uint256 _newRate) external returns (bool);

    function setTreasury(address _treasury) external returns (bool);
    
    function saveFees() external;

    function newHoldingFee() external view returns (uint256);

    function getBadCR() external view returns (uint256);

    function getSafeCR() external view returns (uint256);

    function getRFee() external view returns (uint256);

    function getKR() external view returns (uint256);

    function getHoldingFee() external view returns (uint256);

    function getTFee() external view returns (uint256);

    function getEDR() external view returns (uint256);

    function getTreasury() external view returns (address);

    function setAccumulatedFee(uint256 _fee) external;

    // Events
    event HoldingFeeChanged(uint256);
    event SafeCollateralRateChanged(uint256);
    event BadCollateralRateChanged(uint256);
    event KeeperRateChanged(uint256);
    event RedemptionFeeChanged(uint256);
    event TresuryFeeChanged(uint256);
    event ExcessDistributionRewardChanged(uint256);
}

