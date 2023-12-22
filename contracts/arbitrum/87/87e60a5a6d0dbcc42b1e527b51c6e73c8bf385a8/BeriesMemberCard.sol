// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./ERC1155.sol";
import "./Ownable.sol";
import "./Pausable.sol";


/**
 * @author Whiterose
 * @title BeRiesMemberCard
 * @dev A contract for the BeRies Member Card
 */
contract BeRiesMemberCard is ERC1155, Ownable, Pausable {
    string public name = "BeRies - Family";
    uint256 private nextTokenID;
    uint256 private totalMinted;
    uint8 private constant MAX_SUPPLY = 11;

    mapping(uint256 => address) private owners;
    mapping(address => uint256[]) private ownedTokens;

    constructor(string memory uri) ERC1155(uri) {
        nextTokenID = 1;
    }

    /**
     * @notice Mint a single token
     * @dev This function allows the caller to mint a NFT.
     * @dev The total number of tokens minted cannot exceed the maximum supply.
     */
    function mint() public whenNotPaused {
        require(totalMinted < MAX_SUPPLY, "Total supply reached");
        uint256 newTokenID = nextTokenID;
        _mint(msg.sender, newTokenID, 1, "");
        owners[newTokenID] = msg.sender;
        ownedTokens[msg.sender].push(newTokenID);
        nextTokenID += 1;
        totalMinted += 1;
    }

    /**
     * @notice Burn the most recently owned token
     * @dev This function allows the caller to burn the most recently owned token.
     * @dev Requires the caller to own at least one token.
     */
    function burn() public whenNotPaused{
        require(ownedTokens[msg.sender].length > 0, "Erreur : Cet utilisateur n'a pas de NFT");
        uint256 tokenId = ownedTokens[msg.sender][ownedTokens[msg.sender].length - 1];
        _burn(msg.sender, tokenId, 1);
        delete owners[tokenId];
        ownedTokens[msg.sender].pop();
    }
    /**
     * @notice Mint a batch of tokens
     * @dev This function allows the contract owner to mint multiple tokens at once.
     * @param tokenIds An array of token IDs to be minted
     * @dev Requires the caller to be the contract owner
     */
    function mintBatch(
        uint256[] memory tokenIds
    ) public onlyOwner whenNotPaused {
        require(
            totalMinted + tokenIds.length <= MAX_SUPPLY,
            "Total supply reached"
        );
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 newTokenID = nextTokenID;
            _mint(msg.sender, newTokenID, 1, "");
            owners[newTokenID] = msg.sender;
            ownedTokens[msg.sender].push(newTokenID);
            nextTokenID += 1;
            totalMinted += 1;
        }
    }

    /**
     * @notice Get the balance of tokens owned by the caller
     * @dev This function returns the number of NFT owned by the caller.
     * @return The number of tokens owned by the caller.
     */
    function getBalance() public view returns (uint256) {
        return ownedTokens[msg.sender].length;
    }
}

