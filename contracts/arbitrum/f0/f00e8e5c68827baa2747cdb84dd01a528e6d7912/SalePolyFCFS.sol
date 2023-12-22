// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {ERC20} from "./ERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {ISPoly} from "./ISPoly.sol";

contract SalePolyFCFS is ReentrancyGuard {
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
    // address => amount
    mapping(address => UserInfo) public userInfo;
    // participators
    address[] public addressList;

    // initializer
    bool private initialized;

    bool private adminClaimed;

    ISPoly public sPoly;
    uint256 public stakedPolyRatio = 6000;

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
        IERC20 _lpToken,
        IERC20 _offeringToken,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _releaseTime,
        uint256 _offeringAmount,
        uint256 _raisingAmount,
        address _adminAddress,
        ISPoly _sPoly,
        uint256 _stakedPolyRatio
    ) external onlyAdmin {
        require(initialized == false, "already initialized");

        lpToken = _lpToken;
        offeringToken = _offeringToken;
        startTime = _startTime;
        endTime = _endTime;
        releaseTime = _releaseTime;
        offeringAmount = _offeringAmount;
        raisingAmount = _raisingAmount;
        adminAddress = _adminAddress;
        sPoly = _sPoly;
        stakedPolyRatio = _stakedPolyRatio;

        IERC20(_offeringToken).safeApprove(address(_sPoly), type(uint256).max);
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

    function deposit(uint256 _amount) public payable virtual {
        require(
            block.timestamp > startTime && block.timestamp < endTime,
            "not IMO time"
        );
        require(_amount > 0, "need _amount > 0");
        require(totalAmount + _amount <= raisingAmount, "max cap has reached");

        lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);

        if (userInfo[msg.sender].amount == 0) {
            addressList.push(address(msg.sender));
        }
        userInfo[msg.sender].amount = userInfo[msg.sender].amount + _amount;
        totalAmount = totalAmount + _amount;
        emit Deposit(msg.sender, _amount);
    }

    function harvest() public nonReentrant {
        require(block.timestamp > endTime, "not harvest time");
        require(userInfo[msg.sender].amount > 0, "have you participated?");
        require(!userInfo[msg.sender].claimed, "nothing to harvest");
        require(releaseTime < block.timestamp, "not release time");

        uint256 offeringTokenAmount = getOfferingAmount(msg.sender);

        uint256 toStakeAmount = (offeringTokenAmount * stakedPolyRatio) / 10000;

        if (toStakeAmount > 0) {
            sPoly.stake(toStakeAmount, msg.sender);
        }

        _transferHelper(
            address(offeringToken),
            address(msg.sender),
            offeringTokenAmount - toStakeAmount
        );
        userInfo[msg.sender].claimed = true;
        emit Harvest(msg.sender, offeringTokenAmount, offeringTokenAmount);
    }

    function hasHarvest(address _user) external view returns (bool) {
        return userInfo[_user].claimed;
    }

    function getUserAllocation(address _user) public view returns (uint256) {
        if (totalAmount == 0) return 0;
        return (raisingAmount * userInfo[_user].amount) / totalAmount;
    }

    function getOfferingAmount(address _user) public view returns (uint256) {
        return (userInfo[_user].amount * getExchangeRate()) / 1e18;
    }

    function getRefundingAmount(address _user) public view returns (uint256) {
        return 0;
    }

    function getAddressListLength() external view returns (uint256) {
        return addressList.length;
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

    function getExchangeRate() public view returns (uint256) {
        return (offeringAmount * 1e18) / raisingAmount;
    }
}

