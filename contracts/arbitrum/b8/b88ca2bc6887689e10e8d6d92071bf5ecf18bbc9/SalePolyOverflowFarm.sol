// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import {IERC20} from "./IERC20.sol";
import {ERC20} from "./ERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {ISPoly} from "./ISPoly.sol";

contract SalePolyOverflowFarm is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
        bool claimed; // default false
        uint256 rewardDebt;
    }

    // admin address
    address public adminAddress;
    // The raising token
    IERC20 public lpToken;
    // The offering token
    IERC20 public offeringToken;
    // The block number when IMO starts
    uint256 public startTime;
    // The block number when IMO ends
    uint256 public endTime;
    // The block number when release
    uint256 public releaseTime;
    // total amount of raising tokens need to be raised
    uint256 public raisingAmount;
    // total amount of offeringToken that will offer
    uint256 public offeringAmount;
    // total amount of raising tokens that have already raised
    uint256 public totalAmount;
    // hardcap
    // address => amount
    mapping(address => UserInfo) public userInfo;
    // participators
    address[] public addressList;

    ISPoly public sPoly;
    uint256 public stakedPolyRatio = 6000;

    // initializer
    bool private initialized;

    bool private adminClaimed;

    // OVERFLOW FARMING
    // The timestamp of the last pool update
    uint256 public lastRewardTimestamp;

    // Accrued token per share
    uint256 public accTokenPerShare;

    // Reward tokens created per second.
    uint256 public rewardPerSecond;
    // Reward tokens
    IERC20 public rewardToken;
    //
    uint256 public PRECISION_FACTOR;

    mapping(address => uint256) public rewardStored;

    event Deposit(address indexed user, uint256 amount);
    event Harvest(
        address indexed user,
        uint256 offeringAmount,
        uint256 excessAmount
    );

    receive() external payable {}

    constructor() {
        adminAddress = msg.sender;
    }

    function initialize(
        IERC20 _lpToken, // address(0)
        IERC20 _offeringToken, // POLY
        uint256 _startTime, //
        uint256 _endTime,
        uint256 _releaseTime,
        uint256 _offeringAmount,
        uint256 _raisingAmount,
        address _adminAddress,
        ISPoly _sPoly,
        uint256 _stakedPolyRatio,
        IERC20 _rewardToken,
        uint256 _rewardPerSecond
    ) external onlyAdmin {
        require(initialized == false, "already initialized");

        lpToken = _lpToken;
        offeringToken = _offeringToken;
        startTime = _startTime;
        endTime = _endTime;
        releaseTime = _releaseTime;
        offeringAmount = _offeringAmount;
        raisingAmount = _raisingAmount;
        totalAmount = 0;
        adminAddress = _adminAddress;
        sPoly = _sPoly;
        stakedPolyRatio = _stakedPolyRatio;

        IERC20(_offeringToken).safeApprove(address(_sPoly), type(uint256).max);

        rewardToken = _rewardToken;
        rewardPerSecond = _rewardPerSecond;

        lastRewardTimestamp = startTime;

        uint256 decimalsRewardToken = uint256(
            ERC20(address(rewardToken)).decimals()
        );
        require(decimalsRewardToken < 30, "Must be inferior to 30");

        PRECISION_FACTOR = uint256(10 ** (uint256(30) - decimalsRewardToken));

        initialized = true;
    }

    modifier onlyAdmin() {
        require(msg.sender == adminAddress, "admin: wut?");
        _;
    }

    function setOfferingAmount(uint256 _offerAmount) public onlyAdmin {
        require(block.timestamp < startTime, "no");
        offeringAmount = _offerAmount;
    }

    function setRaisingAmount(uint256 _raisingAmount) public onlyAdmin {
        require(block.timestamp < startTime, "no");
        raisingAmount = _raisingAmount;
    }

    function deposit(uint256 _amount) public payable {
        require(
            block.timestamp > startTime && block.timestamp < endTime,
            "not IMO time"
        );
        require(_amount > 0, "need _amount > 0");
        // for overflow farming
        _updatePool();

        rewardStored[msg.sender] =
            rewardStored[msg.sender] +
            ((userInfo[msg.sender].amount * accTokenPerShare) /
                PRECISION_FACTOR -
                userInfo[msg.sender].rewardDebt);

        lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);

        if (userInfo[msg.sender].amount == 0) {
            addressList.push(address(msg.sender));
        }
        userInfo[msg.sender].amount = userInfo[msg.sender].amount + _amount;
        totalAmount = totalAmount + _amount;

        userInfo[msg.sender].rewardDebt =
            (userInfo[msg.sender].amount * accTokenPerShare) /
            PRECISION_FACTOR;
        emit Deposit(msg.sender, _amount);
    }

    function harvest() public nonReentrant {
        require(block.timestamp > endTime, "not harvest time");
        require(userInfo[msg.sender].amount > 0, "have you participated?");
        require(!userInfo[msg.sender].claimed, "nothing to harvest");
        _updatePool();

        uint256 offeringTokenAmount = getOfferingAmount(msg.sender);
        uint256 refundingTokenAmount = getRefundingAmount(msg.sender);

        uint256 toStakeAmount = (offeringTokenAmount * stakedPolyRatio) / 10000;

        if (toStakeAmount > 0) {
            sPoly.stake(toStakeAmount, msg.sender);
        }

        _transferHelper(
            address(offeringToken),
            address(msg.sender),
            offeringTokenAmount - toStakeAmount
        );
        if (refundingTokenAmount > 0) {
            _transferHelper(
                address(lpToken),
                address(msg.sender),
                refundingTokenAmount
            );
        }
        userInfo[msg.sender].claimed = true;
        emit Harvest(msg.sender, offeringTokenAmount, refundingTokenAmount);
    }

    function hasHarvest(address _user) external view returns (bool) {
        return userInfo[_user].claimed;
    }

    // allocation 100000 means 0.1(10%), 1 meanss 0.000001(0.0001%), 1000000 means 1(100%)
    function getUserAllocation(address _user) public view returns (uint256) {
        return (userInfo[_user].amount * 1e12) / totalAmount / 1e6;
    }

    // get the amount of imo token you will get
    function getOfferingAmount(address _user) public view returns (uint256) {
        if (totalAmount > raisingAmount) {
            uint256 allocation = getUserAllocation(_user);
            return (offeringAmount * allocation) / 1e6;
        } else {
            // userInfo[_user] / (raisingAmount / offeringAmount)
            return (userInfo[_user].amount * offeringAmount) / raisingAmount;
        }
    }

    // get the amount of lp token you will be refunded
    function getRefundingAmount(address _user) public view returns (uint256) {
        if (totalAmount <= raisingAmount) {
            return 0;
        }
        uint256 allocation = getUserAllocation(_user);
        uint256 payAmount = (raisingAmount * allocation) / 1e6;
        return userInfo[_user].amount - payAmount;
    }

    function getAddressListLength() external view returns (uint256) {
        return addressList.length;
    }

    function withdrawAdmin(uint256 _amount) public onlyAdmin {
        // calculate admin
        _transferHelper(address(lpToken), address(msg.sender), _amount);
    }

    function finalWithdraw(
        uint256 _lpAmount,
        uint256 _offerAmount
    ) public onlyAdmin {
        if (address(lpToken) == address(0)) {
            require(_lpAmount > address(this).balance, "not enough token 0");
        } else {
            require(
                _lpAmount <= lpToken.balanceOf(address(this)),
                "not enough token 0"
            );
        }
        require(
            _offerAmount <= offeringToken.balanceOf(address(this)),
            "not enough token 1"
        );
        _transferHelper(address(lpToken), address(msg.sender), _lpAmount);
        _transferHelper(
            address(offeringToken),
            address(msg.sender),
            _offerAmount
        );
    }

    function _transferHelper(
        address _token,
        address _to,
        uint256 _amount
    ) internal {
        if (_token == address(0)) {
            (bool success, ) = payable(_to).call{value: _amount}("");
            require(success, "TransferHelper: ETH_TRANSFER_FAILED");
        } else {
            IERC20(_token).safeTransfer(_to, _amount);
        }
    }

    // OVERFLOW FARMING

    /*
     * @notice Update reward variables of the given pool to be up-to-date.
     */
    function _updatePool() internal {
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }

        uint256 stakedTokenSupply = lpToken.balanceOf(address(this));

        if (stakedTokenSupply == 0) {
            lastRewardTimestamp = block.timestamp;
            return;
        }

        uint256 multiplier = _getMultiplier(
            lastRewardTimestamp,
            block.timestamp
        );
        uint256 rewardTokenReward = multiplier * rewardPerSecond;
        accTokenPerShare =
            accTokenPerShare +
            ((rewardTokenReward * PRECISION_FACTOR) / stakedTokenSupply);
        lastRewardTimestamp = block.timestamp;
    }

    /*
     * @notice Return reward multiplier over the given _from to _to timestamp.
     * @param _from: timestamp to start
     * @param _to: timestamp to finish
     */
    function _getMultiplier(
        uint256 _from,
        uint256 _to
    ) internal view returns (uint256) {
        if (_to <= endTime) {
            return _to - _from;
        } else if (_from >= endTime) {
            return 0;
        } else {
            return endTime - _from;
        }
    }

    /*
     * @notice View function to see pending reward on frontend.
     * @param _user: user address
     * @return Pending reward for a given user
     */
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 stakedTokenSupply = lpToken.balanceOf(address(this));
        uint256 reward = 0;
        if (block.timestamp > lastRewardTimestamp && stakedTokenSupply != 0) {
            uint256 multiplier = _getMultiplier(
                lastRewardTimestamp,
                block.timestamp
            );
            uint256 rewardTokenReward = multiplier * rewardPerSecond;
            uint256 adjustedTokenPerShare = accTokenPerShare +
                ((rewardTokenReward * PRECISION_FACTOR) / stakedTokenSupply);
            reward =
                (user.amount * adjustedTokenPerShare) /
                PRECISION_FACTOR -
                user.rewardDebt;
        } else {
            reward =
                (user.amount * accTokenPerShare) /
                PRECISION_FACTOR -
                (user.rewardDebt);
        }

        return reward + rewardStored[_user];
    }

    function harvestOverflowReward() public nonReentrant {
        require(block.timestamp > endTime, "not harvest time");
        UserInfo storage user = userInfo[msg.sender];
        _updatePool();
        uint256 pending = 0;
        if (user.amount > 0) {
            pending =
                (user.amount * accTokenPerShare) /
                PRECISION_FACTOR -
                user.rewardDebt;
            pending = pending + rewardStored[msg.sender];
            if (pending > 0) {
                _transferHelper(
                    address(rewardToken),
                    address(msg.sender),
                    pending
                );
            }
        }
        user.rewardDebt = (user.amount * accTokenPerShare) / PRECISION_FACTOR;
    }
}

