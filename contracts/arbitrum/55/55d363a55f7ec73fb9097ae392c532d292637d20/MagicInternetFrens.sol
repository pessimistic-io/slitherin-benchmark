// SPDX-License-Identifier: MIT
/*
  

███╗░░░███╗██╗███████╗██████╗░███████╗███╗░░██╗░██████╗
████╗░████║██║██╔════╝██╔══██╗██╔════╝████╗░██║██╔════╝
██╔████╔██║██║█████╗░░██████╔╝█████╗░░██╔██╗██║╚█████╗░
██║╚██╔╝██║██║██╔══╝░░██╔══██╗██╔══╝░░██║╚████║░╚═══██╗
██║░╚═╝░██║██║██║░░░░░██║░░██║███████╗██║░╚███║██████╔╝
╚═╝░░░░░╚═╝╚═╝╚═╝░░░░░╚═╝░░╚═╝╚══════╝╚═╝░░╚══╝╚═════╝░


                               ▄▄▄▄,_
                           _▄████▀└████▄,
                       ▄███████▌   _▄█████▄_
                      ╓████████▄██▄╟██████████▄
                     ╓█████▀▀█████████████⌐ ╓████▄_
                     ╟███`     ╟███████████████████
                      ██▌     ▐████╙▀▐████████▀╙"╙▀" ,▄▄,
                     ,█▀       ,██▄▄ ▄▄█████w     ╒████████▄▄▄▄▄▄▄▄▄,,__
                              ª▀▀▀▀▀▀▀▀"" _,▄▄_▄▄█████████████████████▀▀
                            ╒██▄▄▄▄▄▄███████████████████████████▀▀╙"
                            ▐███████████████████▀▀▀▀▀╙╙"─
                         ▄██████████▀▀▀╙"`
                     ,▄███████▀""
                  ▄███████▀"                               _▄▄█▀▀████▄▄_
              ,▄████████▀                _,▄▄▄,_        ,███▀╓█▄   ╙█████▄
            ▄████████▀"             _▄█▀▀""╙▀██████▄ ╓█████▌ ╙▀"███L╙█████▌
             """╙"─               ▄███▐██▌╓██▄╙████████████▌ ╚█_`▀▀  ████▀
                              _▄█████" └█▄╙██▀ ╫████████████┐  ╙    '"─
                            '▀███████▌  "█─    ▐▀▀"  └"╙▀▀▀╙"         ▄▄_
                                 ╙▀▀██▌                           ,▄█████
                         ,▄▄▄▄▄▄▄▄,______              ___,▄▄▄█████████▀"
                        ██████████████████████████████████████████████▄
                        ╙██████████████████████████████████████████████
                            '╙▀▀█████████████████████████████████▀▀▀╙─
                                     `""╙"╙╙""╙╙╙╙""╙╙"""─`
 
█▀▄▀█ ▄▀█ █▀▀ █ █▀▀   █ █▄░█ ▀█▀ █▀▀ █▀█ █▄░█ █▀▀ ▀█▀   █▀▀ █▀█ █▀▀ █▄░█ █▀
█░▀░█ █▀█ █▄█ █ █▄▄   █ █░▀█ ░█░ ██▄ █▀▄ █░▀█ ██▄ ░█░   █▀░ █▀▄ ██▄ █░▀█ ▄█

*/
pragma solidity ^0.8.20;

import "./ERC721.sol";

interface IFrenURI {
    function tokenURI(uint256 id) external view returns (string memory);
}

