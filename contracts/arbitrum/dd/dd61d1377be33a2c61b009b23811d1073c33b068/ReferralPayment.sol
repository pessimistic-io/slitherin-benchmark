// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import { ECDSAUpgradeable } from "./ECDSAUpgradeable.sol";
import { AddressUpgradeable } from "./AddressUpgradeable.sol";
import { SafeMathUpgradeable } from "./SafeMathUpgradeable.sol";
import { SafeERC20Upgradeable, IERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { TransferHelper } from "./TransferHelper.sol";
import { OwnerPausable } from "./OwnerPausable.sol";
import { BlockContext } from "./BlockContext.sol";
import { IReferralPayment } from "./IReferralPayment.sol";
import { ReferralPaymentStorage } from "./ReferralPaymentStorage.sol";

// never inherit any new stateful contract. never change the orders of parent stateful contracts
contract ReferralPayment is IReferralPayment, BlockContext, OwnerPausable, ReferralPaymentStorage {
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;

    event Paid(address indexed user, uint256 amountPNFT, uint256 amountETH);

    receive() external payable {}

    modifier checkDeadline(uint256 deadline) {
        require(_blockTimestamp() <= deadline, "RP_TE");
        _;
    }

    //
    // EXTERNAL NON-VIEW
    //
    /// @dev this function is public for testing
    // solhint-disable-next-line func-order
    function initialize(address pnftTokenArg, address adminArg) public initializer {
        __OwnerPausable_init();
        //
        _pnftToken = pnftTokenArg;
        _admin = adminArg;
    }

    function _isContract(address contractArg, string memory errorMsg) internal view {
        require(contractArg.isContract(), errorMsg);
    }

    function setAdmin(address adminArg) external {
        _admin = adminArg;
    }

    function getAdmin() external view returns (address admin) {
        admin = _admin;
    }

    function getUserPayment(address user) external view returns (uint256 lastPNFTPayment, uint256 lastETHPayment) {
        lastPNFTPayment = _lastPNFTPayments[user];
        lastETHPayment = _lastETHPayments[user];
    }

    function getMessageHash(
        address user,
        uint256 totalPNFT,
        uint256 totalETH,
        uint256 deadline
    ) public view returns (bytes32) {
        return keccak256(abi.encode(address(this), _admin, user, totalPNFT, totalETH, deadline));
    }

    function _verifySigner(
        address user,
        uint256 totalPNFT,
        uint256 totalETH,
        uint256 deadline,
        bytes memory signature
    ) internal view returns (address, bytes32) {
        bytes32 messageHash = getMessageHash(user, totalPNFT, totalETH, deadline);
        address signer = ECDSAUpgradeable.recover(ECDSAUpgradeable.toEthSignedMessageHash(messageHash), signature);
        // RP_NA: Signer Is Not ADmin
        require(signer == _admin, "RP_NA");
        return (signer, messageHash);
    }

    function claim(
        address user,
        uint256 totalPNFT,
        uint256 totalETH,
        uint256 deadline,
        bytes memory signature
    ) external override checkDeadline(deadline) {
        _verifySigner(user, totalPNFT, totalETH, deadline, signature);
        // RP_ZA: invaild amount
        require(totalPNFT >= _lastPNFTPayments[user], "RP_IA");
        require(totalETH >= _lastETHPayments[user], "RP_IA");
        uint256 amountPNFT = totalPNFT.sub(_lastPNFTPayments[user]);
        uint256 amountETH = totalETH.sub(_lastETHPayments[user]);
        if (amountPNFT > 0) {
            SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(_pnftToken), user, amountPNFT);
        }
        if (amountETH > 0) {
            TransferHelper.safeTransferETH(user, amountETH);
        }
        _lastPNFTPayments[user] = totalPNFT;
        _lastETHPayments[user] = totalETH;
        emit Paid(user, amountPNFT, amountETH);
    }

    function emergencyWithdrawPNFT(uint256 amount) external onlyOwner {
        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(_pnftToken), _msgSender(), amount);
    }

    function emergencyWithdrawETH(uint256 amount) external onlyOwner {
        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(_pnftToken), _msgSender(), amount);
    }
}

