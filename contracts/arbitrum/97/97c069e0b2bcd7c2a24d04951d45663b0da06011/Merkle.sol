pragma solidity ^0.8.0;

import "./MerkleProof.sol";

interface ERC721 {
    function mint(address _to) external;

    function totalSupply() external view returns (uint256);
}

interface Game {
    function addScore(uint256 id, uint256 score) external;

    function nftToId(address _nft, uint256 _id) external view returns (uint256);

    function giveLife(address nft, uint256 _id) external;
}

contract Merkle {
    bytes32 public immutable merkleRoot;
    mapping(address => bool) claimed;

    ERC721 public cudlPets;
    Game public game;

    constructor(
        bytes32 merkleRoot_,
        address _game,
        address _cudlPets
    ) {
        merkleRoot = merkleRoot_;
        cudlPets = ERC721(_cudlPets);
        game = Game(_game);
    }

    function claim(bytes calldata params, bytes32[] calldata merkleProof)
        external
    {
        address user;
        uint256[] memory scores;
        bytes32 node = keccak256(params);
        (user, scores) = abi.decode(params, (address, uint256[]));

        require(!claimed[user], "already claimed");
        claimed[user] = true;

        require(
            MerkleProof.verify(merkleProof, merkleRoot, node),
            "MerkleDistributor: Invalid proof."
        );

        for (uint256 i; i < scores.length; i++) {
            cudlPets.mint(user);
            game.giveLife(address(cudlPets), cudlPets.totalSupply() - 1);

            uint256 petId = game.nftToId(
                address(cudlPets),
                cudlPets.totalSupply() - 1
            );
            game.addScore(petId, scores[i]); // TODO add id
        }
    }
}

