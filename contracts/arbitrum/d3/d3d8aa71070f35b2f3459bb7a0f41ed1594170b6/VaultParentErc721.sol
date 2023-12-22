// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { VaultParentInternal } from "./VaultParentInternal.sol";

import { Constants } from "./Constants.sol";

import { SolidStateERC721, ERC721BaseInternal } from "./SolidStateERC721.sol";

import { ITransport } from "./ITransport.sol";
import { Registry } from "./Registry.sol";
import { RegistryStorage } from "./RegistryStorage.sol";
import { VaultParentStorage } from "./VaultParentStorage.sol";
import { VaultParentInternal } from "./VaultParentInternal.sol";
import { VaultBaseInternal } from "./VaultBaseInternal.sol";
import { VaultOwnershipInternal } from "./VaultOwnershipInternal.sol";
import { VaultRiskProfile } from "./IVaultRiskProfile.sol";

import { IERC165 } from "./IERC165.sol";
import { IERC721 } from "./IERC721.sol";

contract VaultParentErc721 is SolidStateERC721, VaultParentInternal {
    function initialize(
        string memory _name,
        string memory _symbol,
        address _manager,
        uint _managerStreamingFeeBasisPoints,
        uint _managerPerformanceFeeBasisPoints,
        VaultRiskProfile _riskProfile,
        Registry _registry
    ) external {
        require(_vaultId() == 0, 'already initialized');

        bytes32 vaultId = keccak256(
            abi.encodePacked(_registry.chainId(), address(this))
        );
        _setVaultId(vaultId);
        _setHasNotBridged(true);
        VaultBaseInternal.initialize(_registry, _manager, _riskProfile);
        VaultOwnershipInternal.initialize(
            _name,
            _symbol,
            _manager,
            _managerStreamingFeeBasisPoints,
            _managerPerformanceFeeBasisPoints,
            _registry.protocolTreasury()
        );

        _setSupportsInterface(type(IERC165).interfaceId, true);
        _setSupportsInterface(type(IERC721).interfaceId, true);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(SolidStateERC721, VaultParentInternal) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    /**
     * @notice ERC721 hook: revert if value is included in external approve function call
     * @inheritdoc ERC721BaseInternal
     */
    function _handleApproveMessageValue(
        address operator,
        uint256 tokenId,
        uint256 value
    ) internal virtual override(SolidStateERC721, ERC721BaseInternal) {
        if (value > 0) revert SolidStateERC721__PayableApproveNotSupported();
        super._handleApproveMessageValue(operator, tokenId, value);
    }

    /**
     * @notice ERC721 hook: revert if value is included in external transfer function call
     * @inheritdoc ERC721BaseInternal
     */
    function _handleTransferMessageValue(
        address from,
        address to,
        uint256 tokenId,
        uint256 value
    ) internal virtual override(SolidStateERC721, ERC721BaseInternal) {
        if (value > 0) revert SolidStateERC721__PayableTransferNotSupported();
        super._handleTransferMessageValue(from, to, tokenId, value);
    }
}

