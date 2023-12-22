// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Strings.sol";
import "./ERC1155.sol";

contract Booty is ERC1155, Ownable {

    uint256 public constant NUM_CRATES = 3;
    uint256 public constant NUM_ARTIFACT = 15;
    uint256 public constant RARITY_PRECISION = 10000; // Decimal precision of rarity table = 100 / RARITY_PRECISION

    bool public saleEnabled = false;
    bool public craftingEnabled = false;

    uint256[] public artifactIDs;

    struct Crate {
        uint256 price;
        uint256 numMinted;
        uint256 maxSupply;
        uint256 maxMint;
        uint256 minToucan;
        uint256[] rarity;
    }

    struct Ingredient {
        uint256 artifactID;
        uint256 quantity;
    }

    Crate[NUM_CRATES] public crates;

    address immutable toucans;
    
    mapping(address => mapping(uint256 => uint256)) public activated;
    mapping(uint256 => Ingredient[]) public recipes;

    modifier canBuy() {
        require(saleEnabled, "Sale is disabled");
        _;
    }

    modifier canCraft() {
        require(craftingEnabled, "Crafting is disabled");
        _;
    }

    event BuyCrate(address buyer, uint256[] tiers, uint256[] amounts);
    event OpenCrate(address opener, uint256[] tiers, uint256[] amounts);
    event ActivateArtifact(address activator, uint256[] ids, uint256[] amounts);
    event CraftArtifact(address crafter, uint256[] ids, uint256[] amounts);

    constructor(string memory _uri, address _toucans, uint256[NUM_CRATES] memory cratePrice, uint256[NUM_CRATES] memory initialMints, uint256[NUM_CRATES] memory maxSupply, uint256[NUM_CRATES] memory maxMint, uint256[NUM_CRATES] memory minToucan) ERC1155(_uri) {

        toucans = _toucans;
    
        for (uint tier = 0; tier < NUM_CRATES; tier++) {
            crates[tier] = Crate(cratePrice[tier], initialMints[tier], maxSupply[tier], maxMint[tier], minToucan[tier], new uint256[](NUM_ARTIFACT));
            _mint(msg.sender, tier, initialMints[tier], ""); // Future giveaways and promotions
        }

        for(uint i = 0; i < NUM_ARTIFACT; i++){
            artifactIDs.push(i + NUM_CRATES);
        }
    }

    function crateSupply() public view returns (uint256[NUM_CRATES] memory supplies){
        for(uint i = 0; i < NUM_CRATES; i++)
            supplies[i] = crates[i].maxSupply - crates[i].numMinted;
    }

    function buyCrate(uint256[] memory tiers, uint256[] memory amounts) public payable canBuy {

        uint256 paymentOwed = 0;
        require(tiers.length == amounts.length, "Tiers and amounts length must match");

        for (uint i = 0; i < tiers.length; i++) {
            require(amounts[i] <= crates[tiers[i]].maxMint, "Mint amount exceeds limit");
            require(crates[tiers[i]].numMinted + amounts[i] <= crates[tiers[i]].maxSupply, "Mint amount would exceed max supply");
            require(IToucans(toucans).balanceOf(msg.sender) >= crates[tiers[i]].minToucan, "Not enough toucans in wallet");

            paymentOwed += amounts[i] * crates[tiers[i]].price;
            crates[tiers[i]].numMinted += amounts[i];
        }

        require(msg.value == paymentOwed, "Invalid ETH payment sent");
        
        _mintBatch(msg.sender, tiers, amounts, "");

        emit BuyCrate(msg.sender, tiers, amounts);
    }

    function openCrate(uint256[] memory tiers, uint256[] memory amounts) public {

        require(msg.sender == tx.origin, "Cannot open via smart contract");
        require(tiers.length == amounts.length, "Tiers and amounts length must match");

        _burnBatch(msg.sender, tiers, amounts);
        
        for(uint i = 0; i < tiers.length; i++){
            _mintBatch(msg.sender, artifactIDs, revealArtifacts(tiers[i], amounts[i]), "");
        }

        emit OpenCrate(msg.sender, tiers, amounts);
    }

    function activateArtifact(uint256[] memory ids, uint256[] memory amounts) public {

        require(ids.length == amounts.length, "IDs and amounts length must match");

        for(uint i = 0; i < ids.length; i++){
            require(artifactIDs[0] <= ids[i], "Invalid artifact ID");
            activated[msg.sender][ids[i]] += amounts[i];
        }

        _burnBatch(msg.sender, ids, amounts);

        emit ActivateArtifact(msg.sender, ids, amounts);
    }

    function craftArtifact(uint256[] memory ids, uint256[] memory amounts) public canCraft {
        require(ids.length == amounts.length, "Must be equal number of artifacts and amounts");
        Ingredient[] memory recipe;
        for(uint i = 0; i < ids.length; i++){
            recipe = recipes[ids[i]];
            require(recipe.length > 0, "Invalid crafting recipe");
            for(uint j = 0; j < recipe.length; j++){
                _burn(msg.sender, recipe[j].artifactID, recipe[j].quantity * amounts[i]);
            }
            _mint(msg.sender, ids[i], amounts[i], "");
        }

        emit CraftArtifact(msg.sender, ids, amounts);
    }

    function setSale(bool _saleEnabled) external onlyOwner {
        require(!craftingEnabled, "Cannot start sale while activations are enabled");
        saleEnabled = _saleEnabled;
    }

    function setCrafting(bool _craftingEnabled) external onlyOwner {
        craftingEnabled = _craftingEnabled;
    }

    function setCrateRarity(uint256 tier, uint256[NUM_ARTIFACT] memory rarity) external onlyOwner {
        crates[tier].rarity = rarity;
    }

    function setRecipe(uint256 result, uint256[] memory ids, uint256[] memory amounts) external onlyOwner {
        require(ids.length == amounts.length, "Must be equal number of artifacts and amounts");

        Ingredient[] storage recipe = recipes[result];
        while(recipe.length > 0) recipe.pop();

        for(uint i = 0; i < ids.length; i++){
            recipe.push(Ingredient(ids[i], amounts[i]));
        }
    }

    function retrieveFunds() external onlyOwner {
        (bool sent, bytes memory data) = owner().call{value: address(this).balance}("");
        require(sent, "Failed to send Ether");
    }

    function revealArtifacts(uint256 tier, uint256 amount) private view returns (uint256[] memory artifactAmounts) {

        artifactAmounts = new uint256[](NUM_ARTIFACT);
        uint256 seed;

        for(uint i = 0; i < amount; i++){

            seed = uint256(keccak256(
                            abi.encodePacked(msg.sender, tier, i, block.number, block.timestamp, blockhash(block.number))
                        )) % RARITY_PRECISION;
            
            for(uint j = 0; j < crates[tier].rarity.length; j++){
                if(seed <= crates[tier].rarity[j]){
                    artifactAmounts[j]++;
                    break;
                }
            }
        }
    }

    function uri(uint256 _id) public view override returns (string memory) {
        return string(abi.encodePacked(super.uri(_id), Strings.toString(_id)));
    }    
}

interface IToucans {
    function balanceOf(address) external returns (uint256);
}
