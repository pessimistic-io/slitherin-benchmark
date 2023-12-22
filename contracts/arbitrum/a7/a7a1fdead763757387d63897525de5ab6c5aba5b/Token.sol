// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AccessControlEnumerable.sol";
import "./Pausable.sol";
import "./OFT.sol";

contract FapCoin is OFT, Pausable, AccessControlEnumerable {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    address public minter;

    constructor(
        address _layerZeroEndpoint,
        address _admin,
        address _pauser,
        address _minter
    ) OFT("FapCoin", "FAP", _layerZeroEndpoint) {
        _transferOwnership(_admin);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _pauser);
        _grantRole(MINTER_ROLE, _minter);

        minter = _minter;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(AccessControlEnumerable, OFT) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _debitFrom(
        address _from,
        uint16 _dstChainId,
        bytes memory _toAddress,
        uint _amount
    ) internal override whenNotPaused returns (uint) {
        return super._debitFrom(_from, _dstChainId, _toAddress, _amount);
    }

    function pauseSendTokens(bool pause) external onlyRole(PAUSER_ROLE) {
        pause ? _pause() : _unpause();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {}

    function setMinter(address _minter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(MINTER_ROLE, minter);
        grantRole(MINTER_ROLE, _minter);
        minter = _minter;
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burn(uint256 value) external {
        _burn(msg.sender, value);
    }
}

