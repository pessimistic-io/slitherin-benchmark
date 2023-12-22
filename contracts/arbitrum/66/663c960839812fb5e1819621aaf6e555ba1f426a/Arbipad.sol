// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";

contract Arbipad is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    string public name;
    uint256 public poolMaxCap;
    uint256 public saleStartTime;
    uint256 public saleEndTime;
    uint256 public noOfTiers;
    uint256 public totalParticipants;
    uint256 public totalRaisedFundInAllTier;
    address payable public projectOwner;
    address public tokenAddress;
    IERC20 public ERC20Interface;

    /**
     *  @dev Struct to store Tier's metadata
     */
    struct Tier {
        uint256 maxCap;
        uint256 totalFundRaised;
        uint256 totalUsers;
        uint256 minAllocation;
        uint256 maxAllocation;
    }
    mapping(uint256 => Tier) public tierInfo;

    /**
     *  @dev Struct to store User's data
     */
    struct User {
        uint256 tier;
        uint256 totalAllocation;
    }
    mapping(address => User) public userInfo;

    event FundPool(uint256 indexed timestamp, address indexed initiator, uint256 value);

    constructor(
        address poolOwner,
        string memory _name,
        uint256 _poolMaxCap,
        uint256 _saleStartTime,
        uint256 _saleEndTime,
        uint256 _noOfTiers,
        uint256 _totalParticipants,
        address payable _projectOwner,
        address _tokenAddress
    ) {
        transferOwnership(poolOwner);

        name = _name;
        require(_poolMaxCap > 0, "Zero max cap");
        poolMaxCap = _poolMaxCap;

        require(_saleStartTime > block.timestamp && _saleEndTime > _saleStartTime, "Invalid timings");
        saleStartTime = _saleStartTime;
        saleEndTime = _saleEndTime;

        require(_noOfTiers > 0, "Zero tiers");
        noOfTiers = _noOfTiers;

        require(_totalParticipants > 0, "Zero users");
        totalParticipants = _totalParticipants;

        require(_projectOwner != address(0), "Zero project owner address");
        projectOwner = _projectOwner;

        require(_tokenAddress != address(0), "Zero token address");
        tokenAddress = _tokenAddress;
        ERC20Interface = IERC20(tokenAddress);
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
        require(_tier > 0 && _tier <= noOfTiers, "Invalid tier number");
        require(_maxCap > 0, "Invalid max tier cap amount");
        require(_maxAllocation > 0, "Invalid max user cap amount");
        require(_totalUsers > 0, "Zero users in tier");
        tierInfo[_tier].maxCap = _maxCap;
        tierInfo[_tier].minAllocation = _minAllocation;
        tierInfo[_tier].maxAllocation = _maxAllocation;
        tierInfo[_tier].totalUsers = _totalUsers;
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
    ) public onlyOwner {
        require(
            _tier.length == _maxCap.length &&
                _maxCap.length == _minAllocation.length &&
                _minAllocation.length == _maxAllocation.length &&
                _maxAllocation.length == _totalUsers.length,
            "Lengths mismatch"
        );

        for (uint256 i = 0; i < _tier.length; i++) {
            require(_tier[i] > 0 && _tier[i] <= noOfTiers, "Invalid tier number");
            require(_maxCap[i] > 0, "Invalid max tier cap amount");
            require(_maxAllocation[i] > 0, "Invalid max user cap amount");
            require(_totalUsers[i] > 0, "Zero users in tier");

            updateTier(_tier[i], _maxCap[i], _minAllocation[i], _maxAllocation[i], _totalUsers[i]);
        }
    }

    /**
     *  @dev Add User whitelist by tier
     */
    function updateUsersWhitelist(address[] memory _users, uint256[] memory _tiers) external onlyOwner {
        require(_users.length == _tiers.length, "Array length mismatch");
        for (uint256 i = 0; i < _users.length; i++) {
            require(_tiers[i] > 0 && _tiers[i] <= noOfTiers, "Invalid tier");
            userInfo[_users[i]].tier = _tiers[i];
        }
    }

    /**
     *  @dev Prevent under value in allowance
     */
    modifier _hasAllowance(address allower, uint256 amount) {
        uint256 ourAllowance = ERC20Interface.allowance(allower, address(this));
        require(amount <= ourAllowance, "Make sure to add enough allowance");
        _;
    }

    /**
     *  @dev Fund the pool!
     */
    function buyTokens(uint256 amount) external _hasAllowance(msg.sender, amount) returns (bool) {
        require(block.timestamp >= saleStartTime, "Sale not started yet");
        require(block.timestamp <= saleEndTime, "Sale ended");
        require(totalRaisedFundInAllTier.add(amount) <= poolMaxCap, "Exceeds pool max cap");
        uint256 userTier = userInfo[msg.sender].tier;
        require(userTier > 0 && userTier <= noOfTiers, "Not whitelisted");
        uint256 expectedAmount = amount.add(userInfo[msg.sender].totalAllocation);
        require(expectedAmount <= tierInfo[userTier].maxCap, "Amount greater than the tier max cap");
        require(expectedAmount >= tierInfo[userTier].minAllocation, "Amount less than user min allocation");
        require(expectedAmount <= tierInfo[userTier].maxAllocation, "Amount greater than user max allocation");

        totalRaisedFundInAllTier = totalRaisedFundInAllTier.add(amount);
        tierInfo[userTier].totalFundRaised = tierInfo[userTier].totalFundRaised.add(amount);
        userInfo[msg.sender].totalAllocation = expectedAmount;
        ERC20Interface.safeTransferFrom(msg.sender, projectOwner, amount);

        emit FundPool(block.timestamp, msg.sender, amount);
        return true;
    }
}

