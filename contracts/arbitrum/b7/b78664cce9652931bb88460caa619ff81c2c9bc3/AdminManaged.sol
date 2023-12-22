//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./Initializable.sol";
import "./AccessControlDefaultAdminRulesUpgradeable.sol";

abstract contract AdminManaged is Initializable, AccessControlDefaultAdminRulesUpgradeable {
    bytes32 public constant TRANSFER_ROLE = keccak256('TRANSFER_ROLE');
    bytes32 public constant BURNER_ROLE = keccak256('BURNER_ROLE');
    bytes32 public constant APPROVER_ROLE = keccak256('APPROVER_ROLE');
    bytes32 public constant MINTER_ROLE = keccak256('MINTER_ROLE');

    mapping(uint256 => bool) private _isAllowedToTransfer;
    mapping(uint256 => bool) private _isAllowedToBurn;
    mapping(uint256 => bool) private _isAllowedToBurnForHolder;

    function __AdminManaged_init(
        address owner,
        address transfer,
        address burner,
        address minter,
        address approver,
        uint48 delay
    ) internal onlyInitializing {
        __AccessControlDefaultAdminRules_init(delay, owner);

        _grantRole(TRANSFER_ROLE, transfer);
        _grantRole(BURNER_ROLE, burner);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(APPROVER_ROLE, approver);
    }

    function forceTransferFrom(address from, address to, uint256 tokenId) public virtual onlyRole(TRANSFER_ROLE) {
        require(_isAllowedToTransfer[tokenId], 'AdminManaged: not allowed to transfer');
        _approve(msg.sender, tokenId);
        _transferFrom(from, to, tokenId);
    }

    function allowToTransfer(uint256 tokenId) external onlyRole(APPROVER_ROLE) {
        _isAllowedToTransfer[tokenId] = true;
    }

    function denyToTransfer(uint256 tokenId) external onlyRole(APPROVER_ROLE) {
        _isAllowedToTransfer[tokenId] = false;
    }

    function burn(uint256 tokenId) external virtual {
        require(_isAllowedToBurnForHolder[tokenId], 'AdminManaged: not allowed to burn');
        _burn(tokenId);
    }

    function forceBurn(uint256 tokenId) external virtual onlyRole(BURNER_ROLE) {
        require(_isAllowedToBurn[tokenId], 'AdminManaged: not allowed to burn');
        _forceBurn(tokenId);
    }

    function allowToBurn(uint256 tokenId) external onlyRole(APPROVER_ROLE) {
        _isAllowedToBurn[tokenId] = true;
    }

    function denyToBurn(uint256 tokenId) external onlyRole(APPROVER_ROLE) {
        _isAllowedToBurn[tokenId] = false;
    }

    function allowToBurnForHolder(uint256 tokenId) external onlyRole(APPROVER_ROLE) {
        _isAllowedToBurnForHolder[tokenId] = true;
    }

    function denyToBurnForHolder(uint256 tokenId) external onlyRole(APPROVER_ROLE) {
        _isAllowedToBurnForHolder[tokenId] = false;
    }

    function _approve(address to, uint256 tokenId) internal virtual {}

    function _transferFrom(address from, address to, uint256 tokenId) internal virtual {}

    function _burn(uint256 tokenId) internal virtual {}

    function _forceBurn(uint256 tokenId) internal virtual {}

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}

