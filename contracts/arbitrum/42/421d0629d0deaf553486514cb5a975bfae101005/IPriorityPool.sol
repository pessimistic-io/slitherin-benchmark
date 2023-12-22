// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

interface IPriorityPool {
    //

    function lpTokenAddress(uint256 _generation)
        external
        view
        returns (address);

    function insuredToken() external view returns (address);

    function pausePriorityPool(bool _paused) external;

    function setCoverIndex(uint256 _newIndex) external;

    function minAssetRequirement() external view returns (uint256);

    function activeCovered() external view returns (uint256);

    function currentLPAddress() external view returns (address);

    function liquidatePool(uint256 amount) external;

    function generation() external view returns (uint256);

    function crTokenAddress(uint256 generation) external view returns (address);

    function poolInfo()
        external
        view
        returns (
            bool,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        );

    function updateWhenBuy(
        uint256 _amount,
        uint256 _premium,
        uint256 _length,
        uint256 _timestampLength
    ) external;

    function stakedLiquidity(uint256 _amount, address _provider)
        external
        returns (address);

    function unstakedLiquidity(
        address _lpToken,
        uint256 _amount,
        address _provider
    ) external;

    function coverPrice(uint256 _amount, uint256 _length)
        external
        view
        returns (uint256, uint256);

    function maxCapacity() external view returns (uint256);

    function coverIndex() external view returns (uint256);

    function paused() external view returns (bool);

    function basePremiumRatio() external view returns (uint256);

    function updateWhenClaimed(uint256 expiry, uint256 amount) external;
}

