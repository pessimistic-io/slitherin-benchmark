// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Ownable.sol";
import "./IERC20.sol";
import "./MerkleProofLib.sol";

error InvalidToken();
error InvalidMerkleProof();

// ______________________________  _______________    .___
// \_   _____/\______   \_   ___ \ \_____  \   _  \   |   | ______ ________ __   ___________
//  |    __)_  |       _/    \  \/  /  ____/  /_\  \  |   |/  ___//  ___/  |  \_/ __ \_  __ \
//  |        \ |    |   \     \____/       \  \_/   \ |   |\___ \ \___ \|  |  /\  ___/|  | \/
// /_______  / |____|_  /\______  /\_______ \_____  / |___/____  >____  >____/  \___  >__|
//         \/         \/        \/         \/     \/           \/     \/            \/

contract ERC20Issuer is Ownable {
    mapping(IERC20 token => bool supported) public _tokens;
    mapping(uint256 id => bytes32 root) public _roots;
    mapping(uint256 id => string projectName) public _projectNames;

    address public _tokenHolder;
    uint256 public _id; // id of the latest root added.

    /// @notice Constructor sets the tokenHolder address and supported tokens.
    /// @param tokenHolder The address that holds the tokens to be issued.
    /// @param tokens supported tokens.
    constructor(address tokenHolder, IERC20[] memory tokens) {
        _tokenHolder = tokenHolder;
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokens[tokens[i]] = true;
        }
    }

    /// @notice Sets the tokenHolder address.
    /// @param tokenHolder The address that holds the tokens to be issued.
    function setTokenHolder(address tokenHolder) external onlyOwner {
        _tokenHolder = tokenHolder;
    }

    /// @notice Sets a token.
    /// @param token The token to be supported.
    function setToken(IERC20 token) external onlyOwner {
        _tokens[token] = true;
    }

    /// @notice Removes a token.
    /// @param token The token to be removed.
    function removeToken(IERC20 token) external onlyOwner {
        _tokens[token] = false;
    }

    /// @notice Adds a merkle root.
    /// @param root The merkle root.
    function addRoot(bytes32 root) external onlyOwner {
        ++_id;
        _roots[_id] = root;
    }

    /// @notice Updates a merkle root.
    /// @param id The id of the merkle root.
    /// @param root The merkle root.
    function updateRoot(uint256 id, bytes32 root) external onlyOwner {
        _roots[id] = root;
    }

    /// @notice Sets a project name.
    /// @param id The id of the project.
    /// @param name The project name.
    function setProjectName(uint256 id, string memory name) external onlyOwner {
        _projectNames[id] = name;
    }

    /// @notice Issues tokens to a receiver.
    /// @param id The id of the merkle root.
    /// @param token The token to be issued.
    /// @param amount The amount of the token to be issued.
    /// @param proof The merkle proof.
    function issueTokens(
        uint256 id,
        IERC20 token,
        uint256 amount,
        bytes32[] calldata proof
    ) external {
        address receiver = msg.sender;
        if (!_tokens[token]) revert InvalidToken();
        if (!_verify(id, _leaf(receiver, address(token), amount), proof)) {
            revert InvalidMerkleProof();
        }
        IERC20(token).transferFrom(_tokenHolder, receiver, amount);
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
        uint256 id,
        bytes32 leaf,
        bytes32[] calldata proof
    ) internal view returns (bool) {
        bytes32 root = _roots[id];
        return MerkleProofLib.verify(proof, root, leaf);
    }
}

