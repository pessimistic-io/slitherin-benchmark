// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./IArbipad.sol";
import "./FullMath.sol";
import "./IRefundController.sol";

contract Portal is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    bytes4 private constant SIG_DECIMALS = 0x313ce567; // decimals()
    address public immutable REFUND_CONTROLLER;

    IERC20 _ERC20Interface;

    string public name;
    address[] public fundingPool;
    address public tokenAddress;
    uint256 public tokenPrice;
    uint256 public vestingAllocInBps;
    uint256 public claimableAt;
    mapping(address => bool) private _claimed;
    bool public refundClaimed;

    event ClaimToken(uint256 indexed timestamp, address indexed initiator, address indexed tokenAddress, uint256 value);

    constructor(
        address portalOwner,
        string memory _name,
        address _tokenAddress,
        address _REFUND_CONTROLLER,
        address[] memory _fundingPool,
        uint256 _tokenPrice,
        uint256 _vestingAllocInBps,
        uint256 _claimableAt
    ) {
        require(portalOwner != address(0), "Zero project owner address");
        require(_tokenAddress != address(0), "Zero token address");
        require(_fundingPool.length > 0, "Invalid input fundingPool");
        REFUND_CONTROLLER = _REFUND_CONTROLLER;
        transferOwnership(portalOwner);
        name = _name;
        tokenAddress = _tokenAddress;
        fundingPool = _fundingPool;
        tokenPrice = _tokenPrice;
        vestingAllocInBps = _vestingAllocInBps;
        claimableAt = _claimableAt;
        _ERC20Interface = IERC20(tokenAddress);
    }

    /**
     * @dev Claim the token.
     *
     * emits a {ClaimToken} event
     */
    function claimToken() external whenNotPaused nonReentrant {
        require(block.timestamp >= claimableAt, "Not Claimable yet!");
        uint256 _tokenAmount = _calculateClaimableToken(msg.sender);
        require(_tokenAmount > 0, "Zero Allocation!");
        require(!_claimed[msg.sender], "Claimed!");
        uint256 _isRefund = IRefundController(REFUND_CONTROLLER).eligibleForRefund(msg.sender, tokenAddress);
        require(_isRefund != 1, "Requested for refund!");

        _ERC20Interface.safeTransfer(msg.sender, _tokenAmount);
        _claimed[msg.sender] = true;

        // update in refund contract about user already claimt he token
        IRefundController(REFUND_CONTROLLER).updateUserEligibility(msg.sender, tokenAddress, 2);
        emit ClaimToken(block.timestamp, msg.sender, tokenAddress, _tokenAmount);
    }

    /**
     * @dev Claim refunded token
     *
     */
    function claimRefundedToken() external onlyOwner {
        uint256 windowClose = IRefundController(REFUND_CONTROLLER).windowCloseUntil(tokenAddress);
        require(block.timestamp >= windowClose, "Refund window still open");
        require(!refundClaimed, "Refund claimed!");
        uint256 totalRefundedAmount = IRefundController(REFUND_CONTROLLER).totalRefundedAmount(tokenAddress);
        address _fundingToken = IArbipad(fundingPool[0]).tokenAddress();
        uint256 _fundingTokenDecimals = safeDecimals(_fundingToken);
        uint256 _vestingTokenDecimals = safeDecimals(tokenAddress);
        uint256 _denominator = 10**_vestingTokenDecimals;
        uint256 _bpsDivisor = 10000;

        // Convert to token amount
        uint256 tokenAmount;
        if (_fundingTokenDecimals == _vestingTokenDecimals) {
            tokenAmount = FullMath.mulDiv((totalRefundedAmount * vestingAllocInBps) / _bpsDivisor, _denominator, tokenPrice);
        } else if (_fundingTokenDecimals < _vestingTokenDecimals) {
            uint256 totalRefundedAmountAdj = totalRefundedAmount * 10**(_vestingTokenDecimals - _fundingTokenDecimals);
            tokenAmount = FullMath.mulDiv((totalRefundedAmountAdj * vestingAllocInBps) / _bpsDivisor, _denominator, tokenPrice);
        } else {
            uint256 totalRefundedAmountAdj = totalRefundedAmount / 10**(_fundingTokenDecimals - _vestingTokenDecimals);
            tokenAmount = FullMath.mulDiv((totalRefundedAmountAdj * vestingAllocInBps) / _bpsDivisor, _denominator, tokenPrice);
        }

        _ERC20Interface.safeTransfer(msg.sender, tokenAmount);
        refundClaimed = true;
    }

    /**
     * @dev Claim all the token if something went wrong within this contract.
     *
     */
    function sweep() external onlyOwner whenPaused {
        uint256 _tokenBalance = _ERC20Interface.balanceOf(address(this));
        _ERC20Interface.safeTransfer(msg.sender, _tokenBalance);
    }

    /**
     * @dev Pause the contract
     *
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev UnPause the contract
     *
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Retrive current Token Balance
     * @return Token Balance
     */
    function balanceOfToken() external view returns (uint256) {
        return _ERC20Interface.balanceOf(address(this));
    }

    /**
     * @dev Current user's status
     * @param _address, User's address
     * @return User's status
     */
    function isClaimed(address _address) external view returns (bool) {
        return _claimed[_address];
    }

    /**
     * @dev Retrive user's pool allocation.
     * @param _address, User's address
     * @return User's pool allocation info
     */
    function userAllocation(address _address) external view returns (uint256) {
        return _userAllocation(_address);
    }

    /**
     * @dev Retrive amount of token that can be claimed, based on the user's pool allocation.
     * @param _address, User's address
     * @return Claimable token
     */
    function claimableTokenAmount(address _address) external view returns (uint256) {
        return _calculateClaimableToken(_address);
    }

    /**
     * @dev Retrive user in pool.
     * @param _address, User's address
     * @return User's pool info
     */
    // function userInfo(address _address) public view returns (IArbipad.User[] memory) {
    function userInfo(address _address) external view returns (IArbipad.User[] memory) {
        IArbipad.User[] memory _userInPool = new IArbipad.User[](fundingPool.length);
        for (uint256 i; i < fundingPool.length; i++) {
            IArbipad _arbipadInterface = IArbipad(fundingPool[i]);
            _userInPool[i] = _arbipadInterface.userInfo(_address);
        }
        // return _userInPool;
        return _userInPool;
    }

    /**
     * @dev Retrive user's pool allocation.
     * @param _address, User's address
     * @return User's pool allocation info
     */
    function _userAllocation(address _address) private view returns (uint256) {
        uint256 totalAllocation;
        for (uint256 i; i < fundingPool.length; i++) {
            IArbipad _arbipadInterface = IArbipad(fundingPool[i]);
            totalAllocation += _arbipadInterface.userInfo(_address).totalAllocation;
        }
        return totalAllocation;
    }

    /**
     * @dev Calculate amount of token that can be claimed, based on the pool allocation & vesting bps. Handling the decimals too!
     * @return Claimable token
     */
    function _calculateClaimableToken(address _address) private view returns (uint256) {
        uint256 _bpsDivisor = 10000;
        address _fundingToken = IArbipad(fundingPool[0]).tokenAddress();
        uint256 _fundingTokenDecimals = safeDecimals(_fundingToken);
        uint256 _vestingTokenDecimals = safeDecimals(tokenAddress);
        uint256 _denominator = 10**_vestingTokenDecimals;

        uint256 _isRefund = IRefundController(REFUND_CONTROLLER).eligibleForRefund(_address, tokenAddress);
        if (_isRefund == 1) {
            return 0;
        }

        // Calculate the claimable tokens
        if (_fundingTokenDecimals == _vestingTokenDecimals) {
            uint256 _totalAllocation = _userAllocation(_address);
            return FullMath.mulDiv((_totalAllocation * vestingAllocInBps) / _bpsDivisor, _denominator, tokenPrice);
        } else if (_fundingTokenDecimals < _vestingTokenDecimals) {
            uint256 _totalAllocation = _userAllocation(_address) * 10**(_vestingTokenDecimals - _fundingTokenDecimals);
            return FullMath.mulDiv((_totalAllocation * vestingAllocInBps) / _bpsDivisor, _denominator, tokenPrice);
        } else {
            uint256 _totalAllocation = _userAllocation(_address) / 10**(_fundingTokenDecimals - _vestingTokenDecimals);
            return FullMath.mulDiv((_totalAllocation * vestingAllocInBps) / _bpsDivisor, _denominator, tokenPrice);
        }
    }

    /// @notice Provides a safe ERC20.decimals version which returns '18' as fallback value.
    /// @param _token The address of the ERC-20 token contract.
    /// @return (uint8) Token decimals.
    function safeDecimals(address _token) private view returns (uint8) {
        (bool success, bytes memory data) = address(_token).staticcall(abi.encodeWithSelector(SIG_DECIMALS));
        return success && data.length == 32 ? abi.decode(data, (uint8)) : 18;
    }
}

