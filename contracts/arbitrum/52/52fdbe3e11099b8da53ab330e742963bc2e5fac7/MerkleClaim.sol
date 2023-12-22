// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.17;

import "./IERC20.sol";
import "./MerkleProof.sol";


error AlreadyClaimed();
error InvalidProof();

contract MerkleDistributor {

    address public immutable token;
    bytes32 public immutable merkleRoot;
    address public owner;

    // This is a packed array of booleans.
    mapping(uint256 => uint256) private claimedBitMap;

    constructor(address token_, bytes32 merkleRoot_) {
        token = token_;
        merkleRoot = merkleRoot_;
        owner = msg.sender;
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
        claimedBitMap[claimedWordIndex] = claimedBitMap[claimedWordIndex] | (1 << claimedBitIndex);
    }

    event Claimed(uint256 index, address account, uint256 amount);

    function claim(uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof)
        public
    {
        if (isClaimed(index)) revert AlreadyClaimed();

        // Verify the merkle proof.
        bytes32 node = keccak256(bytes.concat(keccak256(abi.encode(index, account, amount))));
        if (!MerkleProof.verify(merkleProof, merkleRoot, node)) revert InvalidProof();

        // Mark it claimed and send the token.
        _setClaimed(index);
        IERC20(token).transfer(account, amount);

        emit Claimed(index, account, amount);
    }


    function recoverToken(address _token, uint256 _amount) public {
        require(msg.sender == owner, "unauthorized");

        if(_amount == 0) {
            _amount = IERC20(_token).balanceOf(address(this));
        }

        IERC20(_token).transfer(msg.sender, _amount);
    }
}

