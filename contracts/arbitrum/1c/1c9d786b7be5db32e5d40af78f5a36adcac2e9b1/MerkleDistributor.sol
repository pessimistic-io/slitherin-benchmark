// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.6.11;

import "./IERC20.sol";
import "./MerkleProof.sol";
import "./IMerkleDistributor.sol";

contract MerkleDistributor is IMerkleDistributor {
    bool public immutable isNativeToken;
    address public immutable override token;
    bytes32 public immutable override merkleRoot;
    address private immutable owner;

    // This is a packed array of booleans.
    mapping(uint256 => uint256) private claimedBitMap;

    constructor(bool isNativeToken_, address token_, bytes32 merkleRoot_) public {
        isNativeToken = isNativeToken_;
        token = token_;
        merkleRoot = merkleRoot_;
        owner = msg.sender;
    }

    modifier onlyOwner {
      require(msg.sender == owner);
      _;
   }

    function sweepToken(address _token, bool _isNativeToken) external onlyOwner {
        if(_isNativeToken){
            (bool success, ) = msg.sender.call{value: address(this).balance}("");
            require(success,'MerkleDistributor: Native token transfer failed.');
        } else {
            require(IERC20(_token).balanceOf(address(this)) > 0, "MerkleDistributor: no token to sweep");
            IERC20(_token).transfer(owner, IERC20(_token).balanceOf(address(this)));
        }
    }

    function isClaimed(uint256 index) public view override returns (bool) {
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

    function claim(uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof) external override {
        require(!isClaimed(index), 'MerkleDistributor: Drop already claimed.');

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, account, amount));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), 'MerkleDistributor: Invalid proof.');

        // Mark it claimed and send the token.
        _setClaimed(index);
        if(isNativeToken){
            (bool success, ) = account.call{value: amount}("");
            require(success,'MerkleDistributor: Native token transfer failed.');
        } else {
            require(IERC20(token).transfer(account, amount), 'MerkleDistributor: Transfer failed.');
        }   
        emit Claimed(index, account, amount);
    }

    // needed to recieve MATIC
    receive() external payable {}
}

