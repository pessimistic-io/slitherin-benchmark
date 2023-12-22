// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPepeBet {
    function placeBet(
        address user,
        address asset,
        uint256 amount,
        uint256 openingPrice,
        uint256 runTime,
        bool isLong
    ) external;

    function settleBet(uint256 betID, uint256 closingPrice) external;

    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function pause() external;

    function unPause() external;

    function modifyFee(uint16 newFee) external;

    function modifyMinAndMaxBetAmount(uint256 _minAmount, uint256 _maxAmount) external;

    function modifyMinAndMaxBetRunTime(uint16 _minRunTime, uint16 _maxRunTime) external;

    function setLiquidityPool(address _liquidityPool) external;

    function updateOracle(address _oracle) external;

    function addNewAssets(address[] calldata newAssets) external;

    function unapproveAssets(address[] calldata assets) external;

    function modifyLeverage(uint16 newLeverage) external;

    function updateFeeTaker(address newFeeTaker) external;

    function liquidityPool() external returns (address);

    function feeTaker() external returns (address);

    function oracle() external returns (address);

    function betId() external returns (uint256);

    function minBetAmount() external returns (uint256);

    function maxBetAmount() external returns (uint256);

    function fee() external returns (uint16);

    function leverage() external returns (uint16);

    function minRunTime() external returns (uint16);

    function maxRunTime() external returns (uint16);
}

