// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ERC1155Upgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ERC1155SupplyUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import "./IBattleflyFounderVault.sol";
import "./IBattleflyStaker.sol";
import "./IBattleflyComic.sol";

contract BattleflyComic is
    ERC1155Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC1155SupplyUpgradeable,
    IBattleflyComic
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public currentComicId;

    IBattleflyFounderVault public FounderVaultV1;
    IBattleflyFounderVault public FounderVaultV2;
    IBattleflyStaker public BattleflyStaker;
    IERC20Upgradeable public Magic;

    mapping(uint256 => Comic) public comicIdToComic;
    mapping(uint256 => mapping(uint256 => bool)) public usedTokens;
    mapping(uint256 => mapping(address => uint256)) public paidMints;
    mapping(address => bool) public admins;

    function initialize(
        address _magic,
        address _founderVaultV1,
        address _founderVaultV2,
        address _battleflyStake
    ) external initializer {
        __ERC1155_init("");
        __Ownable_init();
        __ReentrancyGuard_init();
        __ERC1155Supply_init();

        require(_magic != address(0), "BattleflyComic: invalid address");
        require(_founderVaultV1 != address(0), "BattleflyComic: invalid address");
        require(_founderVaultV2 != address(0), "BattleflyComic: invalid address");
        require(_battleflyStake != address(0), "BattleflyComic: invalid address");

        admins[msg.sender] = true;

        Magic = IERC20Upgradeable(_magic);
        FounderVaultV1 = IBattleflyFounderVault(_founderVaultV1);
        FounderVaultV2 = IBattleflyFounderVault(_founderVaultV2);
        BattleflyStaker = IBattleflyStaker(_battleflyStake);
    }

    // ---------------- Public methods ----------------- //

    /**
     * @dev Mint comic(s) with staked founders tokens.
     */
    function mintFounders(uint256[] memory tokenIds, uint256 id) public override nonReentrant {
        require(comicIdToComic[id].active, "BattleflyComic: This comic cannot be minted as it is currently paused");
        require(
            comicIdToComic[id].mintType == 1,
            "BattleflyComic: This comic cannot be minted by using founders tokens"
        );
        require(
            comicIdToComic[id].maxMints == 0 || totalSupply(id) + tokenIds.length <= comicIdToComic[id].maxMints,
            "BattleflyComic: Max amount of mints reached for this comic"
        );
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                FounderVaultV1.isOwner(msg.sender, tokenIds[i]) || FounderVaultV2.isOwner(msg.sender, tokenIds[i]),
                "BattleflyComic: Founders token not staked by minter"
            );
            require(!usedTokens[id][tokenIds[i]], "BattleflyComic: Founders token cannot be used twice for minting");
        }
        _mint(msg.sender, id, tokenIds.length, "");
        emit MintComicWithFounder(msg.sender, id, tokenIds);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            usedTokens[id][tokenIds[i]] = true;
        }
    }

    /**
     * @dev Mint comic(s) with staked battlefly tokens.
     */
    function mintBattlefly(uint256[] memory tokenIds, uint256 id) public override nonReentrant {
        require(comicIdToComic[id].active, "BattleflyComic: This comic cannot be minted as it is currently paused");
        require(
            comicIdToComic[id].mintType == 2,
            "BattleflyComic: This comic cannot be minted by using battlefly tokens"
        );
        require(
            comicIdToComic[id].maxMints == 0 || totalSupply(id) + tokenIds.length <= comicIdToComic[id].maxMints,
            "BattleflyComic: Max amount of mints reached for this comic"
        );
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                BattleflyStaker.ownerOf(tokenIds[i]) == msg.sender,
                "BattleflyComic: Battlefly token not staked by minter"
            );
            require(!usedTokens[id][tokenIds[i]], "BattleflyComic: Battlefly token cannot be used twice for minting");
        }
        _mint(msg.sender, id, tokenIds.length, "");
        emit MintComicWithBattlefly(msg.sender, id, tokenIds);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            usedTokens[id][tokenIds[i]] = true;
        }
    }

    /**
     * @dev Mint comic(s) by paying Magic.
     */
    function mintPaid(uint256 amount, uint256 id) public override nonReentrant {
        require(comicIdToComic[id].active, "BattleflyComic: This comic cannot be minted as it is currently paused");
        require(
            comicIdToComic[id].mintType == 1 || comicIdToComic[id].mintType == 2,
            "BattleflyComic: This comic cannot be minted as paid mint"
        );
        require(
            comicIdToComic[id].maxMints == 0 || totalSupply(id) + amount <= comicIdToComic[id].maxMints,
            "BattleflyComic: Max amount of mints reached for this comic"
        );
        require(
            comicIdToComic[id].maxPaidMintsPerWallet == 0 ||
                paidMints[id][msg.sender] + amount <= comicIdToComic[id].maxPaidMintsPerWallet,
            "BattleflyComic: Max mints per address for this comic reached"
        );
        require(
            Magic.balanceOf(msg.sender) >= (amount * comicIdToComic[id].priceInWei),
            "BattleflyComic: Not enough MAGIC in wallet"
        );
        Magic.transferFrom(msg.sender, address(this), amount * comicIdToComic[id].priceInWei);
        _mint(msg.sender, id, amount, "");
        emit MintComicWithPayment(msg.sender, id, amount);
        paidMints[id][msg.sender] = paidMints[id][msg.sender] + amount;
    }

    /**
     * @dev Mint comic(s) by burning other comics.
     */
    function burn(
        uint256 burnId,
        uint256 amount,
        uint256 mintId
    ) public override nonReentrant {
        require(comicIdToComic[mintId].active, "BattleflyComic: This comic cannot be minted as it is currently paused");
        require(comicIdToComic[mintId].mintType == 3, "BattleflyComic: This comic cannot be used for burning");
        require(comicIdToComic[burnId].burnableIn == mintId, "BattleflyComic: This comic cannot be used for burning");
        require(
            balanceOf(msg.sender, burnId) >= comicIdToComic[burnId].burnAmount * amount,
            "BattleflyComic: Not enough comics in wallet to burn"
        );
        safeTransferFrom(
            msg.sender,
            0x000000000000000000000000000000000000dEaD,
            burnId,
            comicIdToComic[burnId].burnAmount * amount,
            ""
        );
        _mint(msg.sender, mintId, amount, "");
        emit MintComicByBurning(msg.sender, burnId, amount, mintId);
    }

    // ---------------- Admin methods ----------------- //

    /**
     * @dev Add a new comic cover
     */
    function addComic(Comic memory comic) public onlyAdmin {
        currentComicId++;
        Comic memory newComic = Comic(
            currentComicId,
            comic.active,
            comic.mintType,
            comic.priceInWei,
            comic.burnableIn,
            comic.burnAmount,
            comic.maxPaidMintsPerWallet,
            comic.maxMints,
            comic.name,
            comic.uri
        );
        comicIdToComic[currentComicId] = newComic;
        emit NewComicAdded(
            currentComicId,
            comic.active,
            comic.mintType,
            comic.priceInWei,
            comic.burnableIn,
            comic.burnAmount,
            comic.maxPaidMintsPerWallet,
            comic.maxMints,
            comic.name,
            comic.uri
        );
    }

    /**
     * @dev Mint comic(s) and send them to the treasury address.
     */
    function mintTreasury(
        uint256 amount,
        uint256 id,
        address treasury
    ) public onlyAdmin nonReentrant {
        require(comicIdToComic[id].active, "BattleflyComic: This comic cannot be minted as it is currently paused");
        require(comicIdToComic[id].mintType == 4, "BattleflyComic: This comic cannot be minted as treasury mint");
        require(
            comicIdToComic[id].maxMints == 0 || totalSupply(id) + amount <= comicIdToComic[id].maxMints,
            "BattleflyComic: Max amount of mints reached for this comic"
        );
        _mint(treasury, id, amount, "");
        emit MintComicWithTreasury(treasury, id, amount);
    }

    /**
     * @dev Withdraw Magic
     */
    function withdrawMagic(uint256 amount, address receiver) public onlyAdmin {
        Magic.transfer(receiver, amount);
    }

    /**
     * @dev Update a comic URI
     */
    function updateURI(uint256 _comicId, string memory _newUri) public override onlyAdmin {
        comicIdToComic[_comicId].uri = _newUri;
        emit UpdateComicURI(_comicId, _newUri);
    }

    /**
     * @dev Activate or deactivate the comic
     */
    function activateComic(uint256 _comicId, bool _activate) public onlyAdmin {
        comicIdToComic[_comicId].active = _activate;
        emit ComicActivated(_comicId, _activate);
    }

    /**
     * @dev Update comic.
     */
    function updateComic(uint256 _comicId, Comic memory _comic) public onlyAdmin {
        require(_comicId > 0 && _comicId <= currentComicId, "BattleflyComic: Invalid comic id");
        _comic.id = _comicId;
        comicIdToComic[_comicId] = _comic;
        emit ComicUpdated(
            _comicId,
            _comic.active,
            _comic.mintType,
            _comic.priceInWei,
            _comic.burnableIn,
            _comic.burnAmount,
            _comic.maxPaidMintsPerWallet,
            _comic.maxMints,
            _comic.name,
            _comic.uri
        );
    }

    /**
     * @dev Batch adding admin permission
     */
    function addAdmins(address[] calldata _admins) external onlyOwner {
        for (uint256 i = 0; i < _admins.length; i++) {
            admins[_admins[i]] = true;
        }
    }

    /**
     * @dev Batch removing admin permission
     */
    function removeAdmins(address[] calldata _admins) external onlyOwner {
        for (uint256 i = 0; i < _admins.length; i++) {
            admins[_admins[i]] = false;
        }
    }

    // ---------------- View methods ----------------- //

    /**
     * @dev et the URI of a comic.
     */
    function uri(uint256 _comicId)
        public
        view
        virtual
        override(ERC1155Upgradeable, IBattleflyComic)
        returns (string memory)
    {
        return comicIdToComic[_comicId].uri;
    }

    // ---------------- Internal methods ----------------- //

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155Upgradeable, ERC1155SupplyUpgradeable) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    modifier onlyAdmin() {
        require(admins[msg.sender], "BattleflyComic: caller is not an admin");
        _;
    }
}

