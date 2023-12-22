// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

interface ILibraryBuilder {

    event NewLibraryCreated(address indexed libraryPoolAddress, address rewardToken, uint256 rewardsStartTime);

    event LibraryDeactivated(address indexed libraryPoolAddress, address rewardToken, uint256 timeStamp);

    function deployLibrary(address _rewardToken, uint256 _startTime) external;

    function deactivateLibrary(address _rewardToken) external;

    function addNewCoinBook(address _newCoinBook) external;

    function removeCoinBook(address _oldCoinBook) external;

    function setVestingContract(address _vesting, bool _flag) external;

    function depositExtraRewards(address _token, uint256 _amount) external;

    function handleTransfer(
        address _token, 
        address _staker, 
        address _library, 
        uint256 _amount
    ) external;

    function executeTransfer(
        address _account, 
        uint256 _amount, 
        address _oldPool, 
        address _newPool
    ) external;

    function stakeFromVesting(
        address _account, 
        uint256 _amount, 
        address _newPool
    ) external;

    function getLibraryPool(address _token) external view returns (bool libraryExists, address libraryAddress);

    function getLibraryPool(
        address _tokenA, 
        address _tokenB
    ) external view returns (
        bool libraryExistsA, 
        address libraryAddressA,
        bool libraryExistsB, 
        address libraryAddressB
    );

    function getAllActiveLibraries() external view returns (
        address[] memory libraryAddresses,
        address[] memory rewardTokens,
        uint256[] memory rewardStartTimes
    );

    function getAllInactiveLibraries() external view returns (
        address[] memory libraryAddresses,
        address[] memory rewardTokens
    );

    function getCoinBooks() external view returns (address[] memory activeCoinBooks);
}
