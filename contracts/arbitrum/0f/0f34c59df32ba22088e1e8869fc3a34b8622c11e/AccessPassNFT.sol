pragma solidity >=0.8.19;

import "./ERC721.sol";
import "./ERC721URIStorage.sol";
import "./Strings.sol";
import "./MerkleProof.sol";
import "./Counters.sol";
import "./Ownable.sol";

// todo: rename variables post refactor

contract AccessPassNFT is Ownable, ERC721URIStorage {

    mapping(bytes32 => string) public whitelistedMerkleRootToURI;

    mapping(uint256 => bytes32) public tokenIdToRoot;

    using Counters for Counters.Counter;
    Counters.Counter private _tokenSupply;

    /** @notice Information needed for the NewValidRoot event.
     */
    struct RootInfo {
        bytes32 merkleRoot;
        string baseMetadataURI; // The folder URI from which individual token URIs can be derived. Must therefore end with a slash.
    }

    event RedeemAccessPassNFT(address account, uint256 tokenId);
    event NewValidRoot(RootInfo rootInfo);
    event InvalidatedRoot(bytes32 merkleRoot);

    constructor(
        string memory name,
        string memory symbol
    ) ERC721(name, symbol) {}

    /** @notice Registers a new root as being valid. This allows it to be used in access pass verifications.
     * @dev Apart from the root and the URI, the input values are only used for logging
     */
    function addNewRoot(RootInfo memory rootInfo) public onlyOwner {
        require(
            bytes(rootInfo.baseMetadataURI).length > 0,
            "cannot set empty root URI"
        );
        require(
            bytes(whitelistedMerkleRootToURI[rootInfo.merkleRoot]).length == 0,
            "cannot overwrite non-empty URI"
        );
        whitelistedMerkleRootToURI[rootInfo.merkleRoot] = rootInfo.baseMetadataURI;
        emit NewValidRoot(rootInfo);
    }

    /** @notice Removes a root from whitelist. It can no longer be used for access pass validations.
     * @notice This should only be used in case a faulty root was submitted.
     * @notice If a user already redeemed an access pass based on the faulty root,
     * the badge cannot be burnt.
     */
    function deleteRoot(bytes32 merkleRoot) public onlyOwner {
        delete whitelistedMerkleRootToURI[merkleRoot];
        emit InvalidatedRoot(merkleRoot);
    }

    /** @notice Total supply getter. Returns the total number of minted access passes so far.
     */
    function totalSupply() public view returns (uint256) {
        return _tokenSupply.current();
    }

    /** @notice Total supply getter. Returns the total number of minted access passes so far.
     * @param account: user's address
     * @param accountPassCounter: user's pass counter
     * @param merkleRoot: merkle root associated with this badge
     */
    function getTokenIdHash(
        address account,
        uint256 accountPassCounter,
        bytes32 merkleRoot
    ) public view returns (bytes32) {
        return keccak256(abi.encodePacked(account, merkleRoot, accountPassCounter));
    }

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721URIStorage) returns (string memory) {
        string memory rootURI = whitelistedMerkleRootToURI[tokenIdToRoot[tokenId]];
        return rootURI;
    }


    /** @notice Total supply getter. Returns the total number of minted badges so far.
     * @param account: merkle tree leaf account address
     * @param proof: merkle tree proof of the leaf
     * @param merkleRoot: merkle tree root based on which the proof is verified
     */
    function redeem(
        address account,
        uint256 numberOfAccessPasses,
        bytes32[] calldata proof,
        bytes32 merkleRoot
    ) public returns (uint256[] memory tokenIds) {
        require(
            _verify(_leaf(account, numberOfAccessPasses), proof, merkleRoot),
            "Invalid Merkle proof"
        );

        tokenIds = new uint256[](numberOfAccessPasses);

        for (uint256 i = 0; i < numberOfAccessPasses; i++) {
            bytes32 tokenIdHash = getTokenIdHash(
                account,
                i,
                merkleRoot
            );
            uint256 tokenId = uint256(tokenIdHash);
            _tokenSupply.increment();
            _safeMint(account, tokenId);
            tokenIdToRoot[tokenId] = merkleRoot;
            tokenIds[i] = tokenId;
            emit RedeemAccessPassNFT(account, tokenId);
        }

        return tokenIds;
    }

    /** @notice Encoded the leaf information
     * @param account: account address
     */
    function _leaf(address account, uint256 numberOfAccessPasses) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(account, numberOfAccessPasses));
    }

    /** @notice Verification that the hash of the actor address and information
     * is correctly stored in the Merkle tree i.e. the proof is validated
     */
    function _verify(
        bytes32 encodedLeaf,
        bytes32[] memory proof,
        bytes32 merkleRoot
    ) internal view returns (bool) {
        require(bytes(whitelistedMerkleRootToURI[merkleRoot]).length > 0, "Unrecognised merkle root");
        return MerkleProof.verify(proof, merkleRoot, encodedLeaf);
    }
}


