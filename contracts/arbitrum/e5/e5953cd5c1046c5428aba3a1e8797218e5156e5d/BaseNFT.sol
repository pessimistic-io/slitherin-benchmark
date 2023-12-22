// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.17;

// Contracts
import "./MerkleProof.sol";
import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./ERC721Burnable.sol";
import "./ERC721Pausable.sol";
import "./AccessControlEnumerable.sol";
import "./Context.sol";
import "./Strings.sol";

// Libraries
import "./Counters.sol";

contract BaseNFT is
    Context,
    AccessControlEnumerable,
    ERC721Enumerable,
    ERC721Burnable,
    ERC721Pausable
{
    using Counters for Counters.Counter;
    using Strings for uint256;

    bytes32 public immutable merkleRoot;

    bytes32 public constant MINTER_ROLE = keccak256('MINTER_ROLE');

    bytes32 public constant PAUSER_ROLE = keccak256('PAUSER_ROLE');

    Counters.Counter public _tokenIdTracker;

    string private _baseTokenURI = 'Asdas';

    // This is a packed array of booleans.
    mapping(uint256 => uint256) private claimedBitMap;

    constructor(
        string memory _name,
        string memory _symbol,
        bytes32 _merkleRoot
    ) ERC721(_name, _symbol) {
        merkleRoot = _merkleRoot;

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
    }

    function pause() external {
        require(
            hasRole(PAUSER_ROLE, _msgSender()),
            'Must have pauser role to pause'
        );
        _pause();
    }

    function unpause() external {
        require(
            hasRole(PAUSER_ROLE, _msgSender()),
            'Must have pauser role to unpause'
        );
        _unpause();
    }

    function setBaseTokenURI(string memory baseTokenURI) external {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            'Must have admin role to change baseTokenURI'
        );

        _baseTokenURI = baseTokenURI;
    }

    function mint(address to) external whenNotPaused {
        require(
            hasRole(MINTER_ROLE, _msgSender()),
            'Must have minter role to mint'
        );

        // We cannot just use balanceOf to create the new tokenId because tokens
        // can be burned (destroyed), so we need a separate counter.
        _mint(to, _tokenIdTracker.current());
        _tokenIdTracker.increment();
    }

    function claim(
        uint256 index,
        address account,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external whenNotPaused {
        require(!isClaimed(index), 'Drop already claimed.');

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, account, amount));
        require(
            MerkleProof.verify(merkleProof, merkleRoot, node),
            'Invalid proof.'
        );

        // Mark it claimed and send the token.
        _setClaimed(index);

        for (uint256 i = 0; i < amount; i++) {
            // We cannot just use balanceOf to create the new tokenId because tokens
            // can be burned (destroyed), so we need a separate counter.
            _mint(account, _tokenIdTracker.current());
            _tokenIdTracker.increment();
        }

        emit Claimed(index, account, amount);
    }

    function isClaimed(uint256 index) public view returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMap[claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    function _setClaimed(uint256 index) private {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMap[claimedWordIndex] =
            claimedBitMap[claimedWordIndex] |
            (1 << claimedBitIndex);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable, ERC721Pausable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlEnumerable, ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(_exists(tokenId), 'URI query for nonexistent token');

        string memory currentBaseURI = _baseURI();
        return
            bytes(currentBaseURI).length > 0
                ? string(
                    abi.encodePacked(
                        currentBaseURI,
                        tokenId.toString(),
                        '.json'
                    )
                )
                : '';
    }

    event Claimed(uint256 index, address account, uint256 amount);
}

