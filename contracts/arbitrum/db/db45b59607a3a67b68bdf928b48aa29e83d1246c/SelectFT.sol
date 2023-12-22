// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ERC1155Upgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";
import "./ERC1155BurnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./Strings.sol";
import "./ECDSA.sol";

struct ProjectData {
    bool locked;
    string name;
    string creator;
    string tokenUri;
    uint128 maxSupply;
}

contract SelectFT is Initializable, ERC1155Upgradeable, AccessControlUpgradeable, ERC1155BurnableUpgradeable, UUPSUpgradeable {
    using ECDSA for bytes32;
    using Strings for uint256;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    uint256 public nextProjectId;
    mapping(uint256 => ProjectData) public projects;
    mapping(uint256 => uint256) public projectSupply;

    mapping(address => mapping(uint256 => bool)) private _usedNonces;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize() initializer public {
        __ERC1155_init("");
        __AccessControl_init();
        __ERC1155Burnable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
    }

    function createProject(string calldata name, string calldata creator, string calldata tokenUri, uint128 maxSupply) 
        public 
        onlyRole(MANAGER_ROLE)
    {
        projects[nextProjectId++] = ProjectData(false, name, creator, tokenUri, maxSupply);
    }

    function setProjectName(uint256 projectId, string calldata name)
        public
        onlyRole(MANAGER_ROLE) 
    {
        ProjectData memory projectData = projects[projectId];
        require(projectId < nextProjectId && !projectData.locked, "SelectFT: non-existent or locked project");
        projects[projectId].name = name;
    }

    function setProjectCreator(uint256 projectId, string calldata creator)
        public
        onlyRole(MANAGER_ROLE) 
    {
        ProjectData memory projectData = projects[projectId];
        require(projectId < nextProjectId && !projectData.locked, "SelectFT: non-existent or locked project");
        projects[projectId].creator = creator;
    }

    function setProjectTokenUri(uint256 projectId, string calldata tokenUri)
        public
        onlyRole(MANAGER_ROLE)
    {
        ProjectData memory projectData = projects[projectId];
        require(projectId < nextProjectId && !projectData.locked, "SelectFT: non-existent or locked project");
        projects[projectId].tokenUri = tokenUri;
    }

    function setProjectMaxSupply(uint256 projectId, uint128 maxSupply)
        public
        onlyRole(MANAGER_ROLE)
    {
        ProjectData memory projectData = projects[projectId];
        require(projectId < nextProjectId && !projectData.locked, "SelectFT: non-existent or locked project");
        projects[projectId].maxSupply = maxSupply;
    }

    function lockProject(uint256 projectId)
        public
        onlyRole(MANAGER_ROLE)
    {
        ProjectData memory projectData = projects[projectId];
        require(projectId < nextProjectId && !projectData.locked, "SelectFT: non-existent or locked project");
        projects[projectId].locked = true;
    }

    function mint(address to, uint256 projectId, uint128 qty) public onlyRole(MINTER_ROLE) {
        require(projectId < nextProjectId, "SelectFT: project does not exist");

        ProjectData memory projectData = projects[projectId];
        require(!projectData.locked, "SelectFT: project locked");
        require(projectData.maxSupply == 0 || projectSupply[projectId] + qty <= projectData.maxSupply, "SelectFT: project has reached it's max supply");

        projectSupply[projectId] += qty;

        _mint(to, projectId, qty, "");
    }

    function uri(uint256 projectId) public view virtual override returns (string memory) {
        require(projectId < nextProjectId, "SelectFT: project does not exist");
        return projects[projectId].tokenUri;
    }

    function signatureTransfer(address from, address to, uint256 projectId, uint256 qty, uint256 nonce, bytes memory sig) public onlyRole(MANAGER_ROLE) {
        /* CHECKS */
        require(!_usedNonces[msg.sender][nonce], "SelectFT: invalid nonce for signature");

        bytes32 msgHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            keccak256(abi.encodePacked(from, to, projectId, qty, nonce)))
        );
        require(from == msgHash.recover(sig), "SelectFT: invalid signature");

        /* EFFECTS */
        _usedNonces[msg.sender][nonce] = true;

        /* INTERACTIONS */
        _safeTransferFrom(from, to, projectId, qty, "");
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
