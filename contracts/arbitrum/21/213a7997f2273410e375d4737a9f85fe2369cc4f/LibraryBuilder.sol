// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { SafeERC20Upgradeable as SafeERC20, IERC20Upgradeable as IERC20 }      from "./SafeERC20Upgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { EnumerableSetUpgradeable as EnumerableSet }      from "./EnumerableSetUpgradeable.sol";
import { BookLibrary } from "./BookLibrary.sol";
import { ILibraryBuilder } from "./ILibraryBuilder.sol";
import { ILibrary } from "./ILibrary.sol";

contract LibraryBuilder is ILibraryBuilder, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private activeLibraryTokens;
    EnumerableSet.AddressSet private libraries;
    EnumerableSet.AddressSet private inactiveLibraries;
    mapping(address => address) private inactiveRewardTokens;
    mapping(address => address) private libraryPools;
    mapping(address => bool) private vestingContracts;

    address public book;
    uint256 public defaultPoolLimitPerUser;
    uint256 public defaultLockTime;
    address public admin;
    EnumerableSet.AddressSet private coinBooks;

    modifier onlyLibraries(address _oldPool) {
        require(libraries.contains(msg.sender) && msg.sender == _oldPool, "Caller not allowed");
        _;
    }

    modifier onlyVestingContracts() {
        require(vestingContracts[msg.sender], "Caller not allowed");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(uint256 _lock, address _admin, address _coinBook) external initializer {
        __Ownable_init();
        defaultPoolLimitPerUser = 0;
        defaultLockTime = _lock;
        admin = _admin;
        coinBooks.add(_coinBook);
    }

    function deployLibrary(
        address _rewardToken,
        uint256 _startTime
    ) external override onlyOwner {
        require(book != address(0), "Book token not set");
        require(!activeLibraryTokens.contains(_rewardToken), "Token already has library");
        require(IERC20(_rewardToken).totalSupply() >= 0, "Invalid reward token");

        bytes memory bytecode = type(BookLibrary).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(book, _rewardToken, block.timestamp));
        address libraryPoolAddress;

        assembly {
            libraryPoolAddress := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }

        BookLibrary(libraryPoolAddress).initialize(
            book,
            _rewardToken,
            _startTime,
            defaultPoolLimitPerUser,
            defaultLockTime,
            admin,
            coinBooks.values()
        );

        activeLibraryTokens.add(_rewardToken);
        libraryPools[_rewardToken] = libraryPoolAddress;
        libraries.add(libraryPoolAddress);

        emit NewLibraryCreated(libraryPoolAddress, _rewardToken, _startTime);
    }

    function updateDefaults(uint256 _userLimit, uint256 _lock, address _admin) external onlyOwner {
        defaultPoolLimitPerUser = _userLimit;
        defaultLockTime = _lock;
        admin = _admin;
    }

    function deactivateLibrary(address _rewardToken) external override onlyOwner {
        address _libraryAddress = libraryPools[_rewardToken];
        ILibrary(_libraryAddress).endRewards();
        activeLibraryTokens.remove(_rewardToken);
        delete libraryPools[_rewardToken];

        inactiveLibraries.add(_libraryAddress);
        inactiveRewardTokens[_libraryAddress] = _rewardToken;

        emit LibraryDeactivated(_libraryAddress, _rewardToken, block.timestamp);
    }

    function addNewCoinBook(address _newCoinBook) external override onlyOwner {
        require(!coinBooks.contains(_newCoinBook), "CoinBook already added");
        coinBooks.add(_newCoinBook);

        uint256 length = activeLibraryTokens.length();
        address _libraryAddress;
        for (uint i = 0; i < length; i++) {
            _libraryAddress = libraryPools[activeLibraryTokens.at(i)];
            ILibrary(_libraryAddress).editCoinBooks(_newCoinBook, true);
        }
    }

    function removeCoinBook(address _oldCoinBook) external override onlyOwner {
        coinBooks.remove(_oldCoinBook);

        uint256 length = activeLibraryTokens.length();
        address _libraryAddress;
        for (uint i = 0; i < length; i++) {
            _libraryAddress = libraryPools[activeLibraryTokens.at(i)];
            ILibrary(_libraryAddress).editCoinBooks(_oldCoinBook, false);
        }
    }

    function setBookToken(address _book) external onlyOwner {
        require(book == address(0), "Book Address already set");
        book = _book;
    }

    function setVestingContract(address _vesting, bool _flag) external override onlyOwner {
        vestingContracts[_vesting] = _flag;
    }

    function depositExtraRewards(address _token, uint256 _amount) external override onlyOwner {
        address _library = libraryPools[_token];
        IERC20(_token).safeTransferFrom(msg.sender, _library, _amount);
        BookLibrary(_library).depositReward(_amount);
    }

    function handleTransfer(
        address _token, 
        address _staker, 
        address _library, 
        uint256 _amount
    ) external override onlyLibraries(msg.sender) {
        require(msg.sender == _library, "Caller not correct library");
        IERC20(_token).safeTransferFrom(_staker, _library, _amount);
    }

    function executeTransfer(
        address _account, 
        uint256 _amount, 
        address _oldPool, 
        address _newPool
    ) external override onlyLibraries(_oldPool) {
        ILibrary(_newPool).receiveTransfer(_account, _amount, _oldPool, false);
    }

    function stakeFromVesting(
        address _account, 
        uint256 _amount, 
        address _newPool
    ) external override onlyVestingContracts {
        ILibrary(_newPool).receiveTransfer(_account, _amount, msg.sender, true);
    }

    function getLibraryPool(address _token) external view override returns (bool libraryExists, address libraryAddress) {
        if (activeLibraryTokens.contains(_token)) {
            libraryExists = true;
            libraryAddress = libraryPools[_token];
        } else {
            return (false, address(0));
        }
    }

    function getLibraryPool(
        address _tokenA, 
        address _tokenB
    ) external view override returns (
        bool libraryExistsA, 
        address libraryAddressA,
        bool libraryExistsB, 
        address libraryAddressB
    ) {
        if (activeLibraryTokens.contains(_tokenA)) {
            libraryExistsA = true;
            libraryAddressA = libraryPools[_tokenA];
        } else {
            libraryExistsA = false;
            libraryAddressA = address(0);
        }
        if (activeLibraryTokens.contains(_tokenB)) {
            libraryExistsB = true;
            libraryAddressB = libraryPools[_tokenB];
        } else {
            libraryExistsB = false;
            libraryAddressB = address(0);
        }
    }

    function getAllActiveLibraries() external view override returns (
        address[] memory libraryAddresses,
        address[] memory rewardTokens,
        uint256[] memory rewardStartTimes
    ) {
        uint256 length = activeLibraryTokens.length();
        libraryAddresses = new address[](length);
        rewardTokens = activeLibraryTokens.values();
        rewardStartTimes = new uint256[](length); 
        for (uint i = 0; i < length; i++) {
            address _libraryAddress = libraryPools[rewardTokens[i]];
            libraryAddresses[i] = _libraryAddress;
            rewardStartTimes[i] = BookLibrary(_libraryAddress).startTime();
        }
    }

    function getAllInactiveLibraries() external view override returns (
        address[] memory libraryAddresses,
        address[] memory rewardTokens
    ) {
        uint256 length = inactiveLibraries.length();
        libraryAddresses = inactiveLibraries.values();
        rewardTokens = new address[](length);
        for (uint i = 0; i < length; i++) {
            rewardTokens[i] = inactiveRewardTokens[libraryAddresses[i]];
        }
    }

    function getCoinBooks() external view override returns (address[] memory activeCoinBooks) {
        return coinBooks.values();
    }
}
