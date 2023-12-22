// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IPeon.sol";
import "./IiToken.sol";
import "./IRewardDistributorV3.sol";
import "./IControllerInterface.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

contract Peon is Ownable {
    using SafeERC20 for IERC20;

    address public constant CONTROLLER = 0x8E7e9eA9023B81457Ae7E6D2a51b003D421E5408;
    address public constant REWARD_DISTRIBUTOR = 0xF45e2ae152384D50d4e9b08b8A1f65F0d96786C3;
    address public constant DF = 0xaE6aab43C4f3E0cea4Ab83752C278f8dEbabA689;

    address public chief;
    address public iSuppliedToken;
    address public iBorrowedToken;
    address public suppliedToken;
    address public borrowedToken;

    modifier onlyChiefOrOwner() {
        require(chief != address(0), "chief not initialized");
        require(msg.sender == chief || msg.sender == owner());
        _;
    }

    constructor(address _owner, address _chief, address _iSuppliedToken, address _iBorrowedToken, address _suppliedToken, address _borrowedToken) {
        transferOwnership(_owner);
        
        chief = _chief;
        iSuppliedToken = _iSuppliedToken;
        iBorrowedToken = _iBorrowedToken;
        suppliedToken = _suppliedToken;
        borrowedToken = _borrowedToken;

        address[] memory markets = new address[](2);
        markets[0] = _iSuppliedToken;
        markets[1] = _iBorrowedToken;
        IControllerInterface(CONTROLLER).enterMarkets(markets);
    
        IERC20(_suppliedToken).safeApprove(_iSuppliedToken, type(uint256).max);
        // IERC20(_borrowedToken).safeApprove(_iBorrowedToken, type(uint256).max);
    }

    function supply(uint256 amount) external onlyChiefOrOwner() {
        IERC20(suppliedToken).safeTransferFrom(msg.sender, address(this), amount);
        IiToken(iSuppliedToken).mint(address(this), amount);
    }

    function withdraw(uint256 amount) external onlyChiefOrOwner() {
        IiToken(iSuppliedToken).redeemUnderlying(address(this), amount);
        IERC20(suppliedToken).safeTransfer(msg.sender, amount);
    }

    function borrow(uint256 amount) external onlyChiefOrOwner() {
        IiToken(iBorrowedToken).borrow(amount);
        IERC20(borrowedToken).safeTransfer(msg.sender, amount);
    }

    function repay(uint256 amount) external onlyChiefOrOwner() {
        IERC20(borrowedToken).safeTransferFrom(msg.sender, address(this), amount);
        IiToken(iBorrowedToken).repayBorrow(amount);
    }

    function claimReward() external onlyChiefOrOwner() {
        address[] memory holders = new address[](1);
        holders[0] = address(this);
        IRewardDistributorV3(REWARD_DISTRIBUTOR).claimAllReward(holders);
        uint256 claimedAmount = IERC20(DF).balanceOf(address(this));
        IERC20(DF).safeTransfer(msg.sender, claimedAmount);
    }

    function getBalanceOfUnderlying() external onlyChiefOrOwner() returns (uint256) {
        return IiToken(iSuppliedToken).balanceOfUnderlying(address(this));
    }

    function getBorrowBalanceCurrent() external onlyChiefOrOwner() returns (uint256) {
        return IiToken(iBorrowedToken).borrowBalanceCurrent(address(this));
    }

    function rescueToken(address token) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }

    function rescueNative() external onlyOwner {
        (bool sent, ) = msg.sender.call{value: address(this).balance}("");
        require(sent, "Failed to send Ether");
    }

    /** fallback **/

    receive() external payable {}
}

