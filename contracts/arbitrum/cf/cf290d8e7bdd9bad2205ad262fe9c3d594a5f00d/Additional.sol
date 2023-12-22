// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./OwnableUpgradeable.sol";

abstract contract Additional is OwnableUpgradeable {
    uint16 internal _commission;
    address private _feeWallet;
    address private _refundWallet;
    address private _signerRole;
    address private _adminRole;
    address internal _superAdmin;

    event CommissionChanged(uint16 indexed previousCommission, uint16 indexed newCommission);
    event FeeWalletChanged(address indexed previousFeeWallet, address indexed newFeeWallet);
    event SignerRoleChanged(address indexed previousSignerRole, address indexed newSignerRole);
    event AdminRoleChanged(address indexed previousAdmin, address indexed newAdmin);
    event RefundFeeWalletChanged(address indexed previousRefundFeeWallet, address indexed newRefundFeeWallet);
    event SuperAdminRoleChanged(address indexed previousSuperAdmin, address indexed newSuperAdmin);

    modifier onlyAdmin() {
        require(_adminRole == _msgSender(), "KR: Caller is not the admin");
        _;
    }

    modifier onlySuperAdmin() {
        require(_superAdmin == _msgSender(), "KR: Caller is not the super admin");
        _;
    }

    /**
     * @dev Returns the commission on the contract.
     */
    function getCommission() external view returns (uint16) {
        return _commission;
    }

    /**
     * @dev Returns the address of the current fee wallet.
     */
    function getFeeWallet() external view returns (address) {
        return _feeWallet;
    }

    /**
     * @dev Returns the address of the current fee wallet.
     */
    function feeWallet() internal view returns (address payable) {
        return payable(_feeWallet);
    }

    /**
     * @dev Returns the address of the current admin wallet.
     */
    function adminRole() public view returns (address) {
        return _adminRole;
    }

    /**
     * @dev Returns the address of the current backend wallet.
     */
    function signerRole() public view returns (address) {
        return _signerRole;
    }

    /**
     * @dev Change commission of the contract to a new value.
     * Can only be called by the current admin.
     */
    function changeCommission(uint16 commission_) public onlySuperAdmin {
        emit CommissionChanged(_commission, commission_);
        _commission = commission_;
    }

    /**
     * @dev Change fee wallet of the contract to a new account (`newFeeWallet`).
     * Can only be called by the current owner.
     */
    function changeFeeWallet(address newFeeWallet) public onlySuperAdmin {
        require(newFeeWallet != address(0), "KR: new fee wallet is the zero address");
        emit FeeWalletChanged(_feeWallet, newFeeWallet);
        _feeWallet = newFeeWallet;
    }

    /**
     * @dev Change signer wallet of the contract to a new account.
     * Can only be called by the current owner.
     */
    function changeSignerRole(address newSignerRole) public onlySuperAdmin {
        require(newSignerRole != address(0), "KR: new signer wallet is the zero address");
        emit SignerRoleChanged(_signerRole, newSignerRole);
        _signerRole = newSignerRole;
    }

    /**
     * @dev Change admin wallet of the contract to a new account.
     * Can only be called by the current owner.
     */
    function changeAdminRole(address newAdminRole) public onlySuperAdmin {
        require(newAdminRole != address(0), "KR: new admin wallet is the zero address");
        emit AdminRoleChanged(_adminRole, newAdminRole);
        _adminRole = newAdminRole;
    }

    function getFeeValue(uint price) external view returns(uint, uint) {
        uint fee = _getFee(price);
        return (fee,  price - fee);
    }

    function _getFee(uint price) internal view returns(uint) {
        return price * _commission / 10000;
    }

    function changeRefundFeeWallet(address newRefundFeeWallet) public onlySuperAdmin {
        require(newRefundFeeWallet != address(0), "KR: new refund fee wallet is the zero address");
        emit RefundFeeWalletChanged(_refundWallet, newRefundFeeWallet);
        _refundWallet = newRefundFeeWallet;
    }

    function getRefundFeeWallet() public view returns(address) {
        return _refundWallet;
    }

    function changeSuperAdminRole(address newSuperAdminRole) public onlySuperAdmin {
        require(newSuperAdminRole != address(0), "KR: new super admin wallet is the zero address");
        emit SuperAdminRoleChanged(_superAdmin, newSuperAdminRole);
        _superAdmin = newSuperAdminRole;
    }

    function getSuperAdminRole() public view returns(address) {
        return _superAdmin;
    }
}

