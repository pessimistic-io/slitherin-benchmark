// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC1155Receiver.sol";
import "./IERC721Receiver.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";

import "./IDepositHandler.sol";
import "./IVault.sol";
import "./IVaultFactory.sol";
import "./IVaultKey.sol";

contract Vault is ReentrancyGuard, IDepositHandler, IVault, IERC721Receiver, IERC1155Receiver {
    IVaultFactory public immutable vaultFactoryContract;
    IVaultKey public immutable vaultKeyContract;
    uint256 public override vaultKeyId;
    address public immutable initialBeneficiary;
    address public immutable vaultDeployer;

    uint256 public immutable lockTimestamp;
    uint256 public unlockTimestamp;
    bool public isUnlocked;

    modifier onlyKeyHolder() {
        require(getBeneficiary() == msg.sender, "Vault:onlyKeyHolder:UNAUTHORIZED");
        _;
    }

    modifier onlyUnlockable() {
        require(block.timestamp >= unlockTimestamp, "Vault:onlyUnlockable:PREMATURE");
        _;
    }

    constructor(
        address _vaultFactory,
        address _vaultKeyContractAddress,
        uint256 _vaultKeyId,
        address _beneficiary,
        uint256 _unlockTimestamp
    ) {
        vaultFactoryContract = IVaultFactory(_vaultFactory);
        vaultKeyContract = IVaultKey(_vaultKeyContractAddress);
        vaultKeyId = _vaultKeyId;
        initialBeneficiary = _beneficiary;

        lockTimestamp = block.timestamp;
        unlockTimestamp = _unlockTimestamp;
        isUnlocked = false;
        vaultDeployer = msg.sender;
    }

    function extendLock(uint256 newUnlockTimestamp) external onlyKeyHolder nonReentrant {
        require(!isUnlocked, "Vault:extendLock:FULLY_UNLOCKED");
        require(newUnlockTimestamp > unlockTimestamp, "Vault:extendLock:INVALID_TIMESTAMP");
        uint256 oldUnlockTimestamp = unlockTimestamp;
        unlockTimestamp = newUnlockTimestamp;
        vaultFactoryContract.lockExtended(oldUnlockTimestamp, newUnlockTimestamp);
    }

    function getBeneficiary() public view override returns (address) {
        if (vaultKeyId > 0) return vaultKeyContract.ownerOf(vaultKeyId);
        return initialBeneficiary;
    }

    function mintKey() external onlyKeyHolder nonReentrant {
        require(vaultKeyId == 0, "StakingVault:mintKey:KEY_ALREADY_MINTED");
        address beneficiary = getBeneficiary();
        uint256 totalSupply = vaultKeyContract.totalSupply();
        uint256 lastTokenId = vaultKeyContract.tokenByIndex(totalSupply - 1);
        vaultKeyId = lastTokenId + 1;
        vaultKeyContract.mintKey(beneficiary);
        require(vaultKeyId == vaultKeyContract.lastMintedKeyId(beneficiary), "Invalid minted Token ID");
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId;
    }
}

