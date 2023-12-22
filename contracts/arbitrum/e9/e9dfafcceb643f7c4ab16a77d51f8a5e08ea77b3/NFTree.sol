// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721Enumerable.sol";
import "./ECDSA.sol";
import "./Ownable.sol";
import "./NFTreeLibrary.sol";
import "./IERC20.sol";

contract NFTree is ERC721Enumerable, Ownable {

    using NFTreeLibrary for uint8;
    using ECDSA for bytes32;

    struct Trait {
        string traitName;
        string traitType;
        string pixels;
        uint256 pixelCount;
    }
    
    // Price
    uint256 public price = 0.02 ether;

    //Mappings
    mapping(uint256 => Trait[]) public traitTypes;
    mapping(uint256 => string) internal tokenIdToHash;
    mapping(uint256 => uint256) internal tokenIdToChristmasSpiritCount;
    mapping(address => uint256) public priceInToken;

    //uint256s
    uint256 public MAX_SUPPLY = 6000;
    uint256 public MAX_RESERVE = 30;
    uint256 SEED_NONCE = 0;

    //string arrays
    string[] LETTERS = [
        "a",
        "b",
        "c",
        "d",
        "e",
        "f",
        "g",
        "h",
        "i",
        "j",
        "k",
        "l",
        "m",
        "n",
        "o",
        "p",
        "q",
        "r",
        "s",
        "t",
        "u",
        "v",
        "w",
        "x",
        "y",
        "z"
    ];

    //uint arrays
    uint16[][4] TIERS;

    address _owner;
    address _santaClause = 0x5cAce277eEC49e93Aa8c321d14D84ADb1d495e23;


    uint256 public privateAmountMinted;
    bool public saleLive;

    event LightTreeUp(uint256 tokenId, address account);
  
    
    constructor() ERC721("Christmas NFTree", "TREE") {
        _owner = msg.sender;
       //Declare all the christmasSpirit tiers
        //Tree
        TIERS[0] = [1000, 1000, 1000, 1000, 1000, 1000, 4000];  

        //Lights
        TIERS[1] = [1000, 1000, 2000, 2000, 2000, 2000];

        // Base   
        TIERS[2] = [1000, 2000, 2000, 2000, 3000];
        
        // Tinsel
        TIERS[3] = [1000, 1500, 1500, 2000, 2000, 2000];

    }

    /**
     * @dev Converts a digit from 0 - 10000 into its corresponding christmasSpirit based on the given christmasSpirit tier.
     * @param _randinput The input from 0 - 10000 to use for christmasSpirit gen.
     * @param _christmasSpiritTier The tier to use.
     */
    function treeGeneration(uint256 tokenId, uint256 _randinput, uint8 _christmasSpiritTier)
        internal
        returns (string memory)
    {
        uint16 currentLowerBound = 0;
        for (uint8 i = 0; i < TIERS[_christmasSpiritTier].length; i++) {
            uint16 thisPercentage = TIERS[_christmasSpiritTier][i];
            if (
                _randinput >= currentLowerBound &&
                _randinput < currentLowerBound + thisPercentage
            ) {
                setTokenIdChristmasSpirit(tokenId, i * 5);
                return i.toString();
            }
            currentLowerBound = currentLowerBound + thisPercentage;
        }

        revert();
    }

    /**
     * @dev Generates a 7 digit hash from a tokenId, address, and random number.
     * @param _t The token id to be used within the hash.     
     * @param _a The address to be used within the hash.
     * @param _c The custom nonce to be used within the hash.
     */
    function hash(
        uint256 _t,
        address _a,
        uint256 _c
    ) internal returns (string memory) {
        require(_c < 10);
        // This will generate a 7 character string.
        // The last 6 digits are random, the first is 0, due to the chain is not being burned.
        string memory currentHash = "";            
        SEED_NONCE++;
        uint256 _largerandom = 
                uint256(
                    keccak256(
                        abi.encodePacked(
                            block.timestamp,
                            block.difficulty,
                            _t,
                            _a,
                            _c,
                            SEED_NONCE
                        )
                    )
                );
             
         for (uint8 i = 0; i < 4; i++) {            
            uint16 _randinput = uint16(_largerandom % 10000);
            _largerandom = _largerandom / 10000;     

            currentHash = string(
                abi.encodePacked(currentHash, treeGeneration(_t, _randinput, i))
            );
        } 

        return currentHash;
    }
    /**
     * @dev Changes the price
     */
    function changePrice(uint256 _newPrice) public onlyOwner {
        price = _newPrice;
    }

    /**
     * @dev changes the price in a token
     * @param token token you want to change the price for
     * @param _price the price you want the token to be
     */
    function changePriceInToken(address token, uint256 _price) external onlyOwner {
        priceInToken[token] = _price;
    }

    /**
     * @dev gets the price
     */
    function getPrice() public view returns (uint256) {
        return price;
    }

    
    function lightTree() external payable {
        require(price <= msg.value, "INSUFFICIENT_ETH");

        mintInternal(); 

        payable(_santaClause).transfer(address(this).balance);

    }

    function lightTreeWithToken(address token) external {       
        require(priceInToken[token] > 0, "TOKEN_NOT_ALLOWED");

        require(IERC20(token).transferFrom(msg.sender, _santaClause, priceInToken[token]), "TOKEN_NOT_PAID");

        mintInternal(); 

    }

    /**
     * @dev Mint internal, this is to avoid code duplication.
     */
    function mintInternal() internal {
        require(saleLive, "SALE_CLOSED");

        uint256 _totalSupply = totalSupply();
        require(_totalSupply < MAX_SUPPLY);

        require(!NFTreeLibrary.isContract(msg.sender));

        uint256 thisTokenId = _totalSupply;

        tokenIdToHash[thisTokenId] = hash(thisTokenId, msg.sender, 0); 

        _mint(msg.sender, thisTokenId);  
 
        emit LightTreeUp(_totalSupply, msg.sender); 
    } 
    
    function mintReserve() onlyOwner external  {
        privateAmountMinted++;
        require(privateAmountMinted < MAX_RESERVE); // Reserved for teams and giveaways
         mintInternal(); 
    }

    /**
     * @dev Adds to christmasSpirit count if christmasSpirit is great enough     
     * @param tokenId the token to edit ChristmasSpirit count for
     * @param index position in the current TIER * 5
     */
    function setTokenIdChristmasSpirit(uint256 tokenId, uint256 index) internal {
         if (index < 20) {  
           uint256 cScore = (20 - index);
           tokenIdToChristmasSpiritCount[tokenId] += cScore; 
        }
    }


    function withdraw() external onlyOwner {
        payable(_santaClause).transfer(address(this).balance);
    }


    /**
     * @dev Helper function to reduce pixel size within contract
     */
    function letterToNumber(string memory _inputLetter)
        internal
        view
        returns (uint8)
    {
        for (uint8 i = 0; i < LETTERS.length; i++) {
            if (
                keccak256(abi.encodePacked((LETTERS[i]))) ==
                keccak256(abi.encodePacked((_inputLetter)))
            ) return (i + 1);
        }
        revert();
    }


   /**
     * @dev Hash to SVG function
     */
    function hashToSVG(string memory _hash)
        public
        view
        returns (string memory)
    {
        string memory svgString;
        string memory treeColor;

        bool[24][24] memory placedPixels;

         uint8 treeIndex =  NFTreeLibrary.parseInt(NFTreeLibrary.substring(_hash, 0, 1)); // BG 

        if ( treeIndex == 0 ) {
            // white
            treeColor = "fff8ed";
        } else if ( treeIndex == 1 ) {    
            // violet
            treeColor = "d4c0ff";
        } else if ( treeIndex == 2 ) {
            // pink
            treeColor = "f8e0da";
        } else if ( treeIndex == 3 ) {            
            // golden
            treeColor = "fcffc0";
        } else if ( treeIndex == 4 ) {
            // blue
            treeColor = "c0dbff";
        } else if ( treeIndex == 5 ) {
            // lime
            treeColor = "ddffc5";
        } else if ( treeIndex == 6 ) {
            // green
            treeColor = "42c831";
        }  

        // starts at 1 because index 0 is the tree colour
        for (uint8 i = 1; i < 4; i++) {  
            uint8 thisTraitIndex = NFTreeLibrary.parseInt(
                NFTreeLibrary.substring(_hash, i, i + 1)
            );

            for (
                uint16 j = 0;
                j < traitTypes[i][thisTraitIndex].pixelCount; 
                j++
            ) {
                string memory thisPixel = NFTreeLibrary.substring(
                    traitTypes[i][thisTraitIndex].pixels,
                    j * 4,
                    j * 4 + 4
                );

                uint8 x = letterToNumber(
                    NFTreeLibrary.substring(thisPixel, 0, 1)
                );
                uint8 y = letterToNumber(
                    NFTreeLibrary.substring(thisPixel, 1, 2)
                );

                if (placedPixels[x][y]) continue;

                svgString = string(
                    abi.encodePacked(
                        svgString,
                        "<rect class='c",
                        NFTreeLibrary.substring(thisPixel, 2, 4),
                        "' x='",
                        x.toString(),
                        "' y='",
                        y.toString(),
                        "'/>"
                    )
                );

                placedPixels[x][y] = true;
            }
        }

        svgString = string(
            abi.encodePacked(
                '<svg id="c" xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 19 26" > ',
                "<rect class='c21' x='9' y='4'/><rect class='c21' x='10' y='5'/><rect class='c21' x='8' y='6'/><rect class='c21' x='10' y='6'/><rect class='c21' x='7' y='7'/><rect class='c21' x='8' y='7'/><rect class='c21' x='9' y='7'/><rect class='c21' x='7' y='8'/><rect class='c21' x='10' y='8'/><rect class='c21' x='11' y='8'/><rect class='c21' x='8' y='9'/><rect class='c21' x='9' y='9'/><rect class='c21' x='10' y='9'/><rect class='c21' x='11' y='9'/><rect class='c21' x='6' y='10'/><rect class='c21' x='7' y='10'/><rect class='c21' x='8' y='10'/><rect class='c21' x='9' y='10'/><rect class='c21' x='12' y='10'/><rect class='c21' x='5' y='11'/><rect class='c21' x='6' y='11'/><rect class='c21' x='10' y='11'/><rect class='c21' x='12' y='11'/><rect class='c21' x='13' y='11'/><rect class='c21' x='5' y='12'/><rect class='c21' x='8' y='12'/><rect class='c21' x='9' y='12'/><rect class='c21' x='10' y='12'/><rect class='c21' x='11' y='12'/><rect class='c21' x='12' y='12'/><rect class='c21' x='6' y='13'/><rect class='c21' x='7' y='13'/><rect class='c21' x='8' y='13'/><rect class='c21' x='9' y='13'/><rect class='c21' x='10' y='13'/><rect class='c21' x='13' y='13'/><rect class='c21' x='14' y='13'/><rect class='c21' x='4' y='14'/><rect class='c21' x='5' y='14'/><rect class='c21' x='6' y='14'/><rect class='c21' x='8' y='14'/><rect class='c21' x='12' y='14'/><rect class='c21' x='13' y='14'/><rect class='c21' x='14' y='14'/><rect class='c21' x='3' y='15'/><rect class='c21' x='5' y='15'/><rect class='c21' x='6' y='15'/><rect class='c21' x='9' y='15'/><rect class='c21' x='10' y='15'/><rect class='c21' x='11' y='15'/><rect class='c21' x='12' y='15'/><rect class='c21' x='13' y='15'/><rect class='c21' x='3' y='16'/><rect class='c21' x='4' y='16'/><rect class='c21' x='7' y='16'/><rect class='c21' x='8' y='16'/><rect class='c21' x='9' y='16'/><rect class='c21' x='10' y='16'/><rect class='c21' x='11' y='16'/><rect class='c21' x='15' y='16'/><rect class='c02' x='9' y='17'/><rect class='c02' x='9' y='18'/>",
                svgString,
                "<style>rect{width:1px;height:1px;}.c00{fill:#e39090}.c01{fill:#ac3231}.c02{fill:#663931}.c03{fill:#ff3600}.c04{fill:#00ff1b}.c05{fill:#1b00ff}.c06{fill:#f2ff00}.c07{fill:#ac3232}.c08{fill:#983030}.c09{fill:#fcffc0}.c10{fill:#b2dd93}.c11{fill:#fff200}.c12{fill:#fff8ed}.c13{fill:#ffad51}.c14{fill:#c0dbff}.c15{fill:#e3e3e3}.c16{fill:#ddffc5}.c17{fill:#7cdd90}.c18{fill:#ddd768}.c19{fill:#b071b3}.c20{fill:#a631ac}.c21{fill:#",treeColor,"}.c22{fill:#fff651}.c23{fill:#bc9dff}.c24{fill:#98e4ff}.c25{fill:#d4c0ff}.c26{fill:#ff7070}.c27{fill:#f8e0da}.c28{fill:#51ff63}.c29{fill:#99e550}.c30{fill:#5fcde4}.c31{fill:#d77bba}.c32{fill:#857bd7}.c33{fill:#df7426}</style></svg>")
        );

        return svgString;
    }

    /**
     * @dev Hash to metadata function
     */
    function hashToMetadata(string memory _hash, uint256 _tokenId)
        public
        view
        returns (string memory)
    {
        string memory metadataString;

        for (uint8 i = 0; i < 4; i++) { 
            uint8 thisTraitIndex = NFTreeLibrary.parseInt(
                NFTreeLibrary.substring(_hash, i, i + 1)
            );

            metadataString = string(
                abi.encodePacked(
                    metadataString,
                    '{"trait_type":"',
                    traitTypes[i][thisTraitIndex].traitType,
                    '","value":"',
                    traitTypes[i][thisTraitIndex].traitName,
                    '"},'
                )
            );
          
        }

        metadataString = string(abi.encodePacked(metadataString, '{"display_type": "spirit", "trait_type": "Christmas Spirit", "value":',NFTreeLibrary.toString(tokenIdToChristmasSpiritCount[_tokenId]),'}'));

        return string(abi.encodePacked("[", metadataString, "]"));
    }

    /**
     * @dev Returns the SVG and metadata for a token Id
     * @param _tokenId The tokenId to return the SVG and metadata for.
     */
    function tokenURI(uint256 _tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_exists(_tokenId));

        string memory tokenHash = _tokenIdToHash(_tokenId);

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    NFTreeLibrary.encode(
                        bytes(
                            string(
                                abi.encodePacked(
                                    '{"name": "NFTree #',
                                    NFTreeLibrary.toString(_tokenId),
                                    '", "description": "A digital christmas tree for lighting a real one", "image": "data:image/svg+xml;base64,',
                                    NFTreeLibrary.encode(
                                        bytes(hashToSVG(tokenHash))
                                    ),
                                    '","attributes":',
                                    hashToMetadata(tokenHash, _tokenId),
                                    "}"
                                )
                            )
                        )
                    )
                )
            );
    }

    /**
     * @dev Returns a hash for a given tokenId
     * @param _tokenId The tokenId to return the hash for.
     */
    function _tokenIdToHash(uint256 _tokenId)
        public
        view
        returns (string memory)
    {
        string memory tokenHash = tokenIdToHash[_tokenId];
        //If this is a burned token, override the previous hash
        if (ownerOf(_tokenId) == 0x000000000000000000000000000000000000dEaD) {
            tokenHash = string(
                abi.encodePacked(
                    "1",
                    NFTreeLibrary.substring(tokenHash, 1, 5)
                )
            );
        }

        return tokenHash;
    }



    /**
     * @dev Returns the number of rare assets of a tokenId
     * @param _tokenId The tokenId to return the number of rare assets for.
     */
    function getTokenChristmasSpiritCount(uint256 _tokenId)
        public
        view
        returns (uint256)
    {
        return tokenIdToChristmasSpiritCount[_tokenId];
    }

    /**
     * @dev Returns the wallet of a given wallet. Mainly for ease for frontend devs.
     * @param _wallet The wallet to get the tokens of.
     */
    function walletOfOwner(address _wallet)
        public
        view
        returns (uint256[] memory)
    {
        uint256 tokenCount = balanceOf(_wallet);

        uint256[] memory tokensId = new uint256[](tokenCount);
        for (uint256 i; i < tokenCount; i++) {
            tokensId[i] = tokenOfOwnerByIndex(_wallet, i);
        }
        return tokensId;
    }

    function toggleSaleStatus() external onlyOwner {
        saleLive = !saleLive;
    }


    /**
     * @dev Add a trait type
     * @param _traitTypeIndex The trait type index
     * @param traits Array of traits to add
     */

    function addTraitType(uint256 _traitTypeIndex, Trait[] memory traits)
        public
        onlyOwner
    {
        for (uint256 i = 0; i < traits.length; i++) {
            traitTypes[_traitTypeIndex].push(
                Trait(
                    traits[i].traitName,
                    traits[i].traitType,
                    traits[i].pixels,
                    traits[i].pixelCount
                )
            );
        }

        return;
    }

}
