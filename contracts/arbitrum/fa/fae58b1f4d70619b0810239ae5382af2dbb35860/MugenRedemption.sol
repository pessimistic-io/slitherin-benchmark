// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import {IERC20} from "./IERC20.sol";
import {IGlpManager} from "./IGlpManager.sol";

contract MugenRedemption {
    address public constant MUGEN = 0xFc77b86F3ADe71793E1EEc1E7944DB074922856e;
    address public constant GLP_MANAGER = 0xB95DB5B167D75e6d04227CfFFA61069348d271F5;
    address public constant FS_GLP = 0x1aDDD80E6039594eE970E5872D247bf0414C8903;
    address public constant OWNER = 0x6Cb6D9Fb673CfbF31b3A432F6316fE3196efd4aA;
    address public constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    uint256 public exchangeRate;
    bool public opened;
    bool public paused;
    uint256 public immutable close;
    mapping(address => uint256) public redeemed;

    modifier isPaused() {
        if (paused) revert Paused();
        _;
    }

    constructor() {
        close = block.timestamp + (86400 * 90); // 90 days
    }

    function exchangeGlp(uint256 amount) external {
        if (msg.sender != OWNER) revert OnlyOwner();
        IGlpManager(GLP_MANAGER).unstakeAndRedeemGlp(
            USDC, IERC20(FS_GLP).balanceOf(address(this)), amount, address(this)
        );
    }

    ///@notice redeem all of the users Mugen balance at the set exchange rate for USDC;
    function redeem() external isPaused {
        if (!opened) revert NotOpen();
        address sender = msg.sender;
        uint256 amount = IERC20(MUGEN).balanceOf(sender);
        IERC20(MUGEN).transferFrom(sender, address(this), amount);
        uint256 shares = (amount * exchangeRate) / 1e18;
        IERC20(USDC).transfer(sender, shares);
        redeemed[sender] = shares; // Store proportions for airdrop of unclaimed funds post 90 days;
        emit Redeemed(sender, shares, amount);
    }

    function openRedemption() external {
        if (opened) revert AlreadyOpened();
        if (msg.sender != OWNER) revert OnlyOwner();
        uint256 share = IERC20(USDC).balanceOf(address(this)) * 75 / 1_000;
        IERC20(USDC).transfer(OWNER, share);
        exchangeRate = IERC20(USDC).balanceOf(address(this)) * 1e18 / IERC20(MUGEN).totalSupply();
        opened = true;
        emit Opened(msg.sender, exchangeRate);
    }

    function collectRemainder(address _to) external {
        if (block.timestamp < close) revert StillOpen();
        if (msg.sender != OWNER) revert OnlyOwner();
        uint256 _balance = IERC20(USDC).balanceOf(address(this));
        IERC20(USDC).transfer(_to, _balance);
        emit Collect(msg.sender, _to, _balance);
    }

    function emergencyWithdraw(address to, bytes calldata data) external {
        if (msg.sender != OWNER) revert OnlyOwner();
        (bool success,) = address(to).call(data);
        if (!success) revert CallFailed();
    }

    function pause() external {
        if (msg.sender != OWNER) revert OnlyOwner();
        paused = true;
    }

    function unpause() external {
        if (msg.sender != OWNER) revert OnlyOwner();
        paused = false;
    }

    event Collect(address indexed caller, address indexed receiver, uint256 amount);
    event Redeemed(address indexed caller, uint256 shares, uint256 amount);
    event Opened(address indexed caller, uint256 rate);

    error AlreadyOpened();
    error OnlyOwner();
    error NotOpen();
    error StillOpen();
    error Paused();
    error CallFailed();
}

