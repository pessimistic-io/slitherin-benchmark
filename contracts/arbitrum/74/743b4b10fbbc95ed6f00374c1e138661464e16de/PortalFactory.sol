//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IERC20.sol";
import "./IArbipad.sol";
import "./IRefundController.sol";
import "./Portal.sol";

/**
 * @dev Contract module to deploy a portal automatically
 */
contract PortalFactory is Ownable {
    bytes4 private constant SIG_DECIMALS = 0x313ce567; // decimals()
    address public immutable REFUND_CONTROLLER;

    /**
     * @dev Emitted when launchPortal function is succesfully called and a portal for token claim is created
     */
    event PortalCreation(
        uint256 indexed timestamp,
        Portal indexed portalAddress,
        address indexed tokenAddress,
        string tokenName,
        string portalName,
        address[] fundingPool,
        uint256 tokenPrice,
        uint256 vestingAllocInBps,
        uint256 tokenAmount,
        string imgUrl
    );

    constructor(address _REFUND_CONTROLLER) {
        REFUND_CONTROLLER = _REFUND_CONTROLLER;
    }

    /**
     * @dev Create a portal.
     * Note: input Vesting Alloc in bips, e.g 10% => 1000, 20% => 2000
     * emits a {PortalCreation} event
     */
    function launchPortal(
        string memory _tokenName,
        string memory _portalName,
        address _tokenAddress,
        address[] memory _fundingPool,
        uint256 _tokenPrice,
        uint256 _vestingAllocInBps,
        uint256 _claimableAt,
        string memory _imgUrl
    ) public onlyOwner {
        Portal _portal;
        _portal = new Portal(
            owner(),
            _portalName,
            _tokenAddress,
            REFUND_CONTROLLER,
            _fundingPool,
            _tokenPrice,
            _vestingAllocInBps,
            _claimableAt
        );

        uint256 _tokenAmount = _calculateTokenAmount(_fundingPool, _tokenAddress, _tokenPrice, _vestingAllocInBps);
        IERC20 _ERC20Interface = IERC20(_tokenAddress);
        _ERC20Interface.transferFrom(msg.sender, address(_portal), _tokenAmount);

        IRefundController(REFUND_CONTROLLER).openRefundWindow(_claimableAt, _tokenAddress, _fundingPool);
        IRefundController(REFUND_CONTROLLER).grantRole(keccak256("ADMIN_ROLE"),address(_portal));

        emit PortalCreation(
            block.timestamp,
            _portal,
            _tokenAddress,
            _tokenName,
            _portalName,
            _fundingPool,
            _tokenPrice,
            _vestingAllocInBps,
            _tokenAmount,
            _imgUrl
        );
    }

    /**
     * @dev Calculate amount of token to be transferred, based on the total raised fund in pool & vesting bps. Handling the decimals too!
     * @return Claimable token
     */
    function _calculateTokenAmount(
        address[] memory _fundingPool,
        address _tokenAddress,
        uint256 _tokenPrice,
        uint256 _vestingAllocInBps
    ) private view returns (uint256) {
        uint256 _bpsDivisor = 10000;
        address _fundingToken = IArbipad(_fundingPool[0]).tokenAddress();
        uint256 _fundingTokenDecimals = safeDecimals(_fundingToken);
        uint256 _vestingTokenDecimals = safeDecimals(_tokenAddress);
        uint256 _denominator = 10**_vestingTokenDecimals;

        uint256 _totalRaisedFund;
        for (uint256 i = 0; i < _fundingPool.length; i++) {
            _totalRaisedFund += IArbipad(_fundingPool[i]).totalRaisedFundInAllTier();
        }

        uint256 _refunded = IRefundController(REFUND_CONTROLLER).totalRefundedAmount(_tokenAddress);
        uint256 _finalRaisedFund = _totalRaisedFund - _refunded;

        if (_fundingTokenDecimals == _vestingTokenDecimals) {
            return FullMath.mulDiv((_finalRaisedFund * _vestingAllocInBps) / _bpsDivisor, _denominator, _tokenPrice);
        } else if (_fundingTokenDecimals < _vestingTokenDecimals) {
            uint256 _totalRaisedFundAdj = _finalRaisedFund * 10**(_vestingTokenDecimals - _fundingTokenDecimals);
            return FullMath.mulDiv((_totalRaisedFundAdj * _vestingAllocInBps) / _bpsDivisor, _denominator, _tokenPrice);
        } else {
            uint256 _totalRaisedFundAdj = _finalRaisedFund / 10**(_fundingTokenDecimals - _vestingTokenDecimals);
            return FullMath.mulDiv((_totalRaisedFundAdj * _vestingAllocInBps) / _bpsDivisor, _denominator, _tokenPrice);
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

