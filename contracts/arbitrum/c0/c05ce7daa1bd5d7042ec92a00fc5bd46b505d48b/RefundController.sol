//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./SafeERC20.sol";
import "./IArbipad.sol";

/**
 * @dev Contract module to Gather Refund Data through Emitting Event
 */
contract RefundController is AccessControl {
    using SafeERC20 for IERC20;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    struct TokenPortalRefundInfo {
        address[] fundingPool;
        uint256 windowCloseUntil;
        uint256 totalRefundedAmount;
    }
    mapping(address => TokenPortalRefundInfo) public tokenPortalRefundInfo;

    struct UserRefundInfo {
        uint256 eligibleForRefund; // 0 if Not Eligible, 1 if Eligible, 2 if Not Eligible (claimed)
        uint256 requestRefundedAt;
        uint256 totalRefundedAmount;
    }
    mapping(address => mapping(address => UserRefundInfo)) public userRefundInfo;

    uint256 public refundWindow;

    event RequestedRefund(
        uint256 indexed timestamp,
        address indexed userAddress,
        address indexed tokenAddress,
        address[] fundingPool,
        uint256 refundAmount
    );

    constructor(uint256 _refundWindow) {
        refundWindow = _refundWindow;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);
    }

    function requestRefund(address _userAddress, address _tokenAddress) external {
        require(msg.sender == _userAddress, "Unauthorized User!");
        require(userRefundInfo[_userAddress][_tokenAddress].eligibleForRefund == 0, "Not Eligible for refund!");
        require(userRefundInfo[_userAddress][_tokenAddress].requestRefundedAt == 0, "Requested!");
        require(block.timestamp <= tokenPortalRefundInfo[_tokenAddress].windowCloseUntil, "Out of refund window!");

        userRefundInfo[_userAddress][_tokenAddress].requestRefundedAt = block.timestamp;
        userRefundInfo[_userAddress][_tokenAddress].eligibleForRefund = 1;

        address[] memory _fundingPool = tokenPortalRefundInfo[_tokenAddress].fundingPool;
        uint256 refundedAmount = _userAllocation(_userAddress, _fundingPool);
        require(refundedAmount > 0, "Zero allocation!");
        userRefundInfo[_userAddress][_tokenAddress].totalRefundedAmount = refundedAmount;
        tokenPortalRefundInfo[_tokenAddress].totalRefundedAmount += refundedAmount;

        emit RequestedRefund(block.timestamp, msg.sender, _tokenAddress, _fundingPool, refundedAmount);
    }

    function updateUserEligibility(address _userAddress, address _tokenAddress, uint256 _eligibility) external onlyRole(ADMIN_ROLE) {
        userRefundInfo[_userAddress][_tokenAddress].eligibleForRefund = _eligibility;
    }

    function openRefundWindow(uint256 _claimableAt, address _tokenAddress, address[] memory _fundingPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 _windowCloseUntil = tokenPortalRefundInfo[_tokenAddress].windowCloseUntil;
        tokenPortalRefundInfo[_tokenAddress].fundingPool = _fundingPool;
        if (_windowCloseUntil == 0) {
            tokenPortalRefundInfo[_tokenAddress].windowCloseUntil = _claimableAt + refundWindow;
        }
    }

    function changeRefundWindow(uint256 _refundWindow) external onlyRole(ADMIN_ROLE) {
        refundWindow = _refundWindow;
    }

    function totalRefundedAmount(address _tokenAddress) external view returns (uint256) {
        return tokenPortalRefundInfo[_tokenAddress].totalRefundedAmount;
    }

    function eligibleForRefund(address _userAddress, address _tokenAddress) external view returns (uint256) {
        return userRefundInfo[_userAddress][_tokenAddress].eligibleForRefund;
    }

    function windowCloseUntil(address _tokenAddress) external view returns (uint256) {
        return tokenPortalRefundInfo[_tokenAddress].windowCloseUntil;
    }

    function _userAllocation(address _userAddress, address[] memory fundingPool) private view returns (uint256) {
        uint256 totalAllocation;
        for (uint256 i; i < fundingPool.length; i++) {
            IArbipad _arbipadInterface = IArbipad(fundingPool[i]);
            totalAllocation += _arbipadInterface.userInfo(_userAddress).totalAllocation;
        }
        return totalAllocation;
    }
}

