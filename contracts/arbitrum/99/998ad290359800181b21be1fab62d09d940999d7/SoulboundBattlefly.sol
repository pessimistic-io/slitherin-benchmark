// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./ERC721EnumerableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./ERC721Upgradeable.sol";
import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./MerkleProofUpgradeable.sol";
import "./draft-EIP712Upgradeable.sol";
import "./IERC165Upgradeable.sol";

import "./ISoulboundBattlefly.sol";
import "./IBattleflyGame.sol";

//MMMMWKl.                                            .:0WMMMM//
//MMMWk,                                                .dNMMM//
//MMNd.                                                  .lXMM//
//MWd.    .','''....                         .........    .lXM//
//Wk.     ';......'''''.                ..............     .dW//
//K;     .;,         ..,'.            ..'..         ...     'O//
//d.     .;;.           .''.        ..'.            .'.      c//
//:       .','.           .''.    ..'..           ....       '//
//'         .';.            .''...'..           ....         .//
//.           ';.             .''..             ..           .//
//.            ';.                             ...           .//
//,            .,,.                           .'.            .//
//c             .;.                           '.             ;//
//k.            .;.             .             '.            .d//
//Nl.           .;.           .;;'            '.            :K//
//MK:           .;.          .,,',.           '.           'OW//
//MM0;          .,,..       .''  .,.       ...'.          'kWM//
//MMMK:.          ..'''.....'..   .'..........           ,OWMM//
//MMMMXo.             ..'...        ......             .cKMMMM//
//MMMMMWO:.                                          .,kNMMMMM//
//MMMMMMMNk:.                                      .,xXMMMMMMM//
//MMMMMMMMMNOl'.                                 .ckXMMMMMMMMM//

