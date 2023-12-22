pragma solidity ^0.8.0;

import "./MerkleProof.sol";

interface ERC721 {
    function mint(address _to) external;

    function totalSupply() external view returns (uint256);

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
}

interface Game {
    function addScore(uint256 id, uint256 score) external;

    function nftToId(address _nft, uint256 _id) external view returns (uint256);

    function giveLife(address nft, uint256 _id) external;
}

contract AdamMerkle {
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

    function claim() external {
        // address user;
        // uint256[] memory scores;
        // bytes32 node = keccak256(params);
        // (user, scores) = abi.decode(params, (address, uint256[]));

        // require(!claimed[user], "already claimed");
        // claimed[user] = true;

        // require(
        //     MerkleProof.verify(merkleProof, merkleRoot, node),
        //     "MerkleDistributor: Invalid proof."
        // );

        cudlPets.mint(address(this));
        game.giveLife(address(cudlPets), cudlPets.totalSupply() - 1);

        uint256 petId = game.nftToId(
            address(cudlPets),
            cudlPets.totalSupply() - 1
        );
        game.addScore(petId, 100); // TODO add id

        cudlPets.safeTransferFrom(
            address(this),
            msg.sender,
            cudlPets.totalSupply() - 1
        );
    }
}

