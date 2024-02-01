// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNXXXNNNNNNNNNNWWWNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNWWNNNXXXXx;''',,,;;;:::cclod0NWNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNXKOxolc:;,'''''. .,;,,,,,,'''''.. .lddddxkO0XNNWNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN0xl:'..',;ccloooddd:. ........'''....  .,'''''''',:ldkKNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNNNNNNNNNXOo,..,coxOKXXXXXXXXKKX0xolllccccccccccclloOKKKK00Okdoc;'..,cdOXNNNNNNNNNNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNNNNNNNXx;..cdOKXNNNWNXXKKXXKKXKKXXXXXXXXXXXXXXXXXXXKKKKKKKKKXXXKKOxl;'.'cxKNNNNNNNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNNNNNXx,.,oold0NWWNNXXXXXKXKKKKXXXKKXKKKKKKKKKKXXKKKKKKKKKKKKKKKKKKKXX0kl,..ckXNNNNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNNNNO;.'dOl',,c0NXXXNWWNXKKXXKXXKKKKKKKKKKKKKKKXKKKKKKKXXKKXKXKKKKKKKKKK00kl..;kNNNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNNNx..c0Ko'ckl'oXNNWNNXXKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKXKx:;;:dOo..lKNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNXo..dKX0c;x0l'lXWNXXKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKXx,'lo,'oKk, :KNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNXl.'kKXNO;:x0o,lKXKKKKKKKXKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKXKKX0c.ckOd''xXO; cXNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNXl.'kXXNNx':k0x,:OXKKKKKXKKKKKKXXXXXXXXKKKKKKXXXXXXXXXKKKKXKKKKKXKKKXk,'oOOk:.lKXx..dNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNd..xXXNWXc.lOOo';OXKKKKXXXKK0OkxdoollccccccccccclloodxkO0KXXKKKXKKXKXd',xOOOl.:0XKc ;KWNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNk..oKXNWWO,'dOOo.;OXKK0Oxol:;;,,;;:::ccclllllllccc:::;;,,;:ldk0KXKKKXKo.:kOOOo';OXXk..xWNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNWK; cKXXWWNd.;kOOl.;xkoc;,,;clodxkkOOOOOOOOOOOOOOOOOOOOOkkdoc:,,;:ok0KXKc.ckOOOd',kXX0; cNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNo.'OXXNWNKc.cOOOl.',,;codolcccoxOOOOOOOOOOOOOOOOOOOOxdoodkOOOkxoc;,;cxOc.ckOOOx,'xXKKl ;KWNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNW0, lKXXWWNO;'dOOOc.,oxkOd;'.....,dOOOOOOOOOOOOOOOOOd:'....,lxkOOOOOxo:,,,.:kOOOx;.dXKXd.'OWNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNo.'OXKXNNXx,;kOOkc.ckOOx,.'......ckOOOOOOOOOOOOOOOo'....','',;:lxOOOOOxl;.:kOOOk:.oKKXx..kWNNNNNNNNNNNNNN
// NNNNNNNNNNNNNWK; cKXKXXX0c'cOOOk:.lOOOd;,,.';'.,dOOOOOOOOOOOOOOOk:.,cc;,;',:,,,'ckOOOOOl.;kOOOk:.lKKXk..xWNNNNNNNNNNNNNN
// NNNNNNNNNNNNNWO..xXKXXKx;':xOOOk:'oOOOOd:'..:;;dOOOOOOOOOOOOOOOOOd;,;'..'::,.:c,.lOOOOOxldOOOOkc.lKKXk'.xWNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNd.'OXKK0o',okOOOOOdokOkxdddxd;:c;lOOOOOOOOOOOOOOOOOkxlclldxOOo.,o:.cOOOOOOOOOOOOOc.c0XXk'.xWNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNl ,0XX0c';dOOOOOOOOOkl;'..',cc;:::xOOOOOOOOOOOOOOdc;,',;lxOOOd'';;cxOOOOOOOOOOOOOl.:0XXk..kWNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNc ;KX0l.;xOOOOOkdool:'.......cxooxOOOOOOOOOOOOkkl'.......ckOOOxodkOOOOOOOOOOOOOOOd',kXXd.'OWNNNNNNNNNNNNNN
// NNNNNNNNNNNNWX: :KXd',dOOOOOkl;,;;,,,'....'oOOOOOOOOOOOOOxlcc;,,''''...:kOOOOOOOOOOOOOOOOOOOOOOx;'dKKc ;KWNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNc ;K0:.lOOOOOOOdoddd:.';'..,okOOOOOOOOOOOOx:,;:;;,..',.':xOOOOOOOOOOOOOOOOOOOOOOOkc.:00, lNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNo ,Ox',xOOOOOOOOOOOOkdolcldkOOOOOOOOOOOOOOdc:cldkdc::cldkOOOOOOOOOOOOOOOOOOOOOOOOOo';Ox..kWNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNWk..dl.ckOOOOOOOOOOOOkddxkOklcllxOOOOOOOOOOOkkOOOxollodkOOOOOOOOOOOOOOOOOOOOOOOOOOOo';k; cXWNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNX: ;;.lOOOOOOOOOOko:,'..,cdc;c,lOOOOOOOOOOOOOxl:'.....:xOOOOOOOOOOOOOOOOOOOOOOOOOOl.:c.'OWNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNx..,.ckOOOOOOOOkc........:c:l:oOOOOOOOOOOOOx;.........cOOOOOOOOOOOOOOOOOOOOOOOOOx;';..dNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNWX: ..;kK0OOOOOOx,.',''''';:::lkOOOOOOOOOOOOd'...',...,oOOOOOOOOOOOOOOOOOOOOOOOOkc''..oNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNO' .'oKK0OOOOOkl;:,.';,;cc:okOOOOOOOOOOOOOkl:,.':;':dOOOOOOOOOOOOOOOOOOOOOOOOkc'...oXNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNk. .,dKK0OOOOOOxlccloddoxkOOOOOOOOOOOOOOOOOOkd:;;:xOOOOOOOOOOOOOOOOOOOOOdlll;.. .xXNNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNk' .':cccoxOOOOOOOOOOOOOOOOOkdlcloxOOOOOOOOOkc;;lOOOOOOOOOOOOOOkocclkOo',c,. .c0NNNNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNN0;  .;xl,:llolcokxlloxdlcll;.....,dOOOOOOOOkc:okOOOOOOOOOOOOOk:,ll,,:,.;:..;kXNNNNNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNKo. .;,,:c,,lo;,,,,''',c,........,clc::::okkkOOOkxxkkxoodkOOd,;ol,''.  .;kXNNNNNNNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNNN0c.  .;c;,cl;.'::'.'dOl........:c''dx;.'cdddol::::;;;'':oxo,.,.... . .,kNNNNNNNNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNNNNN0o,   ..;k0l,:c:'.,,..:l,.;c;',',;,,,::',;,.,do'.:l:;c:,..''   .':;. .dXNNNNNNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNNNNNNNx. .. .,:''oOd,.,l:.';;':l;..::'.';:;.,c;','..;;',oOo.   ..,;.....  .'l0NNNNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNNNNNNX: .::'.    .'...,dc..;l:.,odc',cl;..;l;.,xk:.;dl.........,c:;'.  .,:,...l0NNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNNNNNNXc  ....,:,'..        ....'ll,.,lo;..;c'..;,.  .. ..,;::,.......';:cccc;. 'xNNNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNNNNNKl.....  ..',;,..,,,''..   ....   ........ ..'',,..';,'... ..',;ccccccccc:,..lXNNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNNNN0:..;cc:,'.....   ...'''...',,,,...,,,,,,,. .''....  ....',;:ccccccccccccccc,..lXNNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNNN0; .;cccccccc::;,,''..............................'',,;:cccccccccccccccccccccc;..lXNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNNXc .;cccccccccccccccccccccc::::::::;;:::::::::cccccccccccccccccccccccccccccccccc,..dNNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNNx..,ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' .kNNNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNWX: .:ccccc::cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc:. ,0WNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNk. ,ccccc;.':cccccccccccccccccccccccccccccccccccccccccccccccccccc:::ccccccccccccccc,. lXNNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNNl .:cccc:' .:ccccccccccccccccccccccccccccccccccccccccccccccccccc:'.':cccccccccccccc:' .kWNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNW0' 'ccccc:. 'ccccccccccccccccccccccccccccccccccccccccccccccccccccc,. 'ccccccccccccccc:. ;KWNNNNNNNNNN
// NNNNNNNNNNNNNNNNNNNo..;ccccc;. 'ccccccccccccccccccccccccccccccccccccc:,,,;;:;,'...;cc:. .;ccccccccccccccc,..dNNNNNNNNNNN
// NNNNNNNNNNNNNNNNNWX: .:ccccc;..,ccccccccccccccccccccccccccccccccccccc'  .......'. .ccc;. 'ccccccccccccccc:. ,0WNNNNNNNNN
// NNNNNNNNNNNNNNNNNWO' ,cccccc, .;cccccccccccccccccccccccccccccccccccc:. 'oollodxk: .;cc:' .;ccccccccccccccc;. lXNNNNNNNNN
// NNNNNNNNNNNNNNNNNNx. ...''''. .;cccccccccccccccccccccccccccccccccccc:. ,dloxdllol. ,ccc,. 'ccccccccc:::;;,'. .xNNNNNNNNN
// NNNNNNNNNNNNNNNNNNl .;;;,,;,. .:cccccccccccccccccccccccccccccccccccc;. ,:,:l;,;;c' .ccc:.  ...............';. ,0WNNNNNNN
// NNNNNNNNNNNNNNNNWK; :O00000x' 'ccccccccccccccccccccccccccccccccccccc;..:l:cloxkoo; .;ccc,. .;:;:::ccllodxkO0l. cXNNNNNNN
// NNNNNNNNNNNNNNNNWO' l0000O0d. ,ccccccccccccccccccccccccccccccccccccc;..lkxkkkkkkkc..,ccc:. 'k00000000000OO00x, .kWNNNNNN

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./ECDSA.sol";