contract SoulboundBattlefly is
    Initializable,
    ERC721EnumerableUpgradeable,
    EIP712Upgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    ISoulboundBattlefly
{
    using StringsUpgradeable for uint256;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
    bytes32 public constant BATTLEFLY_BOT_ROLE = keccak256("BATTLEFLY_BOT");
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN");

    uint256 public override currentId;
    uint256 public override battleflyTypeCounter;
    bool public paused;

    IBattleflyGame public override game;

    mapping(uint256 => bytes32) merklerootForType;
    mapping(uint256 => bool) isTypeActive;
    mapping(uint256 => mapping(address => uint256)) mintedForType;
    mapping(bytes => bool) consumedMints;
    mapping(bytes32 => mapping(uint256 => bool)) consumedWhitelistMints;
    mapping(uint256 => address) soulboundMapping;
    mapping(address => bool) whitelistedAddresses;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address admin,
        address signer,
        address battleflyBot,
        address guardian,
        address game_
    ) public initializer {
        __ERC721_init("Soulbound Battlefly", "SLBND_BF");
        __EIP712_init("Soulbound Battlefly", "1.0.0");
        __ERC721Enumerable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        paused = true;

        if (admin == address(0)) revert InvalidAddress(admin);
        if (signer == address(0)) revert InvalidAddress(signer);
        if (battleflyBot == address(0)) revert InvalidAddress(battleflyBot);
        if (guardian == address(0)) revert InvalidAddress(guardian);
        if (game_ == address(0)) revert InvalidAddress(game_);
        game = IBattleflyGame(game_);

        whitelistedAddresses[address(this)] = true;

        _setupRole(ADMIN_ROLE, admin);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setupRole(SIGNER_ROLE, signer);
        _setRoleAdmin(SIGNER_ROLE, ADMIN_ROLE);
        _setupRole(BATTLEFLY_BOT_ROLE, battleflyBot);
        _setRoleAdmin(BATTLEFLY_BOT_ROLE, ADMIN_ROLE);
        _setupRole(GUARDIAN_ROLE, guardian);
        _setupRole(GUARDIAN_ROLE, admin);
        _setRoleAdmin(GUARDIAN_ROLE, ADMIN_ROLE);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert UnexistingToken(tokenId);
        return
            string(abi.encodePacked("https://alpha-graph.battlefly.game/soulbounds/", tokenId.toString(), "/metadata"));
    }

    function mint(bool stake, bytes calldata data) external nonReentrant whenNotPaused {
        (uint256 amount, uint256 battleflyType, uint256 transactionId, bytes memory signature) = abi.decode(
            data,
            (uint256, uint256, uint256, bytes)
        );
        if (battleflyType == 0 || battleflyType > battleflyTypeCounter) revert InvalidBattleflyType(battleflyType);
        if (!isTypeActive[battleflyType]) revert TypeNotActive(battleflyType);
        if (consumedMints[signature]) revert AlreadyMinted(signature);
        if (!_verify(_hash(msg.sender, amount, battleflyType, transactionId), signature))
            revert InvalidSignature(signature);
        consumedMints[signature] = true;
        mintedForType[battleflyType][msg.sender] += amount;
        for (uint256 i = currentId; i < (currentId + amount); ) {
            unchecked {
                ++i;
            }
            soulboundMapping[i] = msg.sender;
            if (stake) {
                _mint(address(this), i);
                _approve(address(game), i);
                game.stakeSoulbound(msg.sender, i);
            } else {
                _mint(msg.sender, i);
            }
            emit Minted(msg.sender, i, battleflyType, stake);
        }
        currentId += amount;
    }

    function mintWhitelist(
        uint256 index,
        address account,
        uint256 amount,
        uint256 battleflyType,
        bool stake,
        bytes32[] calldata merkleProof
    ) external nonReentrant whenNotPaused {
        if (battleflyType == 0 || battleflyType > battleflyTypeCounter) revert InvalidBattleflyType(battleflyType);
        uint256 totalMintedForType = mintedForType[battleflyType][msg.sender];
        bytes32 merkleroot = merklerootForType[battleflyType];
        if (!isTypeActive[battleflyType]) revert TypeNotActive(battleflyType);
        if (consumedWhitelistMints[merkleroot][index]) revert AlreadyMintedWhitelist(index, merkleroot);
        if (totalMintedForType >= amount) revert AlreadyMintedFullAllocationForWhitelist(account, battleflyType);
        bytes32 node = keccak256(abi.encodePacked(index, account, amount, battleflyType));
        if (!MerkleProofUpgradeable.verify(merkleProof, merkleroot, node)) revert InvalidProof();
        uint256 toMint = amount - totalMintedForType;
        consumedWhitelistMints[merkleroot][index] = true;
        mintedForType[battleflyType][msg.sender] += toMint;
        for (uint256 i = currentId; i < (currentId + toMint); ) {
            unchecked {
                ++i;
            }
            soulboundMapping[i] = msg.sender;
            if (stake) {
                _mint(address(this), i);
                _approve(address(game), i);
                game.stakeSoulbound(msg.sender, i);
            } else {
                _mint(msg.sender, i);
            }
            emit MintedWhitelist(msg.sender, i, battleflyType, stake);
        }
        currentId += toMint;
    }

    function setMerklerootForType(uint256 battleflyType, bytes32 merkleRoot) external onlyBattleflyBot {
        if (battleflyType == 0 || battleflyType > battleflyTypeCounter) revert InvalidBattleflyType(battleflyType);
        merklerootForType[battleflyType] = merkleRoot;
        emit MerklerootForTypeSet(battleflyType, merkleRoot);
    }

    function addType() external onlyBattleflyBot whenNotPaused {
        battleflyTypeCounter++;
        emit TypeAdded(battleflyTypeCounter);
    }

    function setTypeStatus(uint256 battleflyType, bool status) external onlyBattleflyBot {
        if (battleflyType == 0 || battleflyType > battleflyTypeCounter) revert InvalidBattleflyType(battleflyType);
        isTypeActive[battleflyType] = status;
        emit TypeStatusSet(battleflyType, status);
    }

    function setPaused(bool status) external onlyGuardian {
        paused = status;
        emit Paused(status);
    }

    function whitelistReceiverAddress(address account, bool status) external onlyAdmin {
        whitelistedAddresses[account] = status;
        emit ReceiverAddressWhitelisted(account, status);
    }

    function isWhitelistedReceiverAddress(address account) external view returns (bool) {
        return whitelistedAddresses[account];
    }

    function getMerklerootForType(uint256 battleflyType) external view returns (bytes32) {
        return merklerootForType[battleflyType];
    }

    function isActiveType(uint256 battleflyType) external view returns (bool) {
        return isTypeActive[battleflyType];
    }

    function _verify(bytes32 digest, bytes memory signature) internal view returns (bool) {
        return hasRole(SIGNER_ROLE, ECDSAUpgradeable.recover(digest, signature));
    }

    function _hash(
        address minter,
        uint256 amount,
        uint256 battleflyType,
        uint256 transactionId
    ) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256("Mint(uint256 amount,address minter,uint256 battleflyType,uint256 transactionId)"),
                        amount,
                        minter,
                        battleflyType,
                        transactionId
                    )
                )
            );
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override {
        if (!whitelistedAddresses[to] && soulboundMapping[firstTokenId] != to)
            revert TransferNotAllowed(from, to, firstTokenId);
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    // The following functions are overrides required by Solidity.

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(AccessControlUpgradeable, ERC721EnumerableUpgradeable, IERC165Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    modifier onlyAdmin() {
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert AccessDenied();
        _;
    }

    modifier onlyBattleflyBot() {
        if (!hasRole(BATTLEFLY_BOT_ROLE, msg.sender)) revert AccessDenied();
        _;
    }

    modifier onlySigner() {
        if (!hasRole(SIGNER_ROLE, msg.sender)) revert AccessDenied();
        _;
    }

    modifier onlyGuardian() {
        if (!hasRole(GUARDIAN_ROLE, msg.sender)) revert AccessDenied();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }
}

