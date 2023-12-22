//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {IAccessControlHolder, IAccessControl} from "./IAccessControlHolder.sol";
import {IPolisManager, IPolis} from "./IPolisManager.sol";
import {ECDSA} from "./ECDSA.sol";
import {IERC721Receiver} from "./IERC721Receiver.sol";

contract PolisManager is IAccessControlHolder, IPolisManager, IERC721Receiver {
    using ECDSA for bytes32;

    string internal constant UPGRADE_TYPE =
        "upgrade(uint256 tokenId,uint8 level)";

    bytes32 constant POLIS_UPGRADE = keccak256("POLIS_UPGRADE");

    IAccessControl public immutable override acl;
    IPolis public immutable polis;
    mapping(address => uint256) internal _stakedTokens;
    mapping(uint256 => address) internal _stakers;

    modifier onlyTokenOwnerAccess(uint256 tokenId) {
        if (polis.ownerOf(tokenId) != msg.sender) {
            revert OnlyTokenOwnerAccess();
        }
        _;
    }

    modifier onlyOneStakedToken(address wallet) {
        if (_stakedTokens[wallet] != 0) {
            revert OnlyOneTokenStaked();
        }
        _;
    }

    modifier onlyIfTokenLockedByWallet(address wallet, uint256 tokenId) {
        if (_stakedTokens[wallet] != tokenId) {
            revert CannotUnstakeToken();
        }
        _;
    }

    constructor(IAccessControl acl_, IPolis polis_) {
        acl = acl_;
        polis = polis_;
    }

    function upgradeWithSignature(
        uint256 tokenId,
        uint8 level,
        bytes calldata signature
    ) external override {
        bytes32 messageHash = upgradeHash(tokenId, level);
        address signer = messageHash.toEthSignedMessageHash().recover(
            signature
        );
        _ensureHasUpgradeRole(signer);
        if (_stakers[tokenId] != msg.sender) {
            revert OnlyIfStaked();
        }

        polis.upgrade(tokenId, level);
    }

    function unstake(
        uint256 tokenId
    ) external override onlyIfTokenLockedByWallet(msg.sender, tokenId) {
        polis.safeTransferFrom(address(this), msg.sender, tokenId);

        delete _stakedTokens[msg.sender];
        delete _stakers[tokenId];

        emit Unstaked(msg.sender, tokenId);
    }

    function stake(
        uint256 tokenId
    ) external override onlyOneStakedToken(msg.sender) {
        polis.safeTransferFrom(msg.sender, address(this), tokenId);

        _stakedTokens[msg.sender] = tokenId;
        _stakers[tokenId] = msg.sender;

        emit Staked(msg.sender, tokenId);
    }

    function stakedByWallet(
        address wallet
    ) external view override returns (uint256) {
        uint256 tokenId = _stakedTokens[wallet];
        if (tokenId == 0) {
            revert NotStakedToken();
        }

        return tokenId;
    }

    function staker(uint256 tokenId) external view override returns (address) {
        address _staker = _stakers[tokenId];
        if (_staker == address(0)) {
            revert NotStakedToken();
        }
        return _staker;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function upgradeHash(
        uint256 tokenId,
        uint8 level
    ) public view override returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    uint16(0x1901),
                    _domainSeperator(),
                    keccak256(abi.encode(UPGRADE_TYPE, tokenId, level))
                )
            );
    }

    function _domainSeperator() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,uint256 signedAt)"
                    ),
                    keccak256(bytes("Sparta")),
                    keccak256(bytes("1")),
                    _chainId(),
                    address(this),
                    keccak256(bytes("Sparta"))
                )
            );
    }

    function _chainId() internal view returns (uint256 chainId_) {
        assembly {
            chainId_ := chainid()
        }
    }

    function _ensureHasUpgradeRole(address addr) internal view {
        if (!acl.hasRole(POLIS_UPGRADE, addr)) {
            revert OnlyUpgradeRoleAccess();
        }
    }
}

