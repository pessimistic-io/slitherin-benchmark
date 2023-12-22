// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import "./MerkleProof.sol";

interface ILizardToken {
    function awardTokens(address to, uint256 amount) external;
}

contract LizardDistributor {
    ILizardToken public immutable token;
    address public owner;
    mapping(bytes32 => bool) public claims;
    bytes32 public merkleRoot;

    /// Errors ///
    error Unauthorized();
    error AlreadyClaimed();

    /// Events ///
    event OwnershipTransferred(
        address indexed oldOwner,
        address indexed newOwner
    );

    /// Constructor ///
    constructor(ILizardToken _token) {
        token = _token;
        owner = msg.sender;
    }

    /// @notice batch distributes tokens
    /// @param receivers array of addresses to recveive tokens
    /// @param amounts array of amounts to send to receivers
    function distribute(
        address[] calldata receivers,
        uint256[] calldata amounts
    ) external {
        if (msg.sender != owner) revert Unauthorized();

        uint256 length = receivers.length;

        for (uint256 i = 0; i < length; ++i) {
            token.awardTokens(receivers[i], amounts[i]);
        }
    }

    function setMerkleRoot(bytes32 _merkleRoot) external {
        if (msg.sender != owner) revert Unauthorized();

        merkleRoot = _merkleRoot;
    }

    function canClaim(
        address _wallet,
        uint256 _amount,
        string calldata _claimSeries,
        bytes32[] calldata _proof
    ) public view returns (bool) {
        return
            MerkleProof.verify(
                _proof,
                merkleRoot,
                keccak256(abi.encodePacked(_wallet, _amount, _claimSeries))
            );
    }

    function claim(
        uint256 _amount,
        string calldata _claimSeries,
        bytes32[] calldata _proof
    ) external {
        bytes32 claimHash = keccak256(
            abi.encodePacked(msg.sender, _amount, _claimSeries)
        );

        if (claims[claimHash] == true) revert AlreadyClaimed();

        if (canClaim(msg.sender, _amount, _claimSeries, _proof) == false)
            revert Unauthorized();

        claims[claimHash] = true;
        token.awardTokens(msg.sender, _amount);
    }

    /// @notice transfers ownership of the contract to a new address
    /// @param newOwner the address to transfer ownership to
    function transferOwnership(address newOwner) external {
        if (msg.sender != owner) revert Unauthorized();
        owner = newOwner;
        emit OwnershipTransferred(msg.sender, newOwner);
    }
}

