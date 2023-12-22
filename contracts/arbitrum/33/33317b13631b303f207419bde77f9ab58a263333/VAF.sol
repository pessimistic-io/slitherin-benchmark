// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

///////////////////////////////////////////
///                                     ///
///     ██╗   ██╗  █████╗  ███████╗     ///
///     ██║   ██║ ██╔══██╗ ██╔════╝     ///
///     ██║   ██║ ███████║ ██████╗      ///
///     ╚██╗ ██╔╝ ██╔══██║ ██╔═══╝      ///
///      ╚████╔╝  ██║  ██║ ██║          ///
///       ╚═══╝   ╚═╝  ╚═╝ ╚═╝          ///
///                                     ///
///      © 2022 vocus and friends       ///
///                                     ///
///////////////////////////////////////////

import "./ERC721.sol";
import "./ERC2981.sol";
import "./IERC20.sol";
import "./ERC721Enumerable.sol";
import "./Counters.sol";
import "./MerkleProof.sol";
import "./Ownable.sol";

contract VAF is ERC721, ERC721Enumerable, ERC2981, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdTracker;

    uint256 public MAX_SUPPLY = 3_333;
    uint256 private SALE_PRICE = 0.03 ether;
    string public provenance;
    string private baseURI;

    bytes32 _merkleRoot;
    mapping(address => bool) _hasOnboarded;

    bool isSaleActivated;
    bool isMetadataFrozen;

    error AlreadyOnboarded();
    error AlreadyRevealed();
    error BadInput();
    error BeepBoop();
    error ExceededMaxSupply();
    error NotInMerkle();
    error ReadOnly();
    error TooEarly();
    error Underpaid();

    event BaseURIUpdated(string indexed baseURI);
    event MetadataFrozen();
    event MetadataRevealed(uint256 phase);
    event ProvenanceUpdated(string indexed provenance);
    event RoyaltyUpdated();

    struct Phase {
        bool isRevealed;
        uint256 firstTokenId;
        uint256 lastTokenId;
        uint256 offset;
    }

    Phase[] phases;

    constructor(string memory _name, string memory _symbol)
        ERC721(_name, _symbol)
    {}

    function setPhases(uint256 total, uint256[] calldata ids)
        external
        onlyOwner
    {
        if (phases.length != 0) revert ReadOnly();
        if (total * 2 != ids.length) revert BadInput();

        for (uint256 i = 0; i < total; i++) {
            phases.push(
                Phase({
                    isRevealed: false,
                    firstTokenId: ids[i * 2],
                    lastTokenId: ids[i * 2 + 1],
                    offset: 0
                })
            );
        }
    }

    function setBaseURI(string calldata baseURI_) external onlyOwner {
        if (isMetadataFrozen) revert ReadOnly();
        baseURI = baseURI_;
        emit BaseURIUpdated(baseURI_);
    }

    function onboard(address[] calldata to, uint256[] calldata quantity)
        external
        onlyOwner
    {
        if (to.length != quantity.length) revert BadInput();

        unchecked {
            for (uint256 i = 0; i < to.length; i++) {
                mint(to[i], quantity[i]);
            }
        }
    }

    function setMerkleRoot(bytes32 merkleRoot_) external onlyOwner {
        _merkleRoot = merkleRoot_;
    }

    modifier costs(uint256 price) {
        if (msg.value < price) revert Underpaid();
        _;
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
    }

    modifier eoaOnly() {
        if (tx.origin != msg.sender) revert BeepBoop();
        _;
    }

    function onboard(bytes32[] calldata proof)
        external
        payable
        costs(SALE_PRICE)
        eoaOnly
    {
        if (_hasOnboarded[msg.sender]) revert AlreadyOnboarded();

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        bool isValidLeaf = MerkleProof.verify(proof, _merkleRoot, leaf);
        if (!isValidLeaf) revert NotInMerkle();

        mint(msg.sender, 1);
        _hasOnboarded[msg.sender] = true;
    }

    function activateSale() external onlyOwner {
        isSaleActivated = true;
    }

    function onboard(address to, uint256 quantity)
        external
        payable
        costs(SALE_PRICE * quantity)
        eoaOnly
    {
        if (!isSaleActivated) revert TooEarly();
        mint(to, quantity);
    }

    function setProvenance(string calldata _provenance) external onlyOwner {
        if (bytes(provenance).length != 0) revert ReadOnly();
        provenance = _provenance;
        emit ProvenanceUpdated(_provenance);
    }

    function reveal(uint256 phaseId, string calldata randomSeed)
        external
        onlyOwner
    {
        if (phases[phaseId].isRevealed) revert AlreadyRevealed();
        for (uint256 i = 0; i < phaseId; i++) {
            if (!phases[i].isRevealed) revert BadInput();
        }

        uint256 randomness = uint256(keccak256(abi.encode(randomSeed)));
        uint256 offset = randomness %
            (phases[phaseId].lastTokenId - phases[phaseId].firstTokenId + 1);
        if (offset == 0) offset += 42;
        phases[phaseId].offset = offset;
        phases[phaseId].isRevealed = true;
        emit MetadataRevealed(phaseId);
    }

    function freeze() external onlyOwner {
        if (!isMetadataFrozen) {
            isMetadataFrozen = true;
            emit MetadataFrozen();
        }
    }

    function setRoyalty(address receiver, uint96 feeNumerator)
        external
        onlyOwner
    {
        _setDefaultRoyalty(receiver, feeNumerator);
        emit RoyaltyUpdated();
    }

    function withdraw(address payable recipient, uint256 amount)
        external
        onlyOwner
    {
        recipient.transfer(amount);
    }

    function withdraw(
        address recipient,
        address erc20,
        uint256 amount
    ) external onlyOwner {
        IERC20(erc20).transfer(recipient, amount);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC721Enumerable, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function mint(address to, uint256 quantity) internal {
        uint256 currentId = _tokenIdTracker.current();
        if (currentId >= MAX_SUPPLY) revert ExceededMaxSupply();
        if (currentId + quantity > MAX_SUPPLY) revert ExceededMaxSupply();

        unchecked {
            for (uint256 i = 0; i < quantity; i++) {
                _safeMint(to, ++currentId);
                _tokenIdTracker.increment();
            }
        }
    }

    function _revealedTokenId(uint256 tokenId)
        internal
        view
        override
        returns (uint256)
    {
        for (uint256 i = 0; i < phases.length; i++) {
            if (tokenId <= phases[i].lastTokenId) {
                if (!phases[i].isRevealed) return 0;
                return
                    ((tokenId + phases[i].offset) %
                        (phases[i].lastTokenId - phases[i].firstTokenId + 1)) +
                    phases[i].firstTokenId;
            }
        }
        return 0;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId) internal virtual override {
        super._burn(tokenId);
        _resetTokenRoyalty(tokenId);
    }

    receive() external payable {}
}

