// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ERC721Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./ECDSA.sol";

struct ProjectData {
    bool locked;
    string name;
    string creator;
    string baseUri;
    uint128 maxSupply;
    uint128 nextTokenIdx;
    address[] feeReceivers;
    uint16[]  feeBasisPoints;
    uint16    totalFeeBasisPoints;
}

contract SelectNFT is Initializable, ERC721Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    using ECDSA for bytes32;
    using Strings for uint256;

    uint128 public nextProjectId;
    mapping(uint128 => ProjectData) public projects;
    mapping(uint128 => address) public mintContract;

    mapping(address => mapping(uint256 => bool)) private _usedNonces;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize() initializer public {
        __ERC721_init("SelectNFT", "SLCT");
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    modifier unlockedProject(uint128 projectId) {
        ProjectData memory projectData = projects[projectId];
        require(projectId < nextProjectId && !projectData.locked);
        _;
    }

    function createProject(string calldata name, string calldata creator, string calldata baseUri, uint128 maxSupply, address[] calldata feeReceivers, uint16[] calldata feeBasisPoints) 
        public 
        onlyOwner
    {
        uint16 totalBasisPoints;
        for (uint256 i = 0; i < feeBasisPoints.length;) {
            totalBasisPoints += feeBasisPoints[i];
            unchecked { ++i; }
        }
        require(totalBasisPoints <= 10000, "SelectNFT: basis points must total 10000");

        unchecked {
            projects[nextProjectId++] = ProjectData(false, name, creator, baseUri, maxSupply, 0, feeReceivers, feeBasisPoints, totalBasisPoints);
        }
    }

    function setProjectName(uint128 projectId, string calldata name)
        public
        onlyOwner
        unlockedProject(projectId)
    {
        projects[projectId].name = name;
    }

    function setProjectCreator(uint128 projectId, string calldata creator)
        public
        onlyOwner
        unlockedProject(projectId)
    {
        projects[projectId].creator = creator;
    }

    function setProjectBaseUri(uint128 projectId, string calldata baseUri)
        public
        onlyOwner 
        unlockedProject(projectId)
    {
        projects[projectId].baseUri = baseUri;
    }

    function setProjectMaxSupply(uint128 projectId, uint128 maxSupply)
        public
        onlyOwner
        unlockedProject(projectId)
    {
        projects[projectId].maxSupply = maxSupply;
    }

    function setProjectFees(uint128 projectId, address[] calldata feeReceivers, uint16[] calldata feeBasisPoints) public unlockedProject(projectId) {
        require(feeReceivers.length == feeBasisPoints.length, "SelectNFT: must have a fee receiver for each basis point share");

        uint16 totalBasisPoints;
        for (uint256 i = 0; i < feeBasisPoints.length;) {
            totalBasisPoints += feeBasisPoints[i];
            unchecked { ++i; }
        }
        require(totalBasisPoints <= 10000, "SelectNFT: basis points must total 10000");

        projects[projectId].feeReceivers = feeReceivers;
        projects[projectId].feeBasisPoints = feeBasisPoints;
        projects[projectId].totalFeeBasisPoints = totalBasisPoints;
    }

    function getProjectFees(uint128 projectId) public view returns(address[] memory, uint16[] memory) {
        ProjectData memory projectData = projects[projectId];
        return (projectData.feeReceivers, projectData.feeBasisPoints);
    }

    function lockProject(uint128 projectId)
        public
        onlyOwner
        unlockedProject(projectId)
    {
        projects[projectId].locked = true;
    }

    function setProjectMintContract(uint128 projectId, address mintContractAddress)
        public
        onlyOwner
    {
        mintContract[projectId] = mintContractAddress;
    }

    function mint(address to, uint128 projectId) public {
        require(msg.sender == owner() || msg.sender == mintContract[projectId]);
        require(projectId < nextProjectId, "SelectNFT: project does not exist");

        ProjectData memory projectData = projects[projectId];
        require(!projectData.locked, "SelectNFT: project locked");
        require(projectData.maxSupply == 0 || projectData.nextTokenIdx < projectData.maxSupply, "SelectNFT: project has reached it's max supply");

        uint256 tokenId = tokenIdForProjectAndTokenIdx(projectId, projectData.nextTokenIdx);
        projects[projectId].nextTokenIdx++;
        _mint(to, tokenId);
    }

    function unorderedMint(address to, uint128 projectId, uint128 tokenIdx) public {
        require(msg.sender == owner() || msg.sender == mintContract[projectId]);
        require(projectId < nextProjectId, "SelectNFT: project does not exist");

        ProjectData memory projectData = projects[projectId];
        require(!projectData.locked, "SelectNFT: project locked");

        uint256 tokenId = tokenIdForProjectAndTokenIdx(projectId, tokenIdx);
        _mint(to, tokenId);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        uint128 projectId = projectIdFromTokenId(tokenId);
        string memory baseURI = projects[projectId].baseUri;
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }

    function signatureApprovalForAll(address account, address operator, bool approved, uint256 nonce, bytes memory sig) public onlyOwner {
        /* CHECKS */
        require(!_usedNonces[msg.sender][nonce]);

        bytes32 msgHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            keccak256(abi.encodePacked(operator, approved, nonce)))
        );
        require(account == msgHash.recover(sig));

        /* EFFECTS */
        _usedNonces[msg.sender][nonce] = true;

        /* INTERACTIONS */
        _setApprovalForAll(account, operator, approved);
    }

    // Utility functions

    function projectIdFromTokenId(uint256 tokenId) 
        public 
        pure 
        returns(uint128)
    {
        return uint128(tokenId >> 128);
    }

    function tokenIdxFromTokenId(uint256 tokenId) 
        public 
        pure 
        returns(uint128)
    {
        return uint128(tokenId & type(uint256).max);
    }

    function tokenIdForProjectAndTokenIdx(uint128 projectId, uint128 tokenIdx) 
        public 
        pure 
        returns(uint256)
    {
        return tokenIdx + (uint256(projectId) << 128);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