contract MagicInternetFrens is ERC721 {
    IFrenURI public frenURI;

    mapping(uint256 => uint256) public levels;
    mapping(uint256 => string) public levelURI;
    mapping(address => bool) public isAuth;
    mapping(address => uint256) public frenTokenId;
    mapping(uint256 => address) public tokenIdFren;
    mapping(uint256 => uint256) public miXP; //magic Internet Experience Points
    mapping(uint256 => uint256) public miHP; //magic Internet Health Points
    mapping(address => uint256) public lastSpellTimeStamp;
    uint256 public _tokenIdCounter = 0;
    uint256 public maxSupply = 1111;
    address public owner;

    constructor() ERC721("Magic Internet Frens", "miFrens") {
        owner = msg.sender;
    }

    // Modifier to restrict access to owner only
    modifier onlyAuth() {
        require(msg.sender == owner || isAuth[msg.sender], "Caller is not the authorized");
        _;
    }

    function setIsAuth(address fren, bool isAuthorized) external onlyAuth {
        isAuth[fren] = isAuthorized;
    }

    function mint(address fren) public onlyAuth returns (uint256) {
        require(maxSupply > _tokenIdCounter, "Max Mint Reached");
        uint256 newTokenId = _tokenIdCounter;

        _mint(fren, newTokenId);
        levels[newTokenId] = 0; // Start at level 0
        miXP[newTokenId] = 0;
        miHP[newTokenId] = 100;
        _tokenIdCounter++;
        return newTokenId;
    }

    function SummonDedFren(address fren, uint256 _tokenId) public onlyAuth returns (uint256) {
        _mint(fren, _tokenId);
        miHP[_tokenId] = 100;
        frenTokenId[fren] = _tokenId;
        return _tokenId;
    }

    function setmiXP(uint256 tokenId, uint256 _miXP) public onlyAuth {
        miXP[tokenId] = _miXP;
    }

    function setmiHP(uint256 tokenId, uint256 _miHP) public onlyAuth {
        miHP[tokenId] = _miHP;
        if (_miHP <= 0) _burn(tokenId);
    }

    function levelUp(uint256 tokenId) public onlyAuth {
        levels[tokenId]++;
    }

    function levelDown(uint256 tokenId) public onlyAuth {
        levels[tokenId]--;
    }

    function setLevel(uint256 tokenId, uint256 level) public onlyAuth {
        levels[tokenId] = level;
    }

    function setLevelURI(uint256 level, string memory svgString) public onlyAuth {
        levelURI[level] = svgString;
    }

    function setTimeStamp(address fren, uint256 _lastSpellTimeStamp) public onlyAuth {
        lastSpellTimeStamp[fren] = _lastSpellTimeStamp;
    }

    function getURIForLevel(uint256 level) public view returns (string memory) {
        return levelURI[level];
    }

    function getSpellTimeStamp(address fren) public view returns (uint256) {
        return lastSpellTimeStamp[fren];
    }

    function getmiXP(uint256 tokenId) public view returns (uint256) {
        return miXP[tokenId];
    }

    function getmiHP(uint256 tokenId) public view returns (uint256) {
        return miHP[tokenId];
    }

    function getLevels(uint256 tokenId) public view returns (uint256) {
        return levels[tokenId];
    }

    function getTokenId() public view returns (uint256) {
        return _tokenIdCounter;
    }

    function getFrenId(address _fren) public view returns (uint256) {
        return frenTokenId[_fren];
    }

    function getIdFren(uint256 _id) public view returns (address) {
        return tokenIdFren[_id];
    }

    function signUp(uint256 _id) public returns (address) {
        require(ownerOf(_id) == msg.sender, "Not Auth");
        frenTokenId[ownerOf(_id)] = _id;
        tokenIdFren[_id] = msg.sender;

        return tokenIdFren[_id];
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        return frenURI.tokenURI(id);
    }

    function burnFren(uint256 _id) external onlyAuth {
        _burn(_id);
        delete frenTokenId[ownerOf(_id)];
        delete tokenIdFren[_id];
    }

    // Helper function to convert uint256 to string
    function toString(uint256 value) internal pure returns (string memory) {
        // Convert a uint256 to a string
        // Implementation omitted for brevity
    }

    function setFrenUri(IFrenURI _renderer) external onlyAuth {
        frenURI = _renderer;
    }
}

