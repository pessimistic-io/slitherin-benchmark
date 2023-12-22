// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";

contract Arbipad is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    string public poolName;
    uint256 public poolMaxCap;
    uint256 public saleStartTime;
    uint256 public saleEndTime;
    uint256 public noOfTiers;
    uint256 public totalParticipants;
    uint256 public totalRaisedFundInAllTier;
    address payable public projectOwner;
    address public tokenAddress;
    IERC20 private _ERC20Interface;

    bool public isPublicPool;

    /**
     *  @dev Struct to store Tier's metadata
     */
    struct Tier {
        uint256 maxCap;
        uint256 minAllocation;
        uint256 maxAllocation;
        uint256 totalUsers;
        uint256 totalFundRaised;
    }
    mapping(uint256 => Tier) private _tierInfo;

    /**
     *  @dev Struct to store User's data
     */
    struct User {
        uint256 tier;
        uint256 totalAllocation;
    }
    mapping(address => User) private _userInfo;

    event FundPool(uint256 indexed timestamp, address indexed initiator, uint256 value);

    constructor(
        address poolOwner,
        string memory _poolName,
        uint256 _poolMaxCap,
        uint256 _saleStartTime,
        uint256 _saleEndTime,
        uint256 _noOfTiers,
        uint256 _totalParticipants,
        address payable _projectOwner,
        address _tokenAddress
    ) {
        transferOwnership(poolOwner);

        poolName = _poolName;
        require(_poolMaxCap > 0, "Zero max cap");
        poolMaxCap = _poolMaxCap;

        require(_saleStartTime > block.timestamp && _saleEndTime > _saleStartTime, "Invalid timings");
        saleStartTime = _saleStartTime;
        saleEndTime = _saleEndTime;

        noOfTiers = _noOfTiers;
        if (_noOfTiers == 0) {
            isPublicPool = true;
        }

        require(_totalParticipants > 0, "Zero users");
        totalParticipants = _totalParticipants;

        require(_projectOwner != address(0), "Zero project owner address");
        projectOwner = _projectOwner;

        require(_tokenAddress != address(0), "Zero token address");
        tokenAddress = _tokenAddress;
        _ERC20Interface = IERC20(_tokenAddress);
    }

    /**
     *  @dev to update single tier's metadata
     */
    function updateTier(
        uint256 _tier,
        uint256 _maxCap,
        uint256 _minAllocation,
        uint256 _maxAllocation,
        uint256 _totalUsers
    ) public onlyOwner {
        require(_tier <= noOfTiers, "Invalid tier number");
        require(_maxCap > 0, "Invalid max tier cap amount");
        require(_maxAllocation > 0, "Invalid max user cap amount");
        require(_totalUsers > 0, "Zero users in tier");
        _tierInfo[_tier].maxCap = _maxCap;
        _tierInfo[_tier].minAllocation = _minAllocation;
        _tierInfo[_tier].maxAllocation = _maxAllocation;
        _tierInfo[_tier].totalUsers = _totalUsers;
    }

    /**
     *  @dev to update multiple tier's metadata
     */
    function updateTiers(
        uint256[] memory _tier,
        uint256[] memory _maxCap,
        uint256[] memory _minAllocation,
        uint256[] memory _maxAllocation,
        uint256[] memory _totalUsers
    ) external onlyOwner {
        require(
            _tier.length == _maxCap.length &&
                _maxCap.length == _minAllocation.length &&
                _minAllocation.length == _maxAllocation.length &&
                _maxAllocation.length == _totalUsers.length,
            "Lengths mismatch"
        );

        for (uint256 i = 0; i < _tier.length; i++) {
            updateTier(_tier[i], _maxCap[i], _minAllocation[i], _maxAllocation[i], _totalUsers[i]);
        }
    }

    /**
     *  @dev to Update pool metadata
     */
    function updatePool(
        uint256 _poolMaxCap,
        uint256 _saleStartTime,
        uint256 _saleEndTime,
        uint256 _noOfTiers,
        address payable _projectOwner
    ) external onlyOwner {
        poolMaxCap = _poolMaxCap;
        saleStartTime = _saleStartTime;
        saleEndTime = _saleEndTime;
        noOfTiers = _noOfTiers;
        projectOwner = _projectOwner;
    }

    /**
     *  @dev Setter for public pool status
     */
    function updatePublicPoolStatus(bool _isPublicPool) external onlyOwner {
        isPublicPool = _isPublicPool;
    }

    /**
     *  @dev Add User whitelist by tier
     */
    function updateUsersWhitelist(address[] memory _users, uint256[] memory _tiers) external onlyOwner {
        require(_users.length == _tiers.length, "Array length mismatch");
        for (uint256 i = 0; i < _users.length; i++) {
            require(_tiers[i] > 0 && _tiers[i] <= noOfTiers, "Invalid tier");
            _userInfo[_users[i]].tier = _tiers[i];
        }
    }

    /**
     *  @dev Fund the pool!
     */
    function buyTokens(uint256 amount) external {
        require(block.timestamp >= saleStartTime, "Sale not started yet");
        require(block.timestamp <= saleEndTime, "Sale ended");
        require(totalRaisedFundInAllTier.add(amount) <= poolMaxCap, "Exceeds pool max cap");

        uint256 userTier;
        if (!isPublicPool) {
            userTier = _userInfo[msg.sender].tier;
            require(userTier != 0, "Not whitelisted");
        }
        uint256 expectedAmount = _userInfo[msg.sender].totalAllocation.add(amount);
        require(expectedAmount >= _tierInfo[userTier].minAllocation, "Amount less than user min allocation");
        require(expectedAmount <= _tierInfo[userTier].maxAllocation, "Amount greater than user max allocation");
        require(_tierInfo[userTier].totalFundRaised + amount <= _tierInfo[userTier].maxCap, "Exceeds tier max cap");

        _tierInfo[userTier].totalFundRaised += amount;

        totalRaisedFundInAllTier = totalRaisedFundInAllTier.add(amount);
        _userInfo[msg.sender].totalAllocation += amount;
        _ERC20Interface.safeTransferFrom(msg.sender, projectOwner, amount);

        emit FundPool(block.timestamp, msg.sender, amount);
    }

    /**
     * @dev Return the User Max Allocation left
     * @return Max Allocation Left
     */
    function userMaxAllocationLeft(address user) external view returns (uint256) {
        User memory _user = userInfo(user);
        uint256 _tier = _user.tier;

        if (_user.totalAllocation >= _tierInfo[_tier].maxAllocation) {
            return 0;
        } else {
            uint256 maxAllocationLeft = _tierInfo[_tier].maxAllocation - _user.totalAllocation;
            if (maxAllocationLeft <= _tierInfo[_tier].maxCap - _tierInfo[_tier].totalFundRaised) {
                return maxAllocationLeft;
            } else {
                return _tierInfo[_tier].maxCap - _tierInfo[_tier].totalFundRaised;
            }
        }
    }

    /**
     * @dev Return the Current Tier State
     * @return Tier Info
     */
    function currentTierState(uint256 _tier) external view returns (Tier memory) {
        return _tierInfo[_tier];
    }

    /**
     * @dev Return the User Info
     * @return User Info
     */
    function userInfo(address _user) public view returns (User memory) {
        User memory _tempUserInfo = _userInfo[_user];
        if (isPublicPool) {
            _tempUserInfo.tier = 0;
            return _tempUserInfo;
        } else {
            return _tempUserInfo;
        }
    }
}

