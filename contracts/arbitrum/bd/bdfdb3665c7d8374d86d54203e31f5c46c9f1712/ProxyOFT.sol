// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./OFTCore.sol";
import "./SafeERC20.sol";

contract ProxyOFT is OFTCore {
    using SafeERC20 for IERC20;

    IERC20 internal immutable innerToken;
    address feeAdmin;
    mapping(address => uint256) public transferredBalances;
    uint256 fee = 5 * 10 ** 14;

    event WithdrawEth(address user, uint256 amount);
    event UpdateEthFee(address user, uint256 newFee, uint256 oldFee);

    error WithdrawFailed();

    modifier onlyAdmin() {
        require(feeAdmin == msg.sender, "Admin: caller is not the Admin");
        _;
    }

    constructor(address _lzEndpoint, address _token) OFTCore(_lzEndpoint) {
        innerToken = IERC20(_token);
        feeAdmin = msg.sender;
    }

    function circulatingSupply() public view virtual override returns (uint) {
    unchecked {
        return innerToken.totalSupply() - innerToken.balanceOf(address(this));
    }
    }

    function token() public view virtual override returns (address) {
        return address(innerToken);
    }

    function _debitFrom(address _from, uint16, bytes memory, uint _amount) internal virtual override returns (uint) {
        require(_from == _msgSender(), "ProxyOFT: owner is not send caller");
        uint before = innerToken.balanceOf(address(this));
        innerToken.safeTransferFrom(_from, address(this), _amount);
        return innerToken.balanceOf(address(this)) - before;
    }

    function _creditTo(uint16, address _toAddress, uint _amount) internal virtual override returns (uint) {
        uint before = innerToken.balanceOf(_toAddress);
        innerToken.safeTransfer(_toAddress, _amount);
        return innerToken.balanceOf(_toAddress) - before;
    }

    function _send(address _from, uint16 _dstChainId, bytes memory _toAddress, uint _amount, address payable _refundAddress, address _zroPaymentAddress, bytes memory _adapterParams) internal virtual override {
        _checkAdapterParams(_dstChainId, PT_SEND, _adapterParams, NO_EXTRA_GAS);

        uint amount = _debitFrom(_from, _dstChainId, _toAddress, _amount);
        transferredBalances[_from] += amount;

        bytes memory lzPayload = abi.encode(PT_SEND, _toAddress, amount);
        _lzSend(_dstChainId, lzPayload, _refundAddress, _zroPaymentAddress, _adapterParams, msg.value - fee);

        emit SendToChain(_dstChainId, _from, _toAddress, amount);
    }

    function withdrawEth(uint256 amount) external onlyAdmin {

        require(address(this).balance >= amount, "Insufficient balance");
        (bool success,) = payable(msg.sender).call{value : amount}("");
        if (!success) {
            revert WithdrawFailed();
        }
        emit WithdrawEth(msg.sender, amount);
    }

    function updateEthFee(uint256 newFee) external onlyAdmin {

        uint256 oldFee = fee;
        fee = newFee;
        emit UpdateEthFee(msg.sender, newFee, oldFee);
    }

    function transferAdmin(address newOwner) external onlyAdmin {
        address oldOwner = feeAdmin;
        feeAdmin = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