interface CandyGramRender {
    struct RenderData {
        uint256 tokenId; 
        uint8 gramId;
        string gramName;
        uint256 gramStartBlock;
        uint256 gramStopBlock;
        uint256 tweetId;
        bytes32 renderKey;
        uint256 renderBlock;
        uint256 mintBlock;
        address owner;
        uint256 lastTransferBlock;
        int256 addressTokenCount; // 0x0 address will have a negative count
        uint256 totalTokenCount;
    }

    function render(RenderData calldata d) external view returns (string memory);
}


contract CandyGram is ERC721, ERC721Enumerable, Pausable, Ownable {
    using Counters for Counters.Counter;
    using ECDSA for bytes32; 


    ///////////////////////////////////////////////////////
    // Constants
    ///////////////////////////////////////////////////////
    address private constant ZERO_ADDRESS = 0x0000000000000000000000000000000000000000;


    ///////////////////////////////////////////////////////
    // Variables
    ///////////////////////////////////////////////////////

    // globals
    address public verifierAddress = ZERO_ADDRESS;
    address public renderAddress = ZERO_ADDRESS;

    uint256 public endBlock = 0;
    
    // token data
    Counters.Counter private _tokenIdCounter;

    struct Token {
        uint256 tweetId;
        uint8 gramId;
        uint256 mintBlock;
        uint256 renderedToken;
        uint256 lastTransferBlock;
        bytes32 renderKey;
    }

    mapping(uint256 => Token) tokens;
    mapping(address => int256) addressTokenCount;
    mapping(uint256 => uint256) tweetIdToTokenId;

    // gram data
    uint8 totalActiveGrams;

    struct Gram {
        Counters.Counter gramTokenCounter;
        string name;
        uint256 currentToken;
        uint256 mintPrice;
        uint16 tokenLimit;
        uint256 startBlock;
        uint256 stopBlock;
        uint256 lastTransferBlock;
        uint8 freeMintCount;
    }

    mapping(uint8 => Gram) grams;
    

    
    ///////////////////////////////////////////////////////
    // Contract Creation
    ///////////////////////////////////////////////////////
    constructor() ERC721("CandyGram", "CANDYGRAM") {}


    ///////////////////////////////////////////////////////
    // Boring Contract Administration
    ///////////////////////////////////////////////////////
    function pauseMinting() public onlyOwner {
        _pause();
    }

    function unpauseMinting() public onlyOwner {
        _unpause();
    }

    // turn off the minting of new grams/tokens as well as lock all the designs
    // you only get to do this once
    function killSwitch() public onlyOwner {
        endBlock = block.number;
    }

    function setVerifierAddress(address a) public onlyOwner {
        verifierAddress = a;
    }

    function setRenderAddress(address a) public onlyOwner {
        renderAddress = a;
    }

    ///////////////////////////////////////////////////////
    // Physical Gram Administration
    ///////////////////////////////////////////////////////

    // this will be used to start and restart each CandyGram type
    function setGramData(uint8 gramId,
                         string calldata name, 
                         uint16 tokenLimit,
                         uint256 mintPrice,
                         uint8 freeMintCount) 
        public 
        onlyOwner 
        isLive
    {
        require(grams[gramId].stopBlock == 0,"GRAM_STOPPED");

        grams[gramId].name = name;
        grams[gramId].tokenLimit = tokenLimit;
        grams[gramId].mintPrice = mintPrice;
        grams[gramId].freeMintCount = freeMintCount;
    }

    function startGram(uint8 gramId) 
        public 
        onlyOwner 
    {
        require(grams[gramId].startBlock == 0,"GRAM_ALREADY_STARTED");
        grams[gramId].startBlock = block.number;
    }

    function stopGramAndRevealFinalToken(uint8 gramId,uint256 randSeed) 
        public 
        onlyOwner
    {
        require(grams[gramId].gramTokenCounter.current() == grams[gramId].tokenLimit, "GRAM_MUST_BE_FULLY_MINTED");
        
        bytes32 prevRenderKey = keccak256(abi.encodePacked(gramId,block.number,randSeed));
        uint256 lastTokenId = grams[gramId].currentToken;
        tokens[lastTokenId].renderKey = prevRenderKey;
        
        grams[gramId].stopBlock = block.number;
    }

    ///////////////////////////////////////////////////////
    // Digital Token Administration
    ///////////////////////////////////////////////////////

    // only in case of scam/spam tweets
    function deleteTokenTweetId(uint256 tokenId) 
        public 
        onlyOwner 
        isLive
    {
        tokens[tokenId].tweetId = 0;
    }


    ///////////////////////////////////////////////////////
    // Public mint oooooohhhhhhh yeah
    ///////////////////////////////////////////////////////
    event NewTokenMinted(
        uint256 indexed tokenId,
        uint8 indexed gramId,
        address indexed to,
        uint256 revealedTokenId
    );


    function mint(address to, 
                      uint8 gramId, 
                      uint256 tweetId,
                      uint256 expTime,
                      uint256 ev1,
                      uint256 ev2,
                      bytes memory _signature) 
        public 
        payable
        whenNotPaused
        isGramMintable(gramId)
        isLive
    {
        require(tweetIdToTokenId[tweetId]==0, "TWEET_ALREADY_USED");
        require(_validateSignatureBeforeMint(to, gramId, tweetId, expTime,ev1,ev2,_signature), "INVALID_SIGNATURE");
        require(msg.value >= getGramMintPrice(gramId), "NOT_ENOUGH_ETH");

        // set render key of last token (this will reveal the previous token)
        bytes32 prevRenderKey = keccak256(abi.encodePacked(tweetId, gramId, _signature));
        uint256 lastTokenId = grams[gramId].currentToken;
        tokens[lastTokenId].renderKey = prevRenderKey;
        
        // increment counters
        _tokenIdCounter.increment();
        grams[gramId].gramTokenCounter.increment();

        // set new tokenId
        uint256 tokenId = _tokenIdCounter.current();
        
        // set token data
        tokens[tokenId].tweetId = tweetId;
        tokens[tokenId].gramId = gramId;
        tokens[tokenId].renderKey = 0x0;
        tokens[tokenId].mintBlock = block.number;
        tokens[tokenId].renderedToken = lastTokenId;

        // set Gram current token
        grams[gramId].currentToken = tokenId;

        // tweet can only be used once
        tweetIdToTokenId[tweetId] = tokenId;
        
        _safeMint(to, tokenId);

        emit NewTokenMinted(tokenId, gramId, to, lastTokenId);
    }

    // Track transfers in the contract to inform the rendering
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);

        if(endBlock==0){
            addressTokenCount[from] -= int256(batchSize);
            addressTokenCount[to] += int256(batchSize);
            tokens[tokenId].lastTransferBlock = block.number;
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }


    ///////////////////////////////////////////////////////
    // Get Values
    ///////////////////////////////////////////////////////
    function getTotalTokens() view public returns (uint256) {
        return _tokenIdCounter.current();
    }

    function getTokenByTweetId(uint256 tweetId) view public returns (uint256) {
        return tweetIdToTokenId[tweetId];
    }

    function getGramMintPrice(uint8 gramId) view public returns (uint256 mintPrice) {
        mintPrice = grams[gramId].mintPrice;
        if(grams[gramId].freeMintCount > grams[gramId].gramTokenCounter.current()){
            mintPrice = 0;
        }
    }

    function getGramData(uint8 gramId)
        view
        public
        returns (string memory name, 
                 uint256 currentToken, 
                 uint256 mintPrice, 
                 uint16 tokenLimit,
                 uint256 tokenCount,
                 uint256 lastMintBlock,
                 uint8 freeMintCount,
                 uint256 startBlock,
                 uint256 stopBlock)
    {
        name = grams[gramId].name;
        currentToken = grams[gramId].currentToken;
        mintPrice = grams[gramId].mintPrice;
        freeMintCount = grams[gramId].freeMintCount;
        tokenLimit = grams[gramId].tokenLimit;
        tokenCount = grams[gramId].gramTokenCounter.current();
        lastMintBlock = tokens[currentToken].mintBlock;
        startBlock = grams[gramId].startBlock;
        stopBlock = grams[gramId].stopBlock;
    }



    ///////////////////////////////////////////////////////
    // Verifiers, Validators & Modifiers oh my
    ///////////////////////////////////////////////////////
    function checkIsGramMintable(uint8 gramId) view public returns (bool){
        return (grams[gramId].startBlock != 0 
            && grams[gramId].stopBlock == 0 
            && grams[gramId].gramTokenCounter.current() < grams[gramId].tokenLimit);
    }

    modifier isGramMintable(uint8 gramId) {
        require(grams[gramId].startBlock != 0, "GRAM_NOT_ACTIVE");
        require(grams[gramId].stopBlock == 0, "GRAM_STOPPED_MINTING");
        require(grams[gramId].gramTokenCounter.current() < grams[gramId].tokenLimit, "TOKEN_LIMIT_REACHED");
        _;
    }

    function _isLive() view internal returns (bool) {
        require(endBlock==0, "MODIFICATIONS_HALTED");
        return true;
    }

    modifier isLive(){
        require(endBlock==0, "MODIFICATIONS_HALTED");
        _;
    }

    function _validateSignatureBeforeMint(address addr, uint8 gramId, uint256 tweetId, uint256 expTime, uint256 ev1, uint256 ev2, bytes memory _signature) view internal returns (bool) {
        require(verifierAddress != ZERO_ADDRESS, "VERIFIER_ADDRESS_NOT_SET");
        require(expTime > block.timestamp,"SIGNATURE_EXPIRED");

        bytes32 hashMessage = keccak256(
            abi.encode(addr, gramId, tweetId, expTime, ev1, ev2)
        );

        return verifierAddress == hashMessage.toEthSignedMessageHash().recover(_signature);

    }

    function tokenURI(uint256 tokenId) public override view returns (string memory) {
        require(renderAddress != ZERO_ADDRESS, "NO_RENDER_CONTRACT");

        uint8 gramId = tokens[tokenId].gramId;
        address owner = ownerOf(tokenId);
        uint256 renderBlock = endBlock;
        if(renderBlock==0){
            renderBlock = block.number;
        }

        CandyGramRender.RenderData memory rd = CandyGramRender.RenderData(
            {
                tokenId: tokenId,
                gramId: gramId,
                gramName: grams[gramId].name,
                gramStartBlock: grams[gramId].startBlock,
                gramStopBlock: grams[gramId].stopBlock,
                tweetId: tokens[tokenId].tweetId,
                renderKey: tokens[tokenId].renderKey,
                renderBlock: renderBlock,
                mintBlock: tokens[tokenId].mintBlock,
                owner: owner,
                lastTransferBlock: tokens[tokenId].lastTransferBlock,
                addressTokenCount: addressTokenCount[owner],
                totalTokenCount: _tokenIdCounter.current()
            }
        );
        return CandyGramRender(renderAddress).render(rd);
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;

        payable(msg.sender).transfer(balance);
    }

    receive () external payable {}

}

