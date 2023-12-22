// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IGFly.sol";
import "./MerkleProof.sol";
import "./Ownable.sol";

//MMMMWKl.                                            .:0WMMMM//
//MMMWk,                                                .dNMMM//
//MMNd.                                                  .lXMM//
//MWd.    .','''....                         .........    .lXM//
//Wk.     ';......'''''.                ..............     .dW//
//K;     .;,         ..,'.            ..'..         ...     'O//
//d.     .;;.           .''.        ..'.            .'.      c//
//:       .','.           .''.    ..'..           ....       '//
//'         .';.            .''...'..           ....         .//
//.           ';.             .''..             ..           .//
//.            ';.                             ...           .//
//,            .,,.                           .'.            .//
//c             .;.                           '.             ;//
//k.            .;.             .             '.            .d//
//Nl.           .;.           .;;'            '.            :K//
//MK:           .;.          .,,',.           '.           'OW//
//MM0;          .,,..       .''  .,.       ...'.          'kWM//
//MMMK:.          ..'''.....'..   .'..........           ,OWMM//
//MMMMXo.             ..'...        ......             .cKMMMM//
//MMMMMWO:.                                          .,kNMMMMM//
//MMMMMMMNk:.                                      .,xXMMMMMMM//
//MMMMMMMMMNOl'.                                 .ckXMMMMMMMMM//

contract BattleflyMerkleDistributor is Ownable {
    uint256 public CLAIM_CAP;

    address public token;
    bytes32 public merkleRoot;
    uint256 public claimed = 0;

    // This is a packed array of booleans.
    mapping(uint256 => uint256) private claimedBitMap;

    // This event is triggered whenever a call to #claim succeeds.
    event Claimed(uint256 index, address account, uint256 amount, string reason);

    constructor(address token_, bytes32 merkleRoot_, uint256 claimCap_) {
        token = token_;
        merkleRoot = merkleRoot_;
        CLAIM_CAP = claimCap_;
    }

    function isClaimed(uint256 index) public view  returns (bool) {
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

    function claim(uint256 index, address account, uint256 amount, string calldata reason, bytes32[] calldata merkleProof) external  {
        require(!isClaimed(index), 'BattleflyMerkleDistributor:DROP_ALREADY_CLAIMED');
        require((claimed + amount) <= CLAIM_CAP, 'BattleflyMerkleDistributor:MAX_CLAIM_CAP_REACHED');

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, account, amount, reason));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), 'BattleflyMerkleDistributor:INVALID_PROOF');

        // Mark it claimed and send the token.
        _setClaimed(index);
        IGFly(token).mint(account, amount);
        claimed += amount;

        emit Claimed(index, account, amount, reason);
    }
}

