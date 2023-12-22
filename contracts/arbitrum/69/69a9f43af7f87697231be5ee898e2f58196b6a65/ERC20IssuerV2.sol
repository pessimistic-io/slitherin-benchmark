// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Ownable.sol";
import "./IERC20.sol";
import "./MerkleProofLib.sol";

error InvalidToken();
error InvalidMerkleProof();
error AllocatedTokensAlreadyClaimed();
error ProjectDoesNotExist();
error CallerNotProjectOwner();
error NoTokensAvailable();
error TokenTransferFailed();
error ProjectAlreadyExist();
error ProjectStartClaimed();

struct Project {
    address token;
    bytes32 root;
    string projectName;
    address projectOwner;
    uint256 allocated;
    uint256 claimed;
}

// ______________________________  _______________    .___                                    ____   ____________
// \_   _____/\______   \_   ___ \ \_____  \   _  \   |   | ______ ________ __   ___________  \   \ /   /\_____  \
//  |    __)_  |       _/    \  \/  /  ____/  /_\  \  |   |/  ___//  ___/  |  \_/ __ \_  __ \  \   Y   /  /  ____/
//  |        \ |    |   \     \____/       \  \_/   \ |   |\___ \ \___ \|  |  /\  ___/|  | \/   \     /  /       \
// /_______  / |____|_  /\______  /\_______ \_____  / |___/____  >____  >____/  \___  >__|       \___/   \_______ \
//         \/         \/        \/         \/     \/           \/     \/            \/                           \/

