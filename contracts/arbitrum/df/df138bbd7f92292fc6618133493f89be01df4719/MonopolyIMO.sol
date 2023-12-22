// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

contract MonopolyIMO is ReentrancyGuard {
    // ETH ONLY
    // OVERFLOW
    // raising 100K
    /**
     지분율만큼
     */

    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
        bool claimed; // default false
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

    // initializer
    bool private initialized;

    bool private adminClaimed;

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
        IERC20 _offeringToken, // MONO
        uint256 _startTime, //
        uint256 _endTime,
        uint256 _offeringAmount,
        uint256 _raisingAmount,
        address _adminAddress
    ) external onlyAdmin {
        require(initialized == false, "already initialized");

        lpToken = _lpToken;
        offeringToken = _offeringToken;
        startTime = _startTime;
        endTime = _endTime;
        offeringAmount = _offeringAmount;
        raisingAmount = _raisingAmount;
        totalAmount = 0;
        adminAddress = _adminAddress;
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

        if (address(lpToken) != address(0)) {
            lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
        } else {
            require(_amount == msg.value, "not same amount");
        }
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
        uint256 offeringTokenAmount = getOfferingAmount(msg.sender);
        uint256 refundingTokenAmount = getRefundingAmount(msg.sender);

        _transferHelper(
            address(offeringToken),
            address(msg.sender),
            offeringTokenAmount
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
                _lpAmount < lpToken.balanceOf(address(this)),
                "not enough token 0"
            );
        }
        require(
            _offerAmount < offeringToken.balanceOf(address(this)),
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
}

