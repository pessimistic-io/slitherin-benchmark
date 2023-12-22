// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import "./IPriceOracle.sol";

abstract contract ISyntheX {

    function claimReward(
        address[] memory _rewardTokens,
        address holder,
        address[] memory _pools
    ) external virtual;

    function getRewardsAccrued(
        address[] memory _rewardTokens,
        address holder,
        address[] memory _pools
    ) external virtual returns (uint256[] memory);

    function distribute(uint256 _totalSupply)
        external 
        virtual;

    function distribute(
        address _account,
        uint256 _totalSupply,
        uint256 _balance
    ) external virtual;

    // ERC165
    function supportsInterface(bytes4 interfaceId)
        external
        virtual
        view
        returns (bool);

    event SetPoolRewardSpeed(
        address indexed rewardToken,
        address indexed pool,
        uint256 speed
    );
    event DistributedReward(
        address[] rewardTokens,
        address indexed pool,
        address _account,
        uint256[] accountDelta,
        uint256[] rewardIndex
    );

    function vault() external virtual view returns(address);

    function isL0Admin(address _account) external virtual view returns (bool);

    function isL1Admin(address _account) external virtual view returns (bool);

    function isL2Admin(address _account) external virtual view returns (bool);
}

