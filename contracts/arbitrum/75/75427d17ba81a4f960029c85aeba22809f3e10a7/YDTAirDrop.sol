// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./MerkleProof.sol";
import "./IERC20.sol";
import "./AccessControl.sol";
import "./SafeERC20.sol";

contract YDTAirDrop is AccessControl {
    using SafeERC20 for IERC20;
    IERC20 public token;
    address private treasury;
    bytes32 public merkleRoot;
    mapping(address => bool) public hasClaimed;
    uint256 constant public AIRDROP_AMOUNT = 500000000000000000000;
    uint256 public endDuration;

    event AirDropToken(address indexed _receiver, uint256 indexed _amount);

    constructor(IERC20 _token, bytes32 _merkleRoot, uint256 _duration, address _treasury) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        token = _token;
        merkleRoot = _merkleRoot;
        endDuration = block.timestamp + _duration;
        treasury = _treasury;
    }

    function verify(
        bytes32[] memory proof
    ) public {
        require(!hasClaimed[msg.sender]);
        require(block.timestamp <= endDuration, "Airdrop Closed");
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, AIRDROP_AMOUNT))));
        require(MerkleProof.verify(proof, merkleRoot, leaf), "Invalid proof");
        require(
            token.allowance(treasury, address(this)) >= AIRDROP_AMOUNT,
            "Insufficient allowance"
        );
        hasClaimed[msg.sender] = true;
        token.safeTransferFrom(treasury, msg.sender, AIRDROP_AMOUNT);
        emit AirDropToken(msg.sender, AIRDROP_AMOUNT);
    }

    function updateTreasury(address _treasury) public onlyRole(DEFAULT_ADMIN_ROLE) {
        treasury = _treasury;
    }

}
