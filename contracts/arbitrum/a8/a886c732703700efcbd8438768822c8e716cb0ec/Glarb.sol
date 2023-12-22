// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./ERC721A.sol";
import "./AccessControlEnumerable.sol";
import "./Pausable.sol";
import "./ERC2981.sol";
import "./IGlarb.sol";

contract Glarb is ERC721A, AccessControlEnumerable, Pausable, ERC2981, IGlarb {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BREEDER_ROLE = keccak256("BREEDER_ROLE");
    bytes32 public constant HATCHER_ROLE = keccak256("HATCHER_ROLE");
    bytes32 public constant REJUVENATOR_ROLE = keccak256("REJUVENATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint256 public constant MAX_BREED_COUNT = 3;

    string private __baseUri;

    uint256 public override incubationTime;

    // Glarb Token Id => Glarb Info
    mapping(uint256 => Glarb) internal _glarbs;

    constructor(
        address adminAddress,
        address minterAddress,
        address pauserAddress,
        address breederAndHatcherAddress,
        address rejuvenatorAddress,
        uint256 incubationTimeValue,
        string memory baseURIValue
    ) ERC721A("Glarbs", "GLARB") {
        require(incubationTimeValue > 0, "!incubation_time");
        __baseUri = baseURIValue;
        incubationTime = incubationTimeValue;

        _grantRole(DEFAULT_ADMIN_ROLE, adminAddress);
        _grantRole(MINTER_ROLE, minterAddress);
        _grantRole(MINTER_ROLE, _msgSender());
        _grantRole(PAUSER_ROLE, pauserAddress);
        _grantRole(BREEDER_ROLE, breederAndHatcherAddress);
        _grantRole(HATCHER_ROLE, breederAndHatcherAddress);
        _grantRole(REJUVENATOR_ROLE, rejuvenatorAddress);
    }

    /**
        This functionality allows to mint Glarbs from the ERC721ATransactor, These Glarbs have no parents.
    */
    function safeMint(
        address to, 
        uint256 quantity
    ) external override {
        require(to != address(0x0), "!to");
        require(hasRole(MINTER_ROLE, msg.sender), "!minter_role");
        require(quantity > 0, "!quantity");

        for(uint i = 0; i < quantity; ++i) {
            uint256 glarbTokenId = _currentIndex + i;
            _glarbs[glarbTokenId] = Glarb({
                genes: 0,
                birthTimestamp: block.timestamp,
                breedCount: 0,
                totalBreedCount: 0,
                familyIds: new uint256[](0),
                isHatched: false
            });
        }
        // _safeMint's second argument now takes in a quantity, not a tokenId.
        _safeMint(to, quantity);
    }

    function breed(
        address owner,
        uint256 parent1Id,
        uint256 parent2Id
    ) external override returns (uint256 glarbTokenId) {
        require(hasRole(BREEDER_ROLE, _msgSender()), "!breeder_role");
        require(parent1Id != parent2Id, "same_glarbs");
        require(ownerOf(parent1Id) == owner, "!parent1_owner");
        require(ownerOf(parent2Id) == owner, "!parent2_owner");
        require(!isIncubating(parent1Id), "!parent1_is_incubating");
        require(!isIncubating(parent2Id), "!parent2_is_incubating");

        Glarb storage parent1 = _glarbs[parent1Id];
        Glarb storage parent2 = _glarbs[parent2Id];

        // Check breed count limit
        require(parent1.breedCount < MAX_BREED_COUNT, "Parent 1 has reached breed limit");
        require(parent2.breedCount < MAX_BREED_COUNT, "Parent 2 has reached breed limit");

        // Check family IDs to prevent incest. Glarbs without parents are skipped.
        for (uint256 i = 0; i < parent1.familyIds.length; ++i) {
            for (uint256 j = 0; j < parent2.familyIds.length; ++j) {
                require(parent1.familyIds[i] != parent2.familyIds[j], "Breeding incest is not allowed");
            }
        }

        // Increment breed count
        parent1.breedCount = parent1.breedCount + 1;
        parent1.totalBreedCount = parent1.totalBreedCount + 1;
        parent2.breedCount = parent2.breedCount + 1;
        parent2.totalBreedCount = parent2.totalBreedCount + 1; 

        return _createGlarb(owner, parent1Id, parent2Id);
    }

    function hatch(address owner, uint256 glarbTokenId, uint256 genes) external override {
        require(hasRole(HATCHER_ROLE, _msgSender()), "!hatcher_role");
        require(ownerOf(glarbTokenId) == owner, "!glarb_owner");
        require(!isIncubating(glarbTokenId), "!is_incubating");
        require(!isGlarbHatched(glarbTokenId), "is_hatched");
        _glarbs[glarbTokenId].isHatched = true;
        _glarbs[glarbTokenId].genes = genes;
        emit GlarbHatched(_msgSender(), glarbTokenId, genes);
    }

    function rejuvenate(address owner, uint256 glarbTokenId) external override {
        require(hasRole(REJUVENATOR_ROLE, _msgSender()), "!rejuvenator_role");
        require(ownerOf(glarbTokenId) == owner, "!glarb_owner");
        
        Glarb storage glarb = _glarbs[glarbTokenId];
        
        // Check breed count > 0
        require(glarb.breedCount > 0, "Glarb: Breed count needs to be more or equal than 0");
        // Increase total count and decrease breed count
        glarb.breedCount = glarb.breedCount - 1;

        emit GlarbRejuvenated(owner, glarbTokenId);
    }

    function getGlarb(uint256 glarbTokenId) external view override returns (Glarb memory) {
        return _glarbs[glarbTokenId];
    }

    function isIncubating(uint256 glarbTokenId) public view override returns (bool) {
        Glarb memory glarb = _glarbs[glarbTokenId];
        return
            glarb.birthTimestamp != 0 && block.timestamp < glarb.birthTimestamp + incubationTime;
    }

    function isGlarbHatched(uint256 glarbTokenId) public view override returns (bool) {
        return _glarbs[glarbTokenId].isHatched;
    }

    /**
     * @dev Pauses all token transfers.
     *
     * See {Pausable-_pause}.
     *
     * Requirements:
     *
     * - the caller must have the `PAUSER_ROLE`.
     */
    function pause() external {
        require(hasRole(PAUSER_ROLE, _msgSender()), "Glarb: must have pauser role to pause");
        _pause();
    }

    /**
     * @dev Unpauses all token transfers.
     *
     * See {Pausable-_unpause}.
     *
     * Requirements:
     *
     * - the caller must have the `PAUSER_ROLE`.
     */
    function unpause() external {
        require(hasRole(PAUSER_ROLE, _msgSender()), "Glarb: must have pauser role to unpause");
        _unpause();
    }

    function setRoyaltyInfo(uint96 _royaltyFeeBps, address _royaltyReceiver) external {
        require(hasRole(PAUSER_ROLE, _msgSender()), "!access_account");
        _setDefaultRoyalty(_royaltyReceiver, _royaltyFeeBps);
        emit RoyaltyInfoUpdated(_royaltyReceiver, _royaltyFeeBps);
    }

    function setBaseUri(string calldata newBaseUri) external {
        require(hasRole(PAUSER_ROLE, _msgSender()), "!access_account");
        string memory oldBaseUri = __baseUri;
        __baseUri = newBaseUri;
        emit BaseURIUpdated(oldBaseUri, newBaseUri);
    }

    function setIncubationTime(uint256 newIncubationTime) external override {
        require(hasRole(PAUSER_ROLE, _msgSender()), "!access_account");
        uint256 oldIncubationTime = incubationTime;
        incubationTime = newIncubationTime;
        emit IncubationTimeUpdated(oldIncubationTime, newIncubationTime);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721A, ERC2981, IERC165, AccessControlEnumerable)
        returns (bool)
    {
        return
            ERC2981.supportsInterface(interfaceId) ||
            AccessControlEnumerable.supportsInterface(interfaceId) ||
            super.supportsInterface(interfaceId);
    }

    /** Internal Functions */

    /**
     * @dev Hook that is called before a set of serially-ordered token ids are about to be transferred.
     * This includes minting. And also called before burning one token.
     *
     * startTokenId - the first token id to be transferred
     * quantity - the amount to be transferred
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, `from`'s `tokenId` will be
     * transferred to `to`.
     * - When `from` is zero, `tokenId` will be minted for `to`.
     * - When `to` is zero, `tokenId` will be burned by `from`.
     * - `from` and `to` are never both zero.
     */
    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal override {
        super._beforeTokenTransfers(from, to, startTokenId, quantity);

        require(!paused(), "Glarb: token transfer while paused");
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`. Empty
     * by default, can be overriden in child contracts.
     */
    function _baseURI() internal view override returns (string memory) {
        return __baseUri;
    }

    /**
     * To change the starting tokenId, please override this function.
     */
    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }
    
    function _createGlarb(
        address owner,
        uint256 parent1Id,
        uint256 parent2Id
    ) private returns (uint256 glarbTokenId) {
        glarbTokenId = _currentIndex;
        _glarbs[glarbTokenId] = Glarb({
            genes: 0,
            birthTimestamp: block.timestamp,
            breedCount: 0,
            totalBreedCount: 0,
            familyIds: _glarbs[parent1Id].familyIds,
            isHatched: false
        });

         // Add parents' family IDs to the offspring
        for (uint256 i = 0; i < _glarbs[parent2Id].familyIds.length; ++i) {
            _glarbs[glarbTokenId].familyIds.push(_glarbs[parent2Id].familyIds[i]);
        }
        // Add the offspring's ID to its family IDs
        _glarbs[glarbTokenId].familyIds.push(glarbTokenId);

        _safeMint(owner, 1);

        emit GlarbBred(glarbTokenId, parent1Id, parent2Id, block.timestamp);

        return glarbTokenId;
    }
}

