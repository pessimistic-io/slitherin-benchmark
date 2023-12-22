// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.16;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IGridFirePayment.sol";

contract GridFirePayment is IGridFirePayment, Initializable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 private serviceFee;
    mapping(address => uint256) private balances;
    IERC20Upgradeable constant dai = IERC20Upgradeable(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);

    function initialize() public initializer {
        __Ownable_init();
        serviceFee = 50;
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function _creditBalances(address artist, uint256 amountPaid) private returns (uint256, uint256) {
        if (amountPaid == 0) {
            return (amountPaid, 0);
        }

        if (serviceFee == 0) {
            balances[artist] += amountPaid;
            return (amountPaid, 0);
        }

        uint256 platformShare = (amountPaid / 1000) * serviceFee;
        uint256 artistShare = amountPaid - platformShare;
        balances[owner()] += platformShare;
        balances[artist] += artistShare;
        return (artistShare, platformShare);
    }

    function _transferEditionPayment(
        address buyer,
        address artist,
        uint256 amountPaid
    ) private returns (uint256, uint256) {
        dai.safeTransferFrom(buyer, address(this), amountPaid);
        (uint256 artistShare, uint256 platformShare) = creditBalances(artist, amountPaid);
        return (artistShare, platformShare);
    }

    function _transferPayment(
        address artist,
        uint256 amountPaid,
        bytes32 releaseId,
        bytes32 userId
    ) private {
        dai.safeTransferFrom(msg.sender, address(this), amountPaid);
        (uint256 artistShare, uint256 platformShare) = creditBalances(artist, amountPaid);
        emit Purchase(msg.sender, artist, releaseId, userId, amountPaid, artistShare, platformShare);
    }

    function claim() public {
        uint256 amount = balances[msg.sender];
        require(amount != 0);
        balances[msg.sender] = 0;
        dai.safeTransfer(msg.sender, amount);
        emit Claim(msg.sender, amount);
    }

    function creditBalances(address artist, uint256 amountPaid) public returns (uint256, uint256) {
        return _creditBalances(artist, amountPaid);
    }

    function checkout(BasketItem[] calldata basket, bytes32 userId) external {
        uint256 total = 0;

        for (uint256 i = 0; i < basket.length; i++) {
            uint256 amountPaid = basket[i].amountPaid;
            total += amountPaid;
        }

        // Ensure the full balance is sent to the contract before calculating shares.
        dai.safeTransferFrom(msg.sender, address(this), total);

        for (uint256 i = 0; i < basket.length; i++) {
            address artist = basket[i].artist;
            uint256 amountPaid = basket[i].amountPaid;
            bytes32 releaseId = basket[i].releaseId;
            (uint256 artistShare, uint256 platformShare) = creditBalances(artist, amountPaid);
            emit Purchase(msg.sender, artist, releaseId, userId, amountPaid, artistShare, platformShare);
        }

        emit Checkout(msg.sender, total);
    }

    function getBalance(address artist) external view returns (uint256) {
        return balances[artist];
    }

    function getServiceFee() external view returns (uint256) {
        return serviceFee;
    }

    function purchase(
        address artist,
        uint256 amountPaid,
        bytes32 releaseId,
        bytes32 userId
    ) external {
        require(artist != address(0) && amountPaid != 0);
        transferPayment(artist, amountPaid, releaseId, userId);
    }

    function setServiceFee(uint256 newServiceFee) external onlyOwner {
        require(newServiceFee < 1000);
        serviceFee = newServiceFee;
    }

    function transferEditionPayment(
        address buyer,
        address artist,
        uint256 amountPaid
    ) external returns (uint256, uint256) {
        require(buyer != address(0) && artist != address(0));
        (uint256 artistShare, uint256 platformShare) = _transferEditionPayment(buyer, artist, amountPaid);
        return (artistShare, platformShare);
    }

    function transferPayment(
        address artist,
        uint256 amountPaid,
        bytes32 releaseId,
        bytes32 userId
    ) public {
        require(artist != address(0));
        require(releaseId.length > 0 && userId.length > 0);
        _transferPayment(artist, amountPaid, releaseId, userId);
    }

    function withdraw() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
}

