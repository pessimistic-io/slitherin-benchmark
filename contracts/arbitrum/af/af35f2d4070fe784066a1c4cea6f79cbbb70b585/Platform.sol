// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Pausable.sol";
import "./OFTV2.sol";

// This contract is extended from OFTV2
contract MintsCoin is OFTV2, Pausable {
    mapping(address => bool) public blacklist;
    bool private _transferPaused;

    constructor(
        string memory _name,
        string memory _symbol,
        address _endpoint,
        address _owner,
        uint256 _mintAmt
    ) OFTV2(_name, _symbol, 8, _endpoint) {
        _transferPaused = false;

        if (_mintAmt != 0) {
            _mint(_owner, _mintAmt);
        }
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(_transferPaused == false, "transfer is not open");
        require(
            blacklist[msg.sender] == false,
            "black address cannot transfer"
        );
        super._transfer(from, to, amount);
    }

    function burn(uint256 _amount) public {
        _burn(_msgSender(), _amount);
    }

    function setTransferPause(bool _newPaused) external onlyOwner {
        _transferPaused = _newPaused;
    }

    function tansferPause() external view onlyOwner returns (bool) {
        return _transferPaused;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @notice Returns LZ fee
     * @dev overrides default OFT _send function to add native fee
     * @param _from from addr
     * @param _dstChainId dest LZ chain id
     * @param _toAddress to addr on dst chain
     * @param _amount amount to bridge
     * @param _refundAddress refund addr
     * @param _zroPaymentAddress use ZRO token, someday ;)
     * @param _adapterParams LZ adapter params
     */
    function _send(
        address _from,
        uint16 _dstChainId,
        bytes32 _toAddress,
        uint _amount,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams
    ) internal override whenNotPaused returns (uint) {
        return
            super._send(
                _from,
                _dstChainId,
                _toAddress,
                _amount,
                _refundAddress,
                _zroPaymentAddress,
                _adapterParams
            );
    }

    /**
     * @notice overrides default OFT _debitFrom function to make pauseable
     * @param _from from addr
     * @param _dstChainId dest LZ chain id
     * @param _toAddress to addr on dst chain
     * @param _amount amount to bridge
     */
    function _debitFrom(
        address _from,
        uint16 _dstChainId,
        bytes32 _toAddress,
        uint _amount
    ) internal override whenNotPaused onlyOwner returns (uint) {
        return super._debitFrom(_from, _dstChainId, _toAddress, _amount);
    }

    function uploadBlacklist(address blackAddr) external onlyOwner {
        require(blackAddr != address(0x0), "cannot zero address");
        blacklist[blackAddr] = true;
    }
}

