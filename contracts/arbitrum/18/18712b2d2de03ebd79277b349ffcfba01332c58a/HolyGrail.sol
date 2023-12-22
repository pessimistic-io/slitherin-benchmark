// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IERC20Metadata} from "./IERC20Metadata.sol";

import {SafeOwnable} from "./SafeOwnable.sol";

interface IPresale {
    function START_TIME() external view returns (uint256);

    function END_TIME() external view returns (uint256);

    function GRAIL() external view returns (address);

    function XGRAIL() external view returns (address);

    function LP_TOKEN() external view returns (address);

    function hasStarted() external view returns (bool);

    function isSaleActive() external view returns (bool);

    function totalRaised() external view returns (uint256);

    function totalAllocation() external view returns (uint256);

    function MIN_TOTAL_RAISED_FOR_MAX_GRAIL() external view returns (uint256);

    function getExpectedClaimAmounts(address account) external view returns (uint256 grailAmount, uint256 xGrailAmount);

    function buy(uint256 amount, address referralAddress) external;

    function claim() external;
}

interface IXGrailToken {
    function maxRedeemDuration() external view returns (uint256);

    function redeem(uint256 xGrailAmount, uint256 duration) external;

    function finalizeRedeem(uint256 redeemIndex) external;
}

/// @notice Snipes GRAIL and xGRAIL presale with USDC
/// @dev Only works on Arbitrum One
contract HolyGrail is SafeOwnable {
    address public constant PRESALE = 0x66eC1EE6c3AD04d7629Ce4a6d5d19ba99c365d29;
    address public constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    address public immutable grail;
    address public immutable xgrail;

    constructor(address owner) SafeOwnable(owner) {
        grail = IPresale(PRESALE).GRAIL();
        xgrail = IPresale(PRESALE).XGRAIL();
    }

    function timestamp() public view returns (uint256) {
        return block.timestamp;
    }

    function startTime() public view returns (uint256) {
        return IPresale(PRESALE).START_TIME();
    }

    function endTime() public view returns (uint256) {
        return IPresale(PRESALE).END_TIME();
    }

    function startIn() public view returns (uint256) {
        return IPresale(PRESALE).START_TIME() - timestamp();
    }

    function endIn() public view returns (uint256) {
        return IPresale(PRESALE).END_TIME() - timestamp();
    }

    function shouldSnipe() public view returns (bool) {
        uint256 roof = IPresale(PRESALE).MIN_TOTAL_RAISED_FOR_MAX_GRAIL();
        return IPresale(PRESALE).hasStarted() && IPresale(PRESALE).totalRaised() < roof;
    }

    function buyAll(address _for) external {
        IERC20Metadata(USDC).transferFrom(_for, address(this), IERC20Metadata(USDC).allowance(_for, address(this)));
        uint256 _balance = IERC20Metadata(USDC).balanceOf(address(this));

        IERC20Metadata(USDC).approve(PRESALE, _balance);
        IPresale(PRESALE).buy(_balance, address(0));

        (uint256 grailClaimable, uint256 xgrailClaimable) = IPresale(PRESALE).getExpectedClaimAmounts(address(this));
        require(grailClaimable >= ((_balance * 1E18) / 10 ** IERC20Metadata(USDC).decimals()) / 35, "missed grail");
        require(xgrailClaimable >= ((_balance * 1E18) / 10 ** IERC20Metadata(USDC).decimals()) / 65, "missed xgrail");
    }

    function claimAll(address _for) external onlyOwner {
        IPresale(PRESALE).claim();
        IERC20Metadata(grail).transfer(_for, IERC20Metadata(grail).balanceOf(address(this)));
    }

    function redeemAll() external onlyOwner {
        IXGrailToken(xgrail).redeem(
            IERC20Metadata(xgrail).balanceOf(address(this)),
            IXGrailToken(xgrail).maxRedeemDuration()
        );
    }

    function finalizeRedeemAll(address _for, uint256 _index) external onlyOwner {
        IXGrailToken(xgrail).finalizeRedeem(_index);
        IERC20Metadata(grail).transfer(_for, IERC20Metadata(grail).balanceOf(address(this)));
    }
}