contract ERC20IssuerV2 is Ownable {
    mapping(IERC20 token => bool supported) public _tokens;
    mapping(string id => Project project) public _projects;

    mapping(address tokenReceiver => mapping(string projectId => uint256 claimedTokens))
        public _claimedTokens;

    event ProjectSet(
        string id,
        address token,
        bytes32 root,
        string projectName,
        address projectOwner,
        uint256 allocated
    );
    event ProjectUpdate(
        string id,
        address token,
        bytes32 root,
        string projectName,
        address projectOwner,
        uint256 allocated
    );

    /// @notice Constructor sets the tokenHolder address and supported tokens.
    /// @param tokens supported tokens.
    constructor(IERC20[] memory tokens) {
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokens[tokens[i]] = true;
        }
    }

    /// @notice Issues tokens to a receiver.
    /// @param id The id of the merkle root.
    /// @param amount The total available of the token to be issued.
    /// @param proof The merkle proof.
    function issueTokens(
        string calldata id,
        uint256 amount,
        bytes32[] calldata proof
    ) external {
        address receiver = msg.sender;
        address token = _projects[id].token;
        uint256 allocated = _projects[id].allocated;
        uint256 claimed = _projects[id].claimed;

        if (token == address(0)) revert ProjectDoesNotExist();
        if(_claimedTokens[msg.sender][id] >= amount) revert NoTokensAvailable();
        if (allocated <= claimed) revert AllocatedTokensAlreadyClaimed();
        if (!_verify(id, _leaf(receiver, address(token), amount), proof)) {
            revert InvalidMerkleProof();
        }

        uint256 availableClaimedTokens =  amount - _claimedTokens[receiver][id];
        _claimedTokens[receiver][id] = amount;
        _projects[id].claimed += availableClaimedTokens;
        IERC20(token).approve(address(this), availableClaimedTokens);
        IERC20(token).transferFrom(address(this), receiver, availableClaimedTokens);
    }

    /// @notice Allows the project owner to reclaim unclaimed tokens.
    /// @dev Reverts if the project does not exist, the caller is not the project owner or the allocated tokens have been claimed.
    /// @param id The id of the project.
    function reclaimTokens(string calldata id) external {
        uint256 allocated = _projects[id].allocated;
        uint256 claimed = _projects[id].claimed;

        if (address(_projects[id].token) == address(0))
            revert ProjectDoesNotExist();
        if (msg.sender != _projects[id].projectOwner)
            revert CallerNotProjectOwner();
        if (allocated <= claimed) revert AllocatedTokensAlreadyClaimed();

        uint256 reclaimAmount = allocated - claimed;
        _projects[id].claimed = allocated;

        IERC20(_projects[id].token).approve(address(this), reclaimAmount);
        IERC20(_projects[id].token).transferFrom(
            address(this),
            _projects[id].projectOwner,
            reclaimAmount
        );
    }

    /// @notice Sets a new project with a specific token, merkle root, project name, project owner and total allocated tokens.
    /// @dev Only callable by the owner of this contract.
    /// @param token The token to be issued.
    /// @param id The id for this project.
    /// @param root The root of the merkle tree.
    /// @param projectName The name of the project.
    /// @param allocated The total allocated tokens for the project.
    function setProject(
        address token,
        string calldata id,
        bytes32 root,
        string memory projectName,
        uint256 allocated
    ) external {
        address projectOwner = msg.sender;
        if (!_tokens[IERC20(token)]) revert InvalidToken();
        if (_projects[id].projectOwner != address(0)) revert ProjectAlreadyExist();
        _projects[id] = Project(
            token,
            root,
            projectName,
            projectOwner,
            allocated,
            0
        );

        IERC20(token).transferFrom(projectOwner, address(this), allocated);

        emit ProjectSet(
            id,
            address(token),
            root,
            projectName,
            projectOwner,
            allocated
        );
    }

    /// @param id The id for this project.
    /// @param root The new root of the merkle tree.
    function updateMerkleRoot(
        string calldata id,
        bytes32 root
    ) external {
        address projectOwner = msg.sender;
        if (_projects[id].projectOwner != projectOwner) revert CallerNotProjectOwner();
        _projects[id].root = root;
    }
    /// @notice Update existed project with a specific token, merkle root, project name, project owner and total allocated tokens.
    /// @dev Only callable by the project owner.
    /// @param token The token to be issued.
    /// @param id The id for this project.
    /// @param root The root of the merkle tree.
    /// @param projectName The name of the project.
    /// @param allocated The total allocated tokens for the project.
    function updateProject(
        address token,
        string calldata id,
        bytes32 root,
        string memory projectName,
        uint256 allocated
    ) external {
        address projectOwner = msg.sender;
        if (!_tokens[IERC20(token)]) revert InvalidToken();
        if (_projects[id].projectOwner != projectOwner) revert CallerNotProjectOwner();
     
        uint256 oldAllocated = _projects[id].allocated;
        address oldTokenAddress= _projects[id].token;
        uint256 claimed = _projects[id].claimed;
        if (claimed > 0) revert ProjectStartClaimed();

        IERC20(oldTokenAddress).transfer(projectOwner, oldAllocated);

        _projects[id] = Project(
            token,
            root,
            projectName,
            projectOwner,
            allocated,
            0
        );

        IERC20(token).transferFrom(projectOwner, address(this), allocated);
        emit ProjectUpdate(
            id,
            address(token),
            root,
            projectName,
            projectOwner,
            allocated
        );
    }

    /// @notice User increase reward token for a existing project  
    /// @param id The project id.
    /// @param amount The total deposit tokens for the project.
    function deposit(string calldata id, uint256 amount) external {
        address projectOwner = msg.sender;
        if (projectOwner != _projects[id].projectOwner)
            revert CallerNotProjectOwner();

        address token = _projects[id].token;
        _projects[id].allocated += amount;
        IERC20(token).transferFrom(projectOwner, address(this), amount);
    } 

    /// @notice Sets a token.
    /// @param token The token to be supported.
    function addToken(IERC20 token) external onlyOwner {
        _tokens[token] = true;
    }

    /// @notice Removes a token.
    /// @param token The token to be removed.
    function removeToken(IERC20 token) external onlyOwner {
        _tokens[token] = false;
    }

    /// @notice Returns a leaf of the merkle-tree.
    /// @param receiver The receiver of the tokens.
    /// @param token The token to be issued.
    /// @param amount The amount of the token to be issued.
    function _leaf(
        address receiver,
        address token,
        uint256 amount
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(receiver, token, amount));
    }

    /// @notice Verifies a given leaf is in the merkle-tree with the given root.
    function _verify(
        string calldata id,
        bytes32 leaf,
        bytes32[] calldata proof
    ) internal view returns (bool) {
        bytes32 root = _projects[id].root;
        return MerkleProofLib.verify(proof, root, leaf);
    }
}

