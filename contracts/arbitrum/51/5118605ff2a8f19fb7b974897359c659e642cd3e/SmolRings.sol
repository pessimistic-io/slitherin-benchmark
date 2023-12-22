// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./IERC20.sol";
import "./IERC721.sol";
import "./IERC1155.sol";
import "./Strings.sol";
import "./ERC721Enumerable.sol";
import "./ReentrancyGuard.sol";
import "./AccessControl.sol";
import "./ISmolRings.sol";
import "./ISmolRingDistributor.sol";
import "./ISmolRingStaking.sol";
import "./ISmolRingForging.sol";
import "./ICreatureOwnerResolver.sol";
import "./SmolRingUtils.sol";
import "./ISmoloveActionsVault.sol";
import "./IAtlasMine.sol";

/**
 * @title  SmolRing contract
 * @author Archethect
 * @notice This contract contains all functionalities for Smol Rings
 */
contract SmolRings is ERC721Enumerable, ReentrancyGuard, AccessControl, ISmolRings {
    using Strings for uint256;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR");

    uint128 public constant MAX_RINGS = 7500;
    uint128 public constant MAX_WHITELIST_AMOUNT = 3400;
    uint128 public constant RING_SMOL_AMOUNT = 3700;
    uint128 public constant RING_TEAM_AMOUNT = 400;
    uint256 public constant ringStakePriceInMagicWei = 169e18;
    uint256 public constant ringBuyPriceInEthWei = 42e15;

    uint128 public whitelistAmount;
    bool public regularMintEnabled;
    bool public whitelistMintEnabled;
    bool public smolMintEnabled;
    bool public tokensLocked;
    uint256 public ringCounter;
    uint256 public ringCounterWhitelist;
    uint256 public ringCounterTeam;
    uint256 public ringCounterSmol;
    uint256 public baseRewardFactor;
    string public baseURI;

    ICreatureOwnerResolver public smolBrainsOwnerResolver;
    ICreatureOwnerResolver public smolBodiesOwnerResolver;
    IERC20 public magic;
    address public treasury;
    ISmolRingDistributor public ringDistributor;
    ISmolRingStaking public staking;
    ISmolRingForging public forging;
    ISmoloveActionsVault public smoloveActionsVault;

    mapping(uint256 => bool) public smolUsed;
    mapping(uint256 => bool) public swolUsed;
    mapping(uint256 => uint256) public totalRingsPerType;
    mapping(uint256 => Ring) public ringProps;

    event WhitelistRingMinted(address sender, uint256 ringId);
    event TeamRingMinted(address sender, uint256 ringId);
    event RingMinted(address sender, uint256 ringId);
    event SmolRingMinted(address sender, uint256 smolId, uint256 ringId);
    event SwolRingMinted(address sender, uint256 swolId, uint256 ringId);
    event TokensLocked(bool status);

    constructor(
        address smolBrainsOwnerResolver_,
        address smolBodiesOwnerResolver_,
        address magic_,
        address ringDistributor_,
        address smoloveActionsVault_,
        address treasury_,
        address operator_,
        address admin_
    ) ERC721("Smol Ring", "SmolRing") {
        require(smolBrainsOwnerResolver_ != address(0), "SMOLRING:ILLEGAL_ADDRESS");
        require(smolBodiesOwnerResolver_ != address(0), "SMOLRING:ILLEGAL_ADDRESS");
        require(magic_ != address(0), "SMOLRING:ILLEGAL_ADDRESS");
        require(ringDistributor_ != address(0), "SMOLRING:ILLEGAL_ADDRESS");
        require(smoloveActionsVault_ != address(0), "SMOLRING:ILLEGAL_ADDRESS");
        require(treasury_ != address(0), "SMOLRING:ILLEGAL_ADDRESS");
        require(operator_ != address(0), "SMOLRING:ILLEGAL_ADDRESS");
        require(admin_ != address(0), "SMOLRING:ILLEGAL_ADDRESS");
        smolBrainsOwnerResolver = ICreatureOwnerResolver(smolBrainsOwnerResolver_);
        smolBodiesOwnerResolver = ICreatureOwnerResolver(smolBodiesOwnerResolver_);
        magic = IERC20(magic_);
        ringDistributor = ISmolRingDistributor(ringDistributor_);
        smoloveActionsVault = ISmoloveActionsVault(smoloveActionsVault_);
        treasury = treasury_;
        baseRewardFactor = 250;
        whitelistAmount = 900;
        ringCounter = 1;
        ringCounterTeam = 1;
        ringCounterSmol = 1;
        ringCounterWhitelist = 1;
        tokensLocked = true;
        _setupRole(ADMIN_ROLE, admin_);
        _setupRole(ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, admin_);
        _setupRole(OPERATOR_ROLE, operator_);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "SMOLRING:ACCESS_DENIED");
        _;
    }

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "SMOLRING:ACCESS_DENIED");
        _;
    }

    modifier nonContractCaller() {
        require(msg.sender == tx.origin, "SMOLRING:CONTRACT_CALLER");
        _;
    }

    /**
     * @notice Mint a ring
     * @param amount Amount of rings to mint
     */
    function mintRing(uint256 amount, bool stake) external payable virtual nonReentrant nonContractCaller {
        require(address(forging) != address(0), "SMOLRING:FORGING_CONTRACT_NOT_SET");
        require(regularMintEnabled, "SMOLRING:REGULAR_MINT_DISABLED");
        require(amount > 0, "SMOLRING:MINTING_0_NOT_ALLOWED");
        require(amount <= 5, "SMOLRING:MAX_ALLOWANCE_PER_BATCH_REACHED");
        require(
            ringCounter + amount - 1 <= (MAX_RINGS - RING_TEAM_AMOUNT - (MAX_WHITELIST_AMOUNT - whitelistAmount)),
            "SMOLRING:TOTAL_RING_AMOUNT_REACHED"
        );
        if (stake) {
            require(
                magic.balanceOf(msg.sender) >= amount * ringStakePriceInMagicWei,
                "SMOLRING:NOT_ENOUGH_MAGIC_IN_WALLET"
            );
            smoloveActionsVault.stake(msg.sender, amount * ringStakePriceInMagicWei);
        } else {
            require(amount * ringBuyPriceInEthWei == msg.value, "SMOLRING:INVALID_PRICE");
        }
        for (uint256 i = 0; i < amount; i++) {
            ringProps[RING_TEAM_AMOUNT + ringCounter] = Ring(0);
            totalRingsPerType[0]++;
            _safeMint(msg.sender, RING_TEAM_AMOUNT + ringCounter);
            emit RingMinted(msg.sender, RING_TEAM_AMOUNT + ringCounter);
            ringCounter++;
        }
    }

    function mintRingSmolSwol(
        uint256[] calldata smolIds,
        uint256[] calldata swolIds,
        bool stake
    ) external payable virtual nonReentrant nonContractCaller {
        require((smolIds.length + swolIds.length) > 0, "SMOLRING:MINTING_0_NOT_ALLOWED");
        if (stake) {
            require(
                magic.balanceOf(msg.sender) >= (smolIds.length + swolIds.length) * ringStakePriceInMagicWei,
                "SMOLRING:NOT_ENOUGH_MAGIC_IN_WALLET"
            );
        } else {
            require(
                (smolIds.length + swolIds.length) * ringBuyPriceInEthWei == msg.value,
                "SMOLRING:NOT_ENOUGH_MAGIC_IN_WALLET"
            );
        }
        _mintRingSmol(smolIds, stake);
        _mintRingSwol(swolIds, stake);
    }

    /**
     * @notice Mint ring for Smol holders
     * @param smolIds Ids of smols to be used as minting pass (should be owner of the smols)
     */
    function mintRingSmol(uint256[] calldata smolIds, bool stake)
        external
        payable
        virtual
        nonReentrant
        nonContractCaller
    {
        require(smolIds.length > 0, "SMOLRING:MINTING_0_NOT_ALLOWED");
        if (stake) {
            require(
                magic.balanceOf(msg.sender) >= smolIds.length * ringStakePriceInMagicWei,
                "SMOLRING:NOT_ENOUGH_MAGIC_IN_WALLET"
            );
        } else {
            require(smolIds.length * ringBuyPriceInEthWei == msg.value, "SMOLRING:INVALID_PRICE");
        }
        _mintRingSmol(smolIds, stake);
    }

    function _mintRingSmol(uint256[] calldata smolIds, bool stake) internal {
        require(address(forging) != address(0), "SMOLRING:FORGING_CONTRACT_NOT_SET");
        require(smolMintEnabled, "SMOLRING:SMOL_MINT_DISABLED");
        require(smolIds.length <= 32, "SMOLRING:MAX_ALLOWANCE_PER_BATCH_REACHED");
        require(
            ringCounterSmol + smolIds.length - 1 <= RING_SMOL_AMOUNT,
            "SMOLRING:TOTAL_RING_AMOUNT_FOR_SMOL_REACHED"
        );
        require(
            ringCounter + smolIds.length - 1 <=
                (MAX_RINGS - RING_TEAM_AMOUNT - (MAX_WHITELIST_AMOUNT - whitelistAmount)),
            "SMOLRING:TOTAL_RING_AMOUNT_REACHED"
        );
        for (uint256 i = 0; i < smolIds.length; i++) {
            require(smolBrainsOwnerResolver.isOwner(msg.sender, smolIds[i]), "SMOLRING:NOT_OWNER_OF_SMOL");
            require(!smolUsed[smolIds[i]], "SMOLRING:SMOL_ALREADY_USED");
        }
        if (stake && smolIds.length > 0) {
            smoloveActionsVault.stake(msg.sender, smolIds.length * ringStakePriceInMagicWei);
        }
        for (uint256 i = 0; i < smolIds.length; i++) {
            smolUsed[smolIds[i]] = true;
            ringProps[RING_TEAM_AMOUNT + ringCounter] = Ring(0);
            totalRingsPerType[0]++;
            _safeMint(msg.sender, RING_TEAM_AMOUNT + ringCounter);
            emit SmolRingMinted(msg.sender, smolIds[i], RING_TEAM_AMOUNT + ringCounter);
            ringCounter++;
            ringCounterSmol++;
        }
    }

    /**
     * @notice Mint ring for Swol holders
     * @param swolIds Ids of swols to be used as minting pass (should be owner of the swols)
     */
    function mintRingSwol(uint256[] calldata swolIds, bool stake)
        external
        payable
        virtual
        nonReentrant
        nonContractCaller
    {
        require(swolIds.length > 0, "SMOLRING:MINTING_0_NOT_ALLOWED");
        if (stake) {
            require(
                magic.balanceOf(msg.sender) >= swolIds.length * ringStakePriceInMagicWei,
                "SMOLRING:NOT_ENOUGH_MAGIC_IN_WALLET"
            );
        } else {
            require(swolIds.length * ringBuyPriceInEthWei == msg.value, "SMOLRING:INVALID_PRICE");
        }
        _mintRingSwol(swolIds, stake);
    }

    function _mintRingSwol(uint256[] calldata swolIds, bool stake) internal {
        require(address(forging) != address(0), "SMOLRING:FORGING_CONTRACT_NOT_SET");
        require(smolMintEnabled, "SMOLRING:SWOL_MINT_DISABLED");
        require(swolIds.length <= 32, "SMOLRING:MAX_ALLOWANCE_PER_BATCH_REACHED");
        require(
            ringCounterSmol + swolIds.length - 1 <= RING_SMOL_AMOUNT,
            "SMOLRING:TOTAL_RING_AMOUNT_FOR_SWOL_REACHED"
        );
        require(
            ringCounter + swolIds.length - 1 <=
                (MAX_RINGS - RING_TEAM_AMOUNT - (MAX_WHITELIST_AMOUNT - whitelistAmount)),
            "SMOLRING:TOTAL_RING_AMOUNT_REACHED"
        );
        for (uint256 i = 0; i < swolIds.length; i++) {
            require(smolBodiesOwnerResolver.isOwner(msg.sender, swolIds[i]), "SMOLRING:NOT_OWNER_OF_SWOL");
            require(!swolUsed[swolIds[i]], "SMOLRING:SWOL_ALREADY_USED");
        }
        if (stake && swolIds.length > 0) {
            smoloveActionsVault.stake(msg.sender, swolIds.length * ringStakePriceInMagicWei);
        }
        for (uint256 i = 0; i < swolIds.length; i++) {
            swolUsed[swolIds[i]] = true;
            ringProps[RING_TEAM_AMOUNT + ringCounter] = Ring(0);
            totalRingsPerType[0]++;
            _safeMint(msg.sender, RING_TEAM_AMOUNT + ringCounter);
            emit SwolRingMinted(msg.sender, swolIds[i], RING_TEAM_AMOUNT + ringCounter);
            ringCounter++;
            ringCounterSmol++;
        }
    }

    /**
     * @notice Mint ring for accounts on whitelist
     * @param epoch claim epoch
     * @param index claim index
     * @param amount amount of rings to mint
     * @param rings array of amount of rings per type
     * @param merkleProof merkleproof of claim
     */
    function mintRingWhitelist(
        uint256 epoch,
        uint256 index,
        uint256 amount,
        uint256[] calldata rings,
        bytes32[] calldata merkleProof,
        bool stake
    ) external payable virtual nonReentrant {
        require(address(forging) != address(0), "SMOLRING:FORGING_CONTRACT_NOT_SET");
        require(whitelistMintEnabled, "SMOLRING:WHITELIST_MINT_DISABLED");
        require(amount > 0, "SMOLRING:MINTING_0_NOT_ALLOWED");
        require(amount <= 32, "SMOLRING:MAX_ALLOWANCE_PER_BATCH_REACHED");
        require(
            ringCounterWhitelist + amount - 1 <= whitelistAmount,
            "SMOLRING:TOTAL_RING_AMOUNT_FOR_WHITELIST_REACHED"
        );
        require(
            ringCounter + amount - 1 <= (MAX_RINGS - RING_TEAM_AMOUNT - (MAX_WHITELIST_AMOUNT - whitelistAmount)),
            "SMOLRING:TOTAL_RING_AMOUNT_REACHED"
        );
        for (uint256 i = 0; i < rings.length; i++) {
            require(rings[i] == 0 || forging.getAllowedForges(i).valid, "SMOLRING:TYPE_NOT_ALLOWED_FOR_FORGING");
        }
        require(
            ringDistributor.verifyAndClaim(msg.sender, epoch, index, amount, rings, merkleProof),
            "SMOLRING:INVALID_PROOF"
        );
        if (stake) {
            require(
                magic.balanceOf(msg.sender) >= amount * ringStakePriceInMagicWei,
                "SMOLRING:NOT_ENOUGH_MAGIC_IN_WALLET"
            );
            smoloveActionsVault.stake(msg.sender, amount * ringStakePriceInMagicWei);
        } else {
            require(amount * ringBuyPriceInEthWei == msg.value, "SMOLRING:INVALID_PRICE");
        }
        for (uint256 i = 0; i < rings.length; i++) {
            for (uint256 j = 0; j < rings[i]; j++) {
                if (totalRingsPerType[i] == forging.getAllowedForges(i).maxForges) {
                    ringProps[RING_TEAM_AMOUNT + ringCounter] = Ring(0);
                    totalRingsPerType[0]++;
                } else {
                    ringProps[RING_TEAM_AMOUNT + ringCounter] = Ring(i);
                    totalRingsPerType[i]++;
                }
                _safeMint(msg.sender, RING_TEAM_AMOUNT + ringCounter);
                emit WhitelistRingMinted(msg.sender, RING_TEAM_AMOUNT + ringCounter);
                ringCounter++;
                ringCounterWhitelist++;
            }
        }
    }

    /**
     * @notice Mint ring for team
     * @param ringType type of rings to mint
     * @param amount amount of rings to mint
     * @param recipient account to send the rings to
     */
    function mintRingTeam(
        uint256 ringType,
        uint256 amount,
        address recipient
    ) external virtual nonReentrant onlyOperator {
        require(address(forging) != address(0), "SMOLRING:FORGING_CONTRACT_NOT_SET");
        require(ringCounterTeam + amount - 1 <= RING_TEAM_AMOUNT, "SMOLRING:TOTAL_TEAM_AMOUNT_REACHED");
        require(amount <= 32, "SMOLRING:MAX_ALLOWANCE_PER_BATCH_REACHED");
        require(forging.getAllowedForges(ringType).valid, "SMOLRING:TYPE_NOT_ALLOWED_FOR_FORGING");
        for (uint256 i = 0; i < amount; i++) {
            if (totalRingsPerType[ringType] == forging.getAllowedForges(ringType).maxForges) {
                ringProps[ringCounterTeam] = Ring(0);
                totalRingsPerType[0]++;
            } else {
                ringProps[ringCounterTeam] = Ring(ringType);
                totalRingsPerType[ringType]++;
            }
            _safeMint(recipient, ringCounterTeam);
            emit TeamRingMinted(msg.sender, ringCounterTeam);
            ringCounterTeam++;
        }
    }

    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        require(_exists(_tokenId), "SMOLRING:URI_QUERY_FOR_NON_EXISTANT_TOKEN");
        string memory json = SmolRingUtils.base64encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "#',
                        SmolRingUtils.stringify(_tokenId),
                        '", "description": "Smol Rings", "external_url":"https://www.smolove.xyz/", "image": "',
                        forging.getAllowedForges(ringProps[_tokenId].ringType).imageURI,
                        '", "attributes": [{"trait_type": "Type", "value": "',
                        forging.getAllowedForges(ringProps[_tokenId].ringType).name,
                        '"},{"trait_type": "Reward Factor", "value": "',
                        SmolRingUtils.stringify(forging.getAllowedForges(ringProps[_tokenId].ringType).rewardFactor),
                        '"}]}'
                    )
                )
            )
        );
        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    function setBaseRewardFactor(uint256 baseRewardFactor_) external onlyOperator {
        baseRewardFactor = baseRewardFactor_;
    }

    function ringRarity(uint256 ringId) public view returns (uint256) {
        if (ringProps[ringId].ringType > 0) {
            return forging.getAllowedForges(ringProps[ringId].ringType).rewardFactor;
        }
        return baseRewardFactor;
    }

    function getRingProps(uint256 ringId) public view returns (Ring memory) {
        return ringProps[ringId];
    }

    function getTotalRingsPerType(uint256 ringType) public view returns (uint256) {
        return totalRingsPerType[ringType];
    }

    function setRegularMintEnabled(bool status) public onlyOperator {
        if (status) {
            regularMintEnabled = status;
            smolMintEnabled = !status;
            whitelistMintEnabled = !status;
        } else {
            regularMintEnabled = status;
        }
    }

    function setWhitelistMintEnabled(bool status) public onlyOperator {
        if (status) {
            whitelistMintEnabled = status;
            smolMintEnabled = !status;
            regularMintEnabled = !status;
        } else {
            whitelistMintEnabled = status;
        }
    }

    function setSmolMintEnabled(bool status) public onlyOperator {
        if (status) {
            smolMintEnabled = status;
            whitelistMintEnabled = !status;
            regularMintEnabled = !status;
        } else {
            smolMintEnabled = status;
        }
    }

    function setTokensLocked(bool status) public onlyOperator {
        tokensLocked = status;
        emit TokensLocked(status);
    }

    function setWhitelistAmount(uint128 whitelistAmount_) public onlyAdmin {
        require(whitelistAmount_ <= MAX_WHITELIST_AMOUNT, "SMOLRING:OVER_MAX_WHITELIST_AMOUNT");
        whitelistAmount = whitelistAmount_;
    }

    function setForgingContract(address forging_) external onlyAdmin {
        require(forging_ != address(0), "SMOLRING:ILLEGAL_ADDRESS");
        forging = ISmolRingForging(forging_);
    }

    function switchToRingType(uint256 ringId, uint256 ringType) public {
        require(
            msg.sender == address(this) || msg.sender == address(forging),
            "SMOLRING:SWITCHING_RING_TYPES_NOT_ALLOWED"
        );
        totalRingsPerType[ringType]++;
        uint256 currentRingType = ringProps[ringId].ringType;
        totalRingsPerType[currentRingType]--;
        ringProps[ringId].ringType = ringType;
    }

    function withdrawProceeds() public {
        uint256 contractBalance = address(this).balance;
        payable(treasury).transfer(contractBalance);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        require(address(0) == from || !tokensLocked, "SMOLRING:TOKENS_NOT_UNLOCKED");
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Enumerable, IERC165, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

